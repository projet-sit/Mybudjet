const { query, withTransaction } = require('../config/db');
const ApiError = require('../utils/ApiError');
const { toDateOnly } = require('../utils/dates');
const periodRepository = require('./periodRepository');

function toTransaction(row) {
  return {
    id: row.id,
    walletId: row.wallet_id,
    periodId: row.period_id,
    type: row.type,
    amount: Number(row.amount),
    category: row.category,
    categoryId: row.category_id ?? null,
    description: row.description,
    date: toDateOnly(row.date),
    time: row.time,
    paymentMethod: row.payment_method,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

/**
 * Opération d'épargne atomique (versement / retrait) :
 * 1. verrouille le portefeuille (FOR UPDATE),
 * 2. vérifie la capacité (versement ≤ Reste / retrait ≤ épargne),
 * 3. insère la transaction d'épargne (rattachée à la période active),
 * 4. met à jour savings_amount — le solde (balance) ne bouge pas :
 *    l'argent reste dans le même compte, seul le « Reste » varie.
 */
async function createSavingsTransaction({ walletId, type, amount, date, time }) {
  return withTransaction(async (client) => {
    const locked = await client.query(
      'SELECT id, user_id, balance, savings_amount, start_date FROM wallets WHERE id = $1 FOR UPDATE',
      [walletId]
    );
    if (locked.rows.length === 0) {
      throw ApiError.notFound('Portefeuille introuvable');
    }
    const balance = Number(locked.rows[0].balance);
    const savings = Number(locked.rows[0].savings_amount || 0);
    const available = balance - savings;

    if (type === 'savings_deposit' && amount > available) {
      throw ApiError.conflict(
        'BALANCE_INSUFFICIENT',
        'Versement impossible : le montant dépasse le Reste disponible',
        { available, requested: amount }
      );
    }
    if (type === 'savings_withdrawal' && amount > savings) {
      throw ApiError.conflict(
        'SAVINGS_INSUFFICIENT',
        'Retrait impossible : le montant dépasse l’épargne disponible',
        { savings, requested: amount }
      );
    }

    const period = await periodRepository.ensureActiveWithClient(client, locked.rows[0]);

    const { rows } = await client.query(
      `INSERT INTO transactions (wallet_id, period_id, type, amount, category, description, date, time, payment_method)
       VALUES ($1, $2, $3, $4, 'Épargne', NULL, $5, $6, NULL)
       RETURNING *`,
      [walletId, period.id, type, amount, date, time]
    );
    const transaction = toTransaction(rows[0]);

    const delta = type === 'savings_deposit' ? amount : -amount;
    const updated = await client.query(
      'UPDATE wallets SET savings_amount = savings_amount + $2::bigint, updated_at = now() WHERE id = $1 RETURNING *',
      [walletId, delta]
    );

    return { transaction, wallet: updated.rows[0] };
  });
}

/** Retrait total : toute l'épargne retourne dans le Reste, une seule écriture. */
async function withdrawAllSavings({ walletId, date, time }) {
  return withTransaction(async (client) => {
    const locked = await client.query(
      'SELECT id, user_id, balance, savings_amount, start_date FROM wallets WHERE id = $1 FOR UPDATE',
      [walletId]
    );
    if (locked.rows.length === 0) {
      throw ApiError.notFound('Portefeuille introuvable');
    }
    const savings = Number(locked.rows[0].savings_amount || 0);

    if (savings === 0) {
      const period = await periodRepository.ensureActiveWithClient(client, locked.rows[0]);
      void period; // période active garantie, aucun mouvement à écrire
      return { transaction: null, wallet: locked.rows[0] };
    }

    const period = await periodRepository.ensureActiveWithClient(client, locked.rows[0]);

    const { rows } = await client.query(
      `INSERT INTO transactions (wallet_id, period_id, type, amount, category, description, date, time, payment_method)
       VALUES ($1, $2, 'savings_withdrawal', $3, 'Épargne', NULL, $4, $5, NULL)
       RETURNING *`,
      [walletId, period.id, savings, date, time]
    );
    const transaction = toTransaction(rows[0]);

    const updated = await client.query(
      'UPDATE wallets SET savings_amount = 0, updated_at = now() WHERE id = $1 RETURNING *',
      [walletId]
    );

    return { transaction, wallet: updated.rows[0] };
  });
}

/**
 * Crée une transaction de façon ATOMIQUE :
 * 1. verrouille la ligne du portefeuille (FOR UPDATE → sérialise les écritures concurrentes),
 * 2. vérifie le solde disponible pour une dépense,
 * 3. insère la transaction,
 * 4. met à jour le solde,
 * le tout dans une seule transaction SQL (commit/rollback ensemble).
 */
async function createTransaction({ walletId, type, amount, category, categoryId, description, date, time, paymentMethod }) {
  return withTransaction(async (client) => {
    const locked = await client.query(
      'SELECT id, user_id, initial_amount, balance, savings_amount, start_date FROM wallets WHERE id = $1 FOR UPDATE',
      [walletId]
    );
    if (locked.rows.length === 0) {
      throw ApiError.notFound('Portefeuille introuvable');
    }
    const currentBalance = Number(locked.rows[0].balance);
    const available = currentBalance - Number(locked.rows[0].savings_amount || 0);
    const initialAmount = Number(locked.rows[0].initial_amount || 0);
    const savingsAmount = Number(locked.rows[0].savings_amount || 0);
    const period = await periodRepository.ensureActiveWithClient(client, locked.rows[0]);

    // Règle « Budget du mois » : une dépense ne doit jamais dépasser le reste
    // du budget (devise de référence XOF, entiers).
    if (type === 'expense') {
      const sums = await client.query(
        `SELECT COALESCE(SUM(CASE WHEN type = 'income' THEN amount END), 0) AS income,
                COALESCE(SUM(CASE WHEN type = 'expense' THEN amount END), 0) AS spent
         FROM transactions WHERE wallet_id = $1 AND period_id = $2`,
        [walletId, period.id]
      );
      const income = Number(sums.rows[0].income);
      const spent = Number(sums.rows[0].spent);
      const base = initialAmount + income - savingsAmount;
      if (base > 0) {
        const remaining = Math.max(0, base - spent);
        if (amount > remaining) {
          throw ApiError.conflict(
            'BUDGET_EXCEEDED',
            `Montant supérieur au budget restant (${remaining} FCFA)`,
            { remaining, budget: base, spent }
          );
        }
      }
    }

    if (type === 'expense' && amount > available) {
      throw ApiError.conflict(
        'BALANCE_INSUFFICIENT',
        'Solde disponible insuffisant pour cette dépense',
        { balance: currentBalance, available, requested: amount }
      );
    }

    const { rows } = await client.query(
      `INSERT INTO transactions (wallet_id, period_id, type, amount, category, category_id, description, date, time, payment_method)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
       RETURNING *`,
      [walletId, period.id, type, amount, category, categoryId ?? null, description, date, time, paymentMethod]
    );
    const transaction = toTransaction(rows[0]);

    const delta = type === 'expense' ? -amount : amount;
    const updated = await client.query(
      'UPDATE wallets SET balance = balance + $2::bigint, updated_at = now() WHERE id = $1 RETURNING balance',
      [walletId, delta]
    );

    return { transaction, newBalance: Number(updated.rows[0].balance) };
  });
}

/**
 * Modifie une transaction de façon ATOMIQUE :
 * le solde est corrigé par le delta entre l'ancienne et la nouvelle contribution.
 */
async function updateTransaction({ walletId, txId, type, amount, category, categoryId, description, date, time, paymentMethod }) {
  return withTransaction(async (client) => {
    const locked = await client.query(
      'SELECT id, user_id, start_date, initial_amount, balance, savings_amount FROM wallets WHERE id = $1 FOR UPDATE',
      [walletId]
    );
    if (locked.rows.length === 0) throw ApiError.notFound('Portefeuille introuvable');
    const currentBalance = Number(locked.rows[0].balance);
    const currentAvailable =
      currentBalance - Number(locked.rows[0].savings_amount || 0);
    const initialAmount = Number(locked.rows[0].initial_amount || 0);
    const savingsAmount = Number(locked.rows[0].savings_amount || 0);

    const existing = await client.query(
      'SELECT * FROM transactions WHERE id = $1 AND wallet_id = $2 FOR UPDATE',
      [txId, walletId]
    );
    if (existing.rows.length === 0) throw ApiError.notFound('Transaction introuvable');
    const old = toTransaction(existing.rows[0]);

    if (old.type === 'savings_deposit' || old.type === 'savings_withdrawal') {
      throw ApiError.validation('Une opération d’épargne se gère depuis l’écran Épargne', {
        field: 'type',
      });
    }

    // Règle « Budget du mois » : une dépense ne doit jamais dépasser le reste
    // du budget ; l'ancien montant de cette opération est inclus dans le reste.
    if (type === 'expense' || old.type === 'expense') {
      const period = await periodRepository.ensureActiveWithClient(client, locked.rows[0]);
      const sums = await client.query(
        `SELECT COALESCE(SUM(CASE WHEN type = 'income' THEN amount END), 0) AS income,
                COALESCE(SUM(CASE WHEN type = 'expense' THEN amount END), 0) AS spent
         FROM transactions WHERE wallet_id = $1 AND period_id = $2 AND id <> $3`,
        [walletId, period.id, txId]
      );
      const income = Number(sums.rows[0].income);
      const spentExcludingSelf = Number(sums.rows[0].spent);
      const base = initialAmount + income - savingsAmount;
      const newDelta = type === 'expense' ? amount : 0;
      if (base > 0 && spentExcludingSelf + newDelta > base) {
        const remaining = Math.max(0, base - spentExcludingSelf);
        throw ApiError.conflict(
          'BUDGET_EXCEEDED',
          `Montant supérieur au budget restant (${remaining} FCFA)`,
          { remaining, budget: base, spent: spentExcludingSelf + newDelta }
        );
      }
    }

    const contribution = (t, a) => (t === 'expense' ? -a : a);
    const delta = contribution(type, amount) - contribution(old.type, old.amount);

    // Le solde disponible ne doit jamais devenir négatif suite à la modification.
    if (currentAvailable + delta < 0) {
      throw ApiError.conflict('BALANCE_INSUFFICIENT', 'Modification impossible : solde insuffisant', {
        balance: currentBalance,
        available: currentAvailable,
      });
    }

    const { rows } = await client.query(
      `UPDATE transactions
       SET type = $2, amount = $3, category = $4, category_id = COALESCE($5::uuid, category_id),
           description = $6, date = $7, time = $8, payment_method = $9, updated_at = now()
       WHERE id = $1
       RETURNING *`,
      [txId, type, amount, category, categoryId ?? null, description, date, time, paymentMethod]
    );
    const transaction = toTransaction(rows[0]);

    const updated = await client.query(
      'UPDATE wallets SET balance = balance + $2::bigint, updated_at = now() WHERE id = $1 RETURNING balance',
      [walletId, delta]
    );

    return { transaction, newBalance: Number(updated.rows[0].balance) };
  });
}

/** Supprime une transaction de façon atomique (le solde récupère la contribution). */
async function deleteTransaction({ walletId, txId }) {
  return withTransaction(async (client) => {
    const locked = await client.query(
      'SELECT balance FROM wallets WHERE id = $1 FOR UPDATE',
      [walletId]
    );
    if (locked.rows.length === 0) throw ApiError.notFound('Portefeuille introuvable');
    const currentBalance = Number(locked.rows[0].balance);

    const existing = await client.query(
      'SELECT * FROM transactions WHERE id = $1 AND wallet_id = $2 FOR UPDATE',
      [txId, walletId]
    );
    if (existing.rows.length === 0) throw ApiError.notFound('Transaction introuvable');
    const old = toTransaction(existing.rows[0]);

    await client.query('DELETE FROM transactions WHERE id = $1', [txId]);

    const isSavings = old.type === 'savings_deposit' || old.type === 'savings_withdrawal';
    const delta = old.type === 'expense' ? old.amount : (isSavings ? 0 : -old.amount);
    const savingsDelta = old.type === 'savings_deposit' ? -old.amount
      : old.type === 'savings_withdrawal' ? old.amount
      : 0;
    const updated = await client.query(
      `UPDATE wallets SET
         balance = balance + $2::bigint,
         savings_amount = GREATEST(0, savings_amount + $3::bigint),
         updated_at = now()
       WHERE id = $1 RETURNING balance, savings_amount`,
      [walletId, delta, savingsDelta]
    );

    return { newBalance: Number(updated.rows[0].balance) };
  });
}

/** Récupère une transaction de l'utilisateur (isolation via wallet). */
async function getTransactionForWallet({ walletId, txId }) {
  const { rows } = await query(
    'SELECT * FROM transactions WHERE id = $1 AND wallet_id = $2 LIMIT 1',
    [txId, walletId]
  );
  return rows[0] ? toTransaction(rows[0]) : null;
}

/** Recalcule le solde depuis le montant initial et les transactions de la période active. */
async function recalculateBalance(walletId) {
  return withTransaction(async (client) => {
    const locked = await client.query(
      'SELECT id, user_id, initial_amount, start_date FROM wallets WHERE id = $1 FOR UPDATE',
      [walletId]
    );
    if (locked.rows.length === 0) throw ApiError.notFound('Portefeuille introuvable');
    const initial = Number(locked.rows[0].initial_amount);
    const period = await periodRepository.ensureActiveWithClient(client, locked.rows[0]);

    const sums = await client.query(
      `SELECT
         COALESCE(SUM(CASE WHEN type = 'income' THEN amount END), 0) AS income,
         COALESCE(SUM(CASE WHEN type = 'expense' THEN amount END), 0) AS expense
       FROM transactions WHERE wallet_id = $1 AND period_id = $2`,
      [walletId, period.id]
    );
    const income = Number(sums.rows[0].income);
    const expense = Number(sums.rows[0].expense);
    const balance = initial + income - expense;

    await client.query(
      'UPDATE wallets SET balance = $2::bigint, updated_at = now() WHERE id = $1',
      [walletId, balance]
    );
    return { balance, income, expense, initial };
  });
}

/**
 * Liste paginée + filtrable (Phase 7) :
 * type, category, dateFrom, dateTo, minAmount, maxAmount, search,
 * tri par date/montant, pagination.
 */
async function listTransactions({
  walletId,
  periodId,
  type,
  category,
  dateFrom,
  dateTo,
  minAmount,
  maxAmount,
  search,
  sortBy = 'date',
  sortDir = 'desc',
  page = 1,
  limit = 20,
}) {
  const conditions = ['wallet_id = $1'];
  const params = [walletId];
  const add = (clause, value) => {
    params.push(value);
    conditions.push(clause.replace('$?', `$${params.length}`));
  };

  if (periodId) add('period_id = $?', periodId);
  if (type === 'savings') {
    params.push('savings_deposit');
    params.push('savings_withdrawal');
    conditions.push(`type IN ($${params.length - 1}, $${params.length})`);
  } else if (type && ['expense', 'income', 'savings_deposit', 'savings_withdrawal'].includes(type)) {
    add('type = $?', type);
  }
  if (category) add('category = $?', category);
  if (dateFrom) add('date >= $?', dateFrom);
  if (dateTo) add('date <= $?', dateTo);
  if (minAmount !== undefined) add('amount >= $?', minAmount);
  if (maxAmount !== undefined) add('amount <= $?', maxAmount);
  if (search) {
    params.push(`%${search}%`);
    conditions.push(`(description ILIKE $${params.length} OR category ILIKE $${params.length})`);
  }

  const where = conditions.join(' AND ');
  const sortColumns = { date: 'date', amount: 'amount', created_at: 'created_at' };
  const sortCol = sortColumns[sortBy] || 'date';
  const dir = sortDir.toLowerCase() === 'asc' ? 'ASC' : 'DESC';

  const offset = (page - 1) * limit;

  const countRes = await query(
    `SELECT COUNT(*) AS total,
            COALESCE(SUM(CASE WHEN type = 'expense' THEN amount END), 0) AS expenses,
            COALESCE(SUM(CASE WHEN type = 'income' THEN amount END), 0) AS incomes
     FROM transactions WHERE ${where}`,
    params
  );
  const meta = countRes.rows[0];

  const { rows } = await query(
    `SELECT * FROM transactions WHERE ${where}
     ORDER BY ${sortCol} ${dir}, created_at ${dir}
     LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
    [...params, limit, offset]
  );

  return {
    transactions: rows.map(toTransaction),
    total: Number(meta.total),
    totalExpenses: Number(meta.expenses),
    totalIncomes: Number(meta.incomes),
    page,
    limit,
    pages: Math.max(1, Math.ceil(Number(meta.total) / limit)),
  };
}

/** Phase 10 — export : toutes les transactions, du plus ancien au plus récent. */
async function exportAll(walletId) {
  const { rows } = await query(
    `SELECT * FROM transactions WHERE wallet_id = $1
     ORDER BY date ASC, created_at ASC`,
    [walletId]
  );
  return rows.map(toTransaction);
}

module.exports = {
  toTransaction,
  createTransaction,
  createSavingsTransaction,
  withdrawAllSavings,
  updateTransaction,
  deleteTransaction,
  getTransactionForWallet,
  recalculateBalance,
  listTransactions,
  exportAll,
};
