const walletService = require('./walletService');
const statsRepository = require('../repositories/statsRepository');
const periodRepository = require('../repositories/periodRepository');
const { localMonthStartIso, localYearStartIso, localDaysAgoIso, todayIso } = require('../utils/dates');

/** Phase 6 — tableau de bord. */
async function dashboard(uid, walletId) {
  const wallet = await walletService.getWallet(uid, walletId);
  const activePeriod = (await periodRepository.getInfo(wallet.id)).period;

  const [totals, series, latest] = await Promise.all([
    statsRepository.totals(wallet.id, activePeriod.id),
    statsRepository.dailyExpensesSeries(wallet.id, 7, activePeriod.id),
    statsRepository.latest(wallet.id, 5, activePeriod.id),
  ]);

  const initialAmount = wallet.initialAmount;
  const budget = initialAmount + totals.incomes;
  const percentUsed = budget > 0 ? Math.round((totals.expenses / budget) * 100) : 0;

  return {
    wallet: {
      id: wallet.id,
      name: wallet.name,
      currency: wallet.currency,
      initialAmount,
      balance: wallet.balance,
    },
    totals: {
      expenses: totals.expenses,
      incomes: totals.incomes,
      transactions: totals.count,
      percentUsed,
    },
    weeklySeries: series,
    latestTransactions: latest,
  };
}

/** Phase 8 — statistiques. */
async function stats(uid, walletId, query = {}) {
  const wallet = await walletService.getWallet(uid, walletId);
  const period = ['day', 'week', 'month', 'year', 'all'].includes(query.period) ? query.period : 'month';

  // Frontières de période à minuit heure locale (Bénin), pas en UTC.
  // Les statistiques lisent TOUTES les périodes, y compris les archivées
  // (les périodes archivées conservent leurs transactions).
  const iso = (d) => d.toISOString().slice(0, 10);
  const dateTo = todayIso();
  let dateFrom;
  if (period === 'day') dateFrom = dateTo;
  else if (period === 'week') dateFrom = localDaysAgoIso(6);
  else if (period === 'month') dateFrom = localMonthStartIso();
  else if (period === 'year') dateFrom = localYearStartIso();
  else dateFrom = '1970-01-01';

  const days = ['day', 'week'].includes(period) ? 7 : period === 'month' ? 30 : 365;

  const [totals, series, categories, periodTotals, prevTotals, monthlySeries] = await Promise.all([
    statsRepository.totals(wallet.id),
    statsRepository.dailyExpensesSeries(wallet.id, days),
    statsRepository.byCategory(wallet.id, { dateFrom, dateTo, type: 'expense' }),
    statsRepository.totalsBetween(wallet.id, dateFrom, dateTo),
    (() => {
      if (period === 'month') {
        // Mois civil précédent complet.
        const [year, month] = dateFrom.split('-').map(Number);
        const prev = new Date(Date.UTC(year, month - 2, 1));
        const prevFrom = iso(prev);
        const prevEnd = new Date(Date.UTC(year, month - 1, 0));
        return statsRepository.totalsBetween(wallet.id, prevFrom, iso(prevEnd));
      }
      if (period === 'year') {
        const year = Number(dateFrom.slice(0, 4));
        return statsRepository.totalsBetween(wallet.id, `${year - 1}-01-01`, `${year - 1}-12-31`);
      }
      const from = new Date(dateFrom);
      const span = Math.max(1, Math.round((new Date(dateTo) - from) / 86400000) + 1);
      const prevFrom = iso(new Date(from.getTime() - span * 86400000));
      const prevTo = iso(new Date(from.getTime() - 86400000));
      return statsRepository.totalsBetween(wallet.id, prevFrom, prevTo);
    })(),
    statsRepository.monthlySeries(wallet.id, 6),
  ]);

  const dayCount = Math.max(1, Math.round((new Date(dateTo) - new Date(dateFrom)) / 86400000) + 1);
  const averageDaily = Math.round(periodTotals.expenses / dayCount);

  const catTotal = categories.reduce((s, c) => s + c.total, 0);
  const byCategory = categories.map((c) => ({
    ...c,
    percent: catTotal > 0 ? Math.round((c.total / catTotal) * 100) : 0,
  }));

  return {
    wallet: { id: wallet.id, name: wallet.name, currency: wallet.currency },
    period,
    dateFrom,
    dateTo,
    totals: {
      allTimeExpenses: totals.expenses,
      allTimeIncomes: totals.incomes,
      periodExpenses: periodTotals.expenses,
      periodIncomes: periodTotals.incomes,
      previousPeriodExpenses: prevTotals.expenses,
      previousPeriodIncomes: prevTotals.incomes,
      averageDaily,
    },
    dailySeries: series,
    byCategory,
    monthlySeries,
  };
}

module.exports = { dashboard, stats };
