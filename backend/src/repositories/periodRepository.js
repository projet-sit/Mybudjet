const { query, withTransaction } = require('../config/db');
const ApiError = require('../utils/ApiError');
const { todayIso, toDateOnly, monthEnd, daysBetween } = require('../utils/dates');
const { toWallet } = require('./walletRepository');

const UNDO_WINDOW_MS = 10000;

function toPeriod(row) {
  if (!row) return null;
  return {
    id: row.id,
    userId: row.user_id,
    walletId: row.wallet_id,
    startDate: toDateOnly(row.start_date),
    endDate: toDateOnly(row.end_date),
    status: row.status,
    snapshot: row.snapshot || null,
    createdAt: row.created_at,
    closedAt: row.closed_at,
  };
}

async function findActive(walletId) {
  const { rows } = await query(
    `SELECT * FROM periods
     WHERE wallet_id = $1 AND status = 'active'
     LIMIT 1`,
    [walletId]
  );
  return rows[0] ? toPeriod(rows[0]) : null;
}

async function ensureActiveWithClient(client, wallet) {
  const active = await client.query(
    `SELECT * FROM periods
     WHERE wallet_id = $1 AND status = 'active'
     FOR UPDATE`,
    [wallet.id]
  );
  if (active.rows[0]) return toPeriod(active.rows[0]);

  const today = todayIso();
  const walletStart = toDateOnly(wallet.start_date) || today;
  const firstOfMonth = `${today.slice(0, 8)}01`;
  const startDate = walletStart < firstOfMonth ? firstOfMonth : walletStart;
  const { rows } = await client.query(
    `INSERT INTO periods (user_id, wallet_id, start_date, end_date, status)
     VALUES ($1, $2, $3, $4, 'active')
     RETURNING *`,
    [wallet.user_id, wallet.id, startDate, monthEnd(startDate)]
  );
  return toPeriod(rows[0]);
}

async function ensureActive(walletId) {
  return withTransaction(async (client) => {
    const { rows } = await client.query(
      'SELECT id, user_id, start_date FROM wallets WHERE id = $1 FOR UPDATE',
      [walletId]
    );
    if (!rows[0]) throw ApiError.notFound('Portefeuille introuvable');
    return ensureActiveWithClient(client, rows[0]);
  });
}

async function getInfo(walletId) {
  let period = await findActive(walletId);
  if (!period) period = await ensureActive(walletId);

  const today = todayIso();
  const needsNewPeriod = today > period.endDate;
  return {
    period,
    needsNewPeriod,
    daysLeft: Math.max(0, daysBetween(today, period.endDate)),
  };
}

async function nextPeriod({ walletId, userId, mode, today = todayIso() }) {
  return withTransaction(async (client) => {
    const walletRes = await client.query(
      'SELECT * FROM wallets WHERE id = $1 AND user_id = $2 FOR UPDATE',
      [walletId, userId]
    );
    if (!walletRes.rows[0]) throw ApiError.notFound('Portefeuille introuvable');
    const wallet = walletRes.rows[0];

    const active = await ensureActiveWithClient(client, wallet);

    const totals = await client.query(
      `SELECT
         COALESCE(SUM(CASE WHEN type = 'expense' THEN amount END), 0) AS expenses,
         COALESCE(SUM(CASE WHEN type = 'income' THEN amount END), 0) AS incomes,
         COUNT(*) AS count
       FROM transactions WHERE wallet_id = $1 AND period_id = $2`,
      [walletId, active.id]
    );

    const goals = await client.query(
      'SELECT COALESCE(SUM(saved_amount), 0) AS total FROM goals WHERE wallet_id = $1',
      [walletId]
    );
    const goalsSaved = Number(goals.rows[0].total);

    const previousWallet = {
      initialAmount: Number(wallet.initial_amount),
      balance: Number(wallet.balance),
      savingsAmount: Number(wallet.savings_amount || 0),
      startDate: toDateOnly(wallet.start_date),
    };

    const archivedSnapshot = {
      wallet: previousWallet,
      totals: {
        expenses: Number(totals.rows[0].expenses),
        incomes: Number(totals.rows[0].incomes),
        transactions: Number(totals.rows[0].count),
      },
      closedAt: new Date().toISOString(),
    };

    await client.query(
      `UPDATE periods
       SET status = 'archived', snapshot = $2::jsonb, closed_at = now()
       WHERE id = $1`,
      [active.id, JSON.stringify(archivedSnapshot)]
    );

    const isReset = mode === 'reset';
    const newInitial = isReset ? goalsSaved : previousWallet.balance;
    const newBalance = isReset ? goalsSaved : previousWallet.balance;
    const newSavings = isReset ? goalsSaved : previousWallet.savingsAmount;
    const startDate = today;
    const endDate = monthEnd(today);

    const newPeriod = await client.query(
      `INSERT INTO periods (user_id, wallet_id, start_date, end_date, status, snapshot)
       VALUES ($1, $2, $3, $4, 'active', $5::jsonb)
       RETURNING *`,
      [
        userId,
        walletId,
        startDate,
        endDate,
        JSON.stringify({
          previousPeriodId: active.id,
          previousWallet,
          previousGoalsSaved: goalsSaved,
        }),
      ]
    );

    const updatedWallet = await client.query(
      `UPDATE wallets
       SET initial_amount = $2::bigint,
           balance = $3::bigint,
           savings_amount = $4::bigint,
           start_date = $5,
           updated_at = now()
       WHERE id = $1
       RETURNING *`,
      [walletId, newInitial, newBalance, newSavings, startDate]
    );

    if (newInitial !== previousWallet.initialAmount) {
      await client.query(
        `INSERT INTO initial_amount_history (wallet_id, old_value, new_value)
         VALUES ($1, $2, $3)`,
        [walletId, previousWallet.initialAmount, newInitial]
      );
    }

    return {
      period: toPeriod(newPeriod.rows[0]),
      wallet: toWallet(updatedWallet.rows[0]),
      previousPeriodId: active.id,
      mode,
      undoExpiresAt: new Date(Date.now() + UNDO_WINDOW_MS).toISOString(),
    };
  });
}

/**
 * Remise à zéro avec archivage :
 * 1. archive la période active (snapshot complet : solde, épargne, totaux) —
 *    l'historique est CONSERVÉ, les stats y ont toujours accès ;
 * 2. crée une nouvelle période active démarrant aujourd'hui ;
 * 3. solde remis à zéro (l'épargne est conservée sauf includeSavings,
 *    auquel cas elle retourne aussi à zéro) ;
 * 4. annulation possible pendant 10 s via undoPeriod (snapshot précédent).
 */
async function resetWithArchive({ walletId, userId, includeSavings = false, today = todayIso() }) {
  return withTransaction(async (client) => {
    const walletRes = await client.query(
      'SELECT * FROM wallets WHERE id = $1 AND user_id = $2 FOR UPDATE',
      [walletId, userId]
    );
    if (!walletRes.rows[0]) throw ApiError.notFound('Portefeuille introuvable');
    const wallet = walletRes.rows[0];

    const active = await ensureActiveWithClient(client, wallet);

    const totals = await client.query(
      `SELECT
         COALESCE(SUM(CASE WHEN type = 'expense' THEN amount END), 0) AS expenses,
         COALESCE(SUM(CASE WHEN type = 'income' THEN amount END), 0) AS incomes,
         COALESCE(SUM(CASE WHEN type = 'savings_deposit' THEN amount END), 0) AS saved,
         COUNT(*) AS count
       FROM transactions WHERE wallet_id = $1 AND period_id = $2`,
      [walletId, active.id]
    );

    const goals = await client.query(
      'SELECT COALESCE(SUM(saved_amount), 0) AS total FROM goals WHERE wallet_id = $1',
      [walletId]
    );
    const goalsSaved = Number(goals.rows[0].total);

    const previousWallet = {
      initialAmount: Number(wallet.initial_amount),
      balance: Number(wallet.balance),
      savingsAmount: Number(wallet.savings_amount || 0),
      startDate: toDateOnly(wallet.start_date),
    };

    const archivedSnapshot = {
      wallet: previousWallet,
      totals: {
        expenses: Number(totals.rows[0].expenses),
        incomes: Number(totals.rows[0].incomes),
        saved: Number(totals.rows[0].saved),
        transactions: Number(totals.rows[0].count),
      },
      goalsSaved,
      reason: 'reset',
      closedAt: new Date().toISOString(),
    };

    await client.query(
      `UPDATE periods
       SET status = 'archived', snapshot = $2::jsonb, closed_at = now()
       WHERE id = $1`,
      [active.id, JSON.stringify(archivedSnapshot)]
    );

    const keptSavings = includeSavings ? 0 : previousWallet.savingsAmount;
    const newBalance = keptSavings; // Reste = 0 ; argent total = épargne conservée
    const startDate = today;
    const endDate = monthEnd(today);

    const newPeriod = await client.query(
      `INSERT INTO periods (user_id, wallet_id, start_date, end_date, status, snapshot)
       VALUES ($1, $2, $3, $4, 'active', $5::jsonb)
       RETURNING *`,
      [
        userId,
        walletId,
        startDate,
        endDate,
        JSON.stringify({
          previousPeriodId: active.id,
          previousWallet,
          previousGoalsSaved: goalsSaved,
          includeSavings,
        }),
      ]
    );

    const updatedWallet = await client.query(
      `UPDATE wallets
       SET initial_amount = $2::bigint,
           balance = $3::bigint,
           savings_amount = $4::bigint,
           start_date = $5,
           updated_at = now()
       WHERE id = $1
       RETURNING *`,
      [walletId, keptSavings, newBalance, keptSavings, startDate]
    );

    await client.query(
      `INSERT INTO initial_amount_history (wallet_id, old_value, new_value)
       VALUES ($1, $2, $3)`,
      [walletId, previousWallet.balance, keptSavings]
    );

    return {
      period: toPeriod(newPeriod.rows[0]),
      wallet: toWallet(updatedWallet.rows[0]),
      previousPeriodId: active.id,
      mode: 'reset',
      undoExpiresAt: new Date(Date.now() + UNDO_WINDOW_MS).toISOString(),
    };
  });
}

async function undoPeriod({ walletId, userId, periodId }) {
  return withTransaction(async (client) => {
    const walletRes = await client.query(
      'SELECT * FROM wallets WHERE id = $1 AND user_id = $2 FOR UPDATE',
      [walletId, userId]
    );
    if (!walletRes.rows[0]) throw ApiError.notFound('Portefeuille introuvable');

    const newPeriodRes = await client.query(
      `SELECT * FROM periods
       WHERE id = $1 AND wallet_id = $2 AND status = 'active'
       FOR UPDATE`,
      [periodId, walletId]
    );
    if (!newPeriodRes.rows[0]) throw ApiError.notFound('Période introuvable');
    const newPeriod = toPeriod(newPeriodRes.rows[0]);

    if (Date.now() - new Date(newPeriod.createdAt).getTime() > UNDO_WINDOW_MS) {
      throw ApiError.conflict(
        'UNDO_EXPIRED',
        "Le délai d'annulation est dépassé (10 secondes)"
      );
    }

    const previousPeriodId = newPeriod.snapshot && newPeriod.snapshot.previousPeriodId;
    const previousWallet = (newPeriod.snapshot && newPeriod.snapshot.previousWallet) || null;
    if (!previousPeriodId || !previousWallet) {
      throw ApiError.conflict('UNDO_UNAVAILABLE', 'Cette réinitialisation ne peut pas être annulée');
    }

    const count = await client.query(
      'SELECT COUNT(*) AS count FROM transactions WHERE period_id = $1',
      [periodId]
    );
    if (Number(count.rows[0].count) > 0) {
      throw ApiError.conflict(
        'UNDO_UNAVAILABLE',
        'Des transactions existent déjà sur cette période'
      );
    }

    const goals = await client.query(
      'SELECT COALESCE(SUM(saved_amount), 0) AS total FROM goals WHERE wallet_id = $1',
      [walletId]
    );
    if (Number(goals.rows[0].total) !== Number(newPeriod.snapshot.previousGoalsSaved || 0)) {
      throw ApiError.conflict(
        'UNDO_UNAVAILABLE',
        'Tes objectifs ont changé depuis la réinitialisation'
      );
    }

    const previous = await client.query(
      'SELECT * FROM periods WHERE id = $1 FOR UPDATE',
      [previousPeriodId]
    );
    if (!previous.rows[0] || previous.rows[0].status !== 'archived') {
      throw ApiError.conflict('UNDO_UNAVAILABLE', "La période précédente n'est plus disponible");
    }

    await client.query('DELETE FROM periods WHERE id = $1', [periodId]);
    const restored = await client.query(
      `UPDATE periods
       SET status = 'active', snapshot = NULL, closed_at = NULL
       WHERE id = $1
       RETURNING *`,
      [previousPeriodId]
    );

    const updatedWallet = await client.query(
      `UPDATE wallets
       SET initial_amount = $2::bigint,
           balance = $3::bigint,
           savings_amount = $4::bigint,
           start_date = $5,
           updated_at = now()
       WHERE id = $1
       RETURNING *`,
      [
        walletId,
        previousWallet.initialAmount,
        previousWallet.balance,
        previousWallet.savingsAmount,
        previousWallet.startDate,
      ]
    );

    return {
      period: toPeriod(restored.rows[0]),
      wallet: toWallet(updatedWallet.rows[0]),
    };
  });
}

module.exports = {
  toPeriod,
  findActive,
  ensureActive,
  ensureActiveWithClient,
  getInfo,
  nextPeriod,
  undoPeriod,
  resetWithArchive,
};
