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

/** Série journalière (dépenses) sur N derniers jours (heure locale du Bénin), jours vides inclus. */
async function dailyExpensesSeries(walletId, days = 7, periodId) {
  const { localDaysAgoIso, todayIso } = require('../utils/dates');
  const startIso = localDaysAgoIso(days - 1);
  const params = [walletId, startIso];
  let periodClause = '';
  if (periodId) {
    params.push(periodId);
    periodClause = `AND period_id = $${params.length}`;
  }
  const { rows } = await query(
    `SELECT date AS day, amount
     FROM transactions
     WHERE wallet_id = $1 AND type = 'expense' AND date >= $2::date ${periodClause}`,
    params
  );
  const byDay = new Map();
  for (const r of rows) {
    const key = new Date(r.day).toISOString().slice(0, 10);
    byDay.set(key, (byDay.get(key) || 0) + Number(r.amount));
  }
  const result = [];
  const today = new Date(`${todayIso()}T00:00:00Z`);
  for (let i = days - 1; i >= 0; i--) {
    const d = new Date(today.getTime() - i * 86400000);
    const key = d.toISOString().slice(0, 10);
    result.push({ date: key, expenses: byDay.get(key) || 0 });
  }
  return result;
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

/** Série mensuelle (dépenses et revenus) sur les N derniers mois (heure locale du Bénin). */
async function monthlySeries(walletId, months = 6) {
  const { localIsoParts } = require('../utils/dates');
  const now = localIsoParts();
  // Premier jour du mois il y a (months-1) mois, heure locale.
  let y = now.year;
  let m = now.month - (months - 1);
  while (m <= 0) {
    m += 12;
    y -= 1;
  }
  const startIso = `${y}-${String(m).padStart(2, '0')}-01`;
  const { rows } = await query(
    `SELECT date AS day, type, amount
     FROM transactions
     WHERE wallet_id = $1 AND date >= $2::date`,
    [walletId, startIso]
  );
  const byMonth = new Map();
  for (const r of rows) {
    const key = new Date(r.day).toISOString().slice(0, 7);
    const bucket = byMonth.get(key) || { expenses: 0, incomes: 0 };
    if (r.type === 'expense') bucket.expenses += Number(r.amount);
    else if (r.type === 'income') bucket.incomes += Number(r.amount);
    byMonth.set(key, bucket);
  }
  const result = [];
  for (let i = months - 1; i >= 0; i--) {
    let yy = y;
    let mm = m + i;
    while (mm > 12) {
      mm -= 12;
      yy += 1;
    }
    const key = `${yy}-${String(mm).padStart(2, '0')}`;
    const value = byMonth.get(key) || { expenses: 0, incomes: 0 };
    result.push({ month: key, expenses: value.expenses, incomes: value.incomes });
  }
  return result;
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
