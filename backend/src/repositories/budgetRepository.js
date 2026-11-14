const { query, withTransaction } = require('../config/db');
const ApiError = require('../utils/ApiError');
const walletService = require('../services/walletService');
const periodRepository = require('./periodRepository');

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function toBudget(row) {
  return {
    id: row.id,
    userId: row.user_id,
    walletId: row.wallet_id,
    category: row.category,
    limitAmount: Number(row.limit_amount),
    period: row.period,
    createdAt: row.created_at,
  };
}

async function create(uid, walletId, body) {
  await walletService.getWallet(uid, walletId); // isolation
  const category = String(body.category || '').trim();
  const limit = Number(body.limitAmount);
  if (!category) throw ApiError.validation('Catégorie requise', { field: 'category' });
  if (!Number.isInteger(limit) || limit <= 0) {
    throw ApiError.validation('La limite doit être un entier positif', { field: 'limitAmount' });
  }

  const existing = await query(
    'SELECT id FROM budgets WHERE wallet_id = $1 AND category = $2',
    [walletId, category]
  );
  if (existing.rows.length > 0) {
    throw ApiError.conflict('BUDGET_EXISTS', `Un budget existe déjà pour ${category}`);
  }

  const { rows } = await query(
    `INSERT INTO budgets (user_id, wallet_id, category, limit_amount, period)
     VALUES ($1, $2, $3, $4, $5) RETURNING *`,
    [uid, walletId, category, limit, body.period || 'monthly']
  );
  return toBudget(rows[0]);
}

async function list(uid, walletId, { withProgress = false, dateFrom, dateTo } = {}) {
  await walletService.getWallet(uid, walletId);
  const { rows } = await query(
    'SELECT * FROM budgets WHERE wallet_id = $1 ORDER BY created_at ASC',
    [walletId]
  );
  const budgets = rows.map(toBudget);

  if (!withProgress) return { budgets };

  const active = await periodRepository.getInfo(walletId);
  const periodId = active.period.id;
  if (!dateFrom || !DATE_RE.test(dateFrom)) dateFrom = active.period.startDate;
  if (!dateTo || !DATE_RE.test(dateTo)) dateTo = active.period.endDate;

  const spentRows = await query(
    `SELECT category, SUM(amount) AS spent
     FROM transactions
     WHERE wallet_id = $1 AND type = 'expense' AND period_id = $2
     GROUP BY category`,
    [walletId, periodId]
  );
  const spentMap = new Map(spentRows.rows.map((r) => [r.category, Number(r.spent)]));

  return {
    budgets: budgets.map((b) => {
      const spent = spentMap.get(b.category) || 0;
      return {
        ...b,
        spent,
        remaining: Math.max(0, b.limitAmount - spent),
        percent: Math.round((spent / b.limitAmount) * 100),
        alertLevel: spent / b.limitAmount >= 1 ? 100 : spent / b.limitAmount >= 0.8 ? 80 : spent / b.limitAmount >= 0.5 ? 50 : 0,
      };
    }),
    dateFrom,
    dateTo,
  };
}

async function update(uid, walletId, budgetId, body) {
  await walletService.getWallet(uid, walletId);
  const limit = Number(body.limitAmount);
  if (!Number.isInteger(limit) || limit <= 0) {
    throw ApiError.validation('La limite doit être un entier positif', { field: 'limitAmount' });
  }
  const { rows } = await query(
    `UPDATE budgets SET limit_amount = $3, updated_at = now()
     WHERE id = $1 AND wallet_id = $2 RETURNING *`,
    [budgetId, walletId, limit]
  );
  if (rows.length === 0) throw ApiError.notFound('Budget introuvable');
  return toBudget(rows[0]);
}

async function remove(uid, walletId, budgetId) {
  await walletService.getWallet(uid, walletId);
  const { rowCount } = await query(
    'DELETE FROM budgets WHERE id = $1 AND wallet_id = $2',
    [budgetId, walletId]
  );
  if (rowCount === 0) throw ApiError.notFound('Budget introuvable');
  return { deleted: true };
}

module.exports = { create, list, update, remove };
