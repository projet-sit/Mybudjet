const { query, withTransaction } = require('../config/db');
const ApiError = require('../utils/ApiError');
const periodRepository = require('./periodRepository');

function toTransaction(row) {
  return {
    id: row.id,
    walletId: row.wallet_id,
    periodId: row.period_id,
    type: row.type,
    amount: Number(row.amount),
    category: row.category,
    description: row.description,
    date: row.date,
    time: row.time,
    paymentMethod: row.payment_method,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

/**
 * Crée une transaction de façon ATOMIQUE :
 * 1. verrouille la ligne du portefeuille (FOR UPDATE → sérialise les écritures concurrentes),
 * 2. vérifie le solde disponible pour une dépense,
 * 3. insère la transaction,
 * 4. met à jour le solde,
 * le tout dans une seule transaction SQL (commit/rollback ensemble).
 */
async function createTransaction({ walletId, type, amount, category, description, date, time, paymentMethod }) {
  return withTransaction(async (client) => {
    const locked = await client.query(
      'SELECT id, user_id, balance, savings_amount, start_date FROM wallets WHERE id = $1 FOR UPDATE',
      [walletId]
    );
    if (locked.rows.length === 0) {
      throw ApiError.notFound('Portefeuille introuvable');
    }
    const currentBalance = Number(locked.rows[0].balance);
    const available = currentBalance - Number(locked.rows[0].savings_amount || 0);
    const period = await periodRepository.ensureActiveWithClient(client, locked.rows[0]);

    if (type === 'expense' && amount > available) {
      throw ApiError.conflict(
        'BALANCE_INSUFFICIENT',
        'Solde disponible insuffisant pour cette dépense',
        { balance: currentBalance, available, requested: amount }
      );
    }

    const { rows } = await client.query(
      `INSERT INTO transactions (wallet_id, period_id, type, amount, category, description, date, time, payment_method)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
       RETURNING *`,
      [walletId, period.id, type, amount, category, description, date, time, paymentMethod]
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
async function updateTransaction({ walletId, txId, type, amount, category, description, date, time, paymentMethod }) {
  return withTransaction(async (client) => {
    const locked = await client.query(
      'SELECT balance, savings_amount FROM wallets WHERE id = $1 FOR UPDATE',
      [walletId]
    );
    if (locked.rows.length === 0) throw ApiError.notFound('Portefeuille introuvable');
    const currentBalance = Number(locked.rows[0].balance);
    const currentAvailable =
      currentBalance - Number(locked.rows[0].savings_amount || 0);

    const existing = await client.query(
      'SELECT * FROM transactions WHERE id = $1 AND wallet_id = $2 FOR UPDATE',
      [txId, walletId]
    );
    if (existing.rows.length === 0) throw ApiError.notFound('Transaction introuvable');
    const old = toTransaction(existing.rows[0]);

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
       SET type = $2, amount = $3, category = $4, description = $5,
           date = $6, time = $7, payment_method = $8, updated_at = now()
       WHERE id = $1
       RETURNING *`,
      [txId, type, amount, category, description, date, time, paymentMethod]
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

    const delta = old.type === 'expense' ? old.amount : -old.amount;
    const updated = await client.query(
      'UPDATE wallets SET balance = balance + $2::bigint, updated_at = now() WHERE id = $1 RETURNING balance',
      [walletId, delta]
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
  if (type && ['expense', 'income'].includes(type)) add('type = $?', type);
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
  updateTransaction,
  deleteTransaction,
  getTransactionForWallet,
  recalculateBalance,
  listTransactions,
  exportAll,
};
