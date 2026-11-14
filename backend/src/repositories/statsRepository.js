const { query } = require('../config/db');
const { toTransaction } = require('./transactionRepository');

/** Totaux + séries pour le tableau de bord (Phase 6) et les statistiques (Phase 8). */

async function totals(walletId, periodId) {
  const { rows } = await query(
    `SELECT
       COALESCE(SUM(CASE WHEN type = 'expense' THEN amount END), 0) AS expenses,
       COALESCE(SUM(CASE WHEN type = 'income' THEN amount END), 0) AS incomes,
       COUNT(*) AS count
     FROM transactions
     WHERE wallet_id = $1 ${periodId ? 'AND period_id = $2' : ''}`,
    periodId ? [walletId, periodId] : [walletId]
  );
  const r = rows[0];
  return {
    expenses: Number(r.expenses),
    incomes: Number(r.incomes),
    count: Number(r.count),
  };
}

/** Série journalière (dépenses) sur N derniers jours, incluant les jours vides. */
async function dailyExpensesSeries(walletId, days = 7, periodId) {
  const params = [walletId, days];
  let periodClause = '';
  if (periodId) {
    params.push(periodId);
    periodClause = `AND t.period_id = $${params.length}`;
  }
  const { rows } = await query(
    `SELECT d::date AS day,
            COALESCE(SUM(t.amount), 0) AS total
     FROM generate_series(CURRENT_DATE - ($2::int - 1), CURRENT_DATE, '1 day') AS d
     LEFT JOIN transactions t
       ON t.wallet_id = $1 AND t.type = 'expense' AND t.date = d::date ${periodClause}
     GROUP BY d::date ORDER BY d::date ASC`,
    params
  );
  return rows.map((r) => ({ date: r.day, expenses: Number(r.total) }));
}

/** Répartition par catégorie (dépenses) sur une période. */
async function byCategory(walletId, { dateFrom, dateTo, type = 'expense' } = {}) {
  const conditions = ['wallet_id = $1', 'type = $2'];
  const params = [walletId, type];
  if (dateFrom) {
    params.push(dateFrom);
    conditions.push(`date >= $${params.length}`);
  }
  if (dateTo) {
    params.push(dateTo);
    conditions.push(`date <= $${params.length}`);
  }
  const { rows } = await query(
    `SELECT category, SUM(amount) AS total, COUNT(*) AS count
     FROM transactions WHERE ${conditions.join(' AND ')}
     GROUP BY category ORDER BY total DESC`,
    params
  );
  return rows.map((r) => ({ category: r.category, total: Number(r.total), count: Number(r.count) }));
}

/** Dernières transactions (tableau de bord). */
async function latest(walletId, limit = 5, periodId) {
  const params = [walletId, limit];
  let periodClause = '';
  if (periodId) {
    params.push(periodId);
    periodClause = `AND period_id = $${params.length}`;
  }
  const { rows } = await query(
    `SELECT * FROM transactions WHERE wallet_id = $1 ${periodClause}
     ORDER BY date DESC, created_at DESC LIMIT $2`,
    params
  );
  return rows.map(toTransaction);
}

/** Série mensuelle (dépenses et revenus) sur les N derniers mois. */
async function monthlySeries(walletId, months = 6) {
  const { rows } = await query(
    `SELECT to_char(m.month_start, 'YYYY-MM') AS month,
            COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount END), 0) AS expenses,
            COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount END), 0) AS incomes
     FROM (
       SELECT generate_series(
         date_trunc('month', CURRENT_DATE) - (($2::int - 1) * interval '1 month'),
         date_trunc('month', CURRENT_DATE),
         '1 month'
       ) AS month_start
     ) m
     LEFT JOIN transactions t
       ON t.wallet_id = $1
      AND date_trunc('month', t.date) = m.month_start
     GROUP BY m.month_start
     ORDER BY m.month_start ASC`,
    [walletId, months]
  );
  return rows.map((r) => ({
    month: r.month,
    expenses: Number(r.expenses),
    incomes: Number(r.incomes),
  }));
}

/** Période : totaux entre deux dates. */
async function totalsBetween(walletId, dateFrom, dateTo) {
  const { rows } = await query(
    `SELECT
       COALESCE(SUM(CASE WHEN type = 'expense' THEN amount END), 0) AS expenses,
       COALESCE(SUM(CASE WHEN type = 'income' THEN amount END), 0) AS incomes
     FROM transactions
     WHERE wallet_id = $1 AND date >= $2 AND date <= $3`,
    [walletId, dateFrom, dateTo]
  );
  return {
    expenses: Number(rows[0].expenses),
    incomes: Number(rows[0].incomes),
  };
}

module.exports = {
  totals,
  dailyExpensesSeries,
  byCategory,
  latest,
  totalsBetween,
  monthlySeries,
};
