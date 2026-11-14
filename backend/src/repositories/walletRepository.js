const { query, withTransaction } = require('../config/db');
const ApiError = require('../utils/ApiError');
const { monthEnd, toDateOnly } = require('../utils/dates');

function toWallet(row) {
  return {
    id: row.id,
    userId: row.user_id,
    name: row.name,
    initialAmount: Number(row.initial_amount),
    startDate: toDateOnly(row.start_date),
    currency: row.currency,
    balance: Number(row.balance),
    savingsAmount: Number(row.savings_amount || 0),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function findByUserId(userId) {
  const { rows } = await query(
    `SELECT * FROM wallets WHERE user_id = $1 ORDER BY created_at ASC`,
    [userId]
  );
  return rows.map(toWallet);
}

async function findById(walletId) {
  const { rows } = await query('SELECT * FROM wallets WHERE id = $1 LIMIT 1', [walletId]);
  return rows[0] ? toWallet(rows[0]) : null;
}

async function create({ userId, name, initialAmount, startDate, currency }) {
  return withTransaction(async (client) => {
    const { rows } = await client.query(
      `INSERT INTO wallets (user_id, name, initial_amount, start_date, currency, balance)
       VALUES ($1, $2, $3, $4, $5, $3)
       RETURNING *`,
      [userId, name, initialAmount, startDate, currency]
    );
    const wallet = toWallet(rows[0]);

    await client.query(
      `INSERT INTO periods (user_id, wallet_id, start_date, end_date, status)
       VALUES ($1, $2, $3, $4, 'active')`,
      [userId, wallet.id, startDate, monthEnd(startDate)]
    );

    if (initialAmount > 0) {
      await client.query(
        `INSERT INTO initial_amount_history (wallet_id, old_value, new_value) VALUES ($1, 0, $2)`,
        [wallet.id, initialAmount]
      );
    }
    return wallet;
  });
}

async function reservedSavings(client, walletId) {
  const { rows } = await client.query(
    'SELECT COALESCE(SUM(saved_amount), 0) AS total FROM goals WHERE wallet_id = $1',
    [walletId]
  );
  return Number(rows[0].total);
}

/**
 * Modifie le montant initial de façon atomique :
 * - met à jour initial_amount et balance (le solde suit le delta),
 * - enregistre l'historique, le tout dans la même transaction SQL.
 */
async function updateInitialAmount(walletId, newAmount) {
  return withTransaction(async (client) => {
    const current = await client.query(
      'SELECT initial_amount, balance FROM wallets WHERE id = $1 FOR UPDATE',
      [walletId]
    );
    if (current.rows.length === 0) return null;
    const oldValue = Number(current.rows[0].initial_amount);
    const balance = Number(current.rows[0].balance);
    const reserved = await reservedSavings(client, walletId);
    const newBalance = balance + (newAmount - oldValue);

    if (newBalance < reserved) {
      throw ApiError.conflict(
        'SAVINGS_LOCKED',
        'Ce montant est déjà réservé dans tes objectifs d’épargne',
        { reserved }
      );
    }

    const { rows } = await client.query(
      `UPDATE wallets
       SET initial_amount = $2::bigint,
           balance = balance + ($2::bigint - initial_amount),
           updated_at = now()
       WHERE id = $1
       RETURNING *`,
      [walletId, newAmount]
    );
    await client.query(
      `INSERT INTO initial_amount_history (wallet_id, old_value, new_value) VALUES ($1, $2, $3)`,
      [walletId, oldValue, newAmount]
    );
    return toWallet(rows[0]);
  });
}

/**
 * Fixe le montant mis de côté (réserve interne au solde).
 * Le trigger SQL rabaisse automatiquement l'épargne si le solde a changé.
 */
async function setSavings(walletId, amount) {
  return withTransaction(async (client) => {
    const locked = await client.query('SELECT balance FROM wallets WHERE id = $1 FOR UPDATE', [
      walletId,
    ]);
    if (locked.rows.length === 0) return null;

    const reserved = await reservedSavings(client, walletId);
    if (amount < reserved) {
      throw ApiError.conflict(
        'SAVINGS_LOCKED',
        'Une partie de ton épargne est déjà réservée dans tes objectifs',
        { reserved }
      );
    }

    const { rows } = await client.query(
      `UPDATE wallets
       SET savings_amount = $2::bigint, updated_at = now()
       WHERE id = $1
       RETURNING *`,
      [walletId, amount]
    );
    return toWallet(rows[0]);
  });
}

async function getInitialAmountHistory(walletId) {
  const { rows } = await query(
    `SELECT id, old_value, new_value, changed_at
     FROM initial_amount_history WHERE wallet_id = $1
     ORDER BY changed_at DESC LIMIT 100`,
    [walletId]
  );
  return rows.map((r) => ({
    id: r.id,
    oldValue: Number(r.old_value),
    newValue: Number(r.new_value),
    changedAt: r.changed_at,
  }));
}

/**
 * Repart à zéro : efface toutes les transactions, budgets, objectifs,
 * périodes et historique des montants initiaux du portefeuille, remet le solde
 * (et l'épargne) à 0 et recrée une période active démarrant aujourd'hui.
 */
async function reset(walletId) {
  return withTransaction(async (client) => {
    await client.query('DELETE FROM transactions WHERE wallet_id = $1', [walletId]);
    await client.query('DELETE FROM budgets WHERE wallet_id = $1', [walletId]);
    await client.query('DELETE FROM goals WHERE wallet_id = $1', [walletId]);
    await client.query('DELETE FROM periods WHERE wallet_id = $1', [walletId]);
    await client.query('DELETE FROM initial_amount_history WHERE wallet_id = $1', [walletId]);

    const today = new Date().toISOString().slice(0, 10);
    const { rows } = await client.query(
      `UPDATE wallets
       SET balance = 0,
           initial_amount = 0,
           savings_amount = 0,
           start_date = $2,
           updated_at = now()
       WHERE id = $1
       RETURNING *`,
      [walletId, today]
    );

    if (rows.length === 0) return null;
    const wallet = toWallet(rows[0]);

    await client.query(
      `INSERT INTO periods (user_id, wallet_id, start_date, end_date, status)
       VALUES ((SELECT user_id FROM wallets WHERE id = $1), $1, $2, $3, 'active')`,
      [wallet.id, today, monthEnd(today)]
    );

    return wallet;
  });
}

module.exports = {
  toWallet,
  findByUserId,
  findById,
  create,
  updateInitialAmount,
  setSavings,
  getInitialAmountHistory,
  reset,
};
