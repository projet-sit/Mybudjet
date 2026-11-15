// Tests d'intégration de bout en bout du backend MYBUDGET.
// Base PostgreSQL en mémoire (pg-mem) + vrai serveur Express + vraies migrations,
// une base VIERGE par test (isolation complète).
// Lancement : npm run test:e2e

const { test, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const { startApp } = require('./setup.e2e');

let app = null;

const api = async (path, { method = 'GET', token, body } = {}) => {
  const response = await fetch(`${app.baseUrl}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  let json = null;
  try {
    json = await response.json();
  } catch (_) {
    // Réponses 204 : pas de corps.
  }
  return { status: response.status, json };
};

const setupWallet = async () => {
  const email = `e2e_${Date.now()}_${Math.floor(Math.random() * 1e6)}@mybudget.app`;
  const register = await api('/auth/register', {
    method: 'POST',
    body: { displayName: 'E2E Testeur', email, password: 'secret123' },
  });
  assert.equal(register.status, 201, 'register doit aboutir');
  const token = register.json.data.tokens.accessToken;
  const create = await api('/wallets', {
    method: 'POST',
    token,
    body: { name: 'Budget E2E', initialAmount: 100000, startDate: '2026-11-01' },
  });
  assert.equal(create.status, 201);
  return { token, walletId: create.json.data.wallet.id };
};

afterEach(async () => {
  if (app && app.server) {
    await new Promise((resolve) => app.server.close(resolve));
    if (app.pool && typeof app.pool.end === 'function') {
      await app.pool.end();
    }
  }
  app = null;
});

test('santé publique + healthcheck', async () => {
  app = await startApp();
  const res = await api('/health');
  assert.equal(res.status, 200);
  assert.equal(res.json.data.service, 'MYBUDGET API');
});

test('inscription → portefeuille → dépenses → budget → épargne → reset → annulation', async () => {
  app = await startApp();
  const { token, walletId } = await setupWallet();

  // 1. Dépense classique
  const expense = await api(`/wallets/${walletId}/transactions`, {
    method: 'POST',
    token,
    body: { type: 'expense', amount: 7000, category: 'Alimentation', description: 'Courses', date: '2026-11-15', time: '10:00' },
  });
  assert.equal(expense.status, 201);
  assert.equal(expense.json.data.newBalance, 93000);

  // 2. Budget catégorie : spent reflète la dépense
  const budget = await api(`/wallets/${walletId}/budgets`, {
    method: 'POST',
    token,
    body: { category: 'Alimentation', limitAmount: 30000 },
  });
  assert.equal(budget.status, 201);
  const budgets = await api(`/wallets/${walletId}/budgets?progress=1`, { token });
  const ali = budgets.json.data.budgets.find((b) => b.category === 'Alimentation');
  assert.equal(ali.spent, 7000);

  // 3. Versement à l'épargne : Reste diminue, l'épargne augmente (atomique)
  const deposit = await api(`/wallets/${walletId}/savings/deposit`, {
    method: 'POST',
    token,
    body: { amount: 20000 },
  });
  assert.equal(deposit.status, 200);
  assert.equal(deposit.json.data.wallet.balance, 93000, 'le solde total ne bouge pas');
  assert.equal(deposit.json.data.wallet.savingsAmount, 20000);

  // 4. Reste disponible = balance - savings
  const remain = deposit.json.data.wallet.balance - deposit.json.data.wallet.savingsAmount;
  assert.equal(remain, 73000);

  // 5. Versement > Reste → refus 409 BALANCE_INSUFFICIENT
  const tooMuch = await api(`/wallets/${walletId}/savings/deposit`, {
    method: 'POST',
    token,
    body: { amount: 73001 },
  });
  assert.equal(tooMuch.status, 409);
  assert.equal(tooMuch.json.error.code, 'BALANCE_INSUFFICIENT');

  // 6. L'épargne ne compte PAS comme dépense dans les stats ni le budget
  const stats = await api(`/wallets/${walletId}/stats?period=month`, { token });
  assert.equal(stats.json.data.totals.periodExpenses, 7000);
  const budgetsAfter = await api(`/wallets/${walletId}/budgets?progress=1`, { token });
  const aliAfter = budgetsAfter.json.data.budgets.find((b) => b.category === 'Alimentation');
  assert.equal(aliAfter.spent, 7000, 'une transaction d’épargne ne doit pas alimenter le budget');

  // 7. L'épargne figure dans la liste des opérations (type + catégorie « Épargne »)
  const savingsTxs = await api(`/wallets/${walletId}/transactions?type=savings&all=1`, { token });
  assert.equal(savingsTxs.json.data.total, 1);
  assert.equal(savingsTxs.json.data.transactions[0].type, 'savings_deposit');
  assert.equal(savingsTxs.json.data.transactions[0].category, 'Épargne');

  // 8. Retrait d'épargne : l'argent revient dans le Reste
  const withdraw = await api(`/wallets/${walletId}/savings/withdraw`, {
    method: 'POST',
    token,
    body: { amount: 5000 },
  });
  assert.equal(withdraw.status, 200);
  assert.equal(withdraw.json.data.wallet.savingsAmount, 15000);
  assert.equal(withdraw.json.data.wallet.balance, 93000);

  // 9. Retrait > épargne → refus 409 SAVINGS_INSUFFICIENT
  const tooMuchOut = await api(`/wallets/${walletId}/savings/withdraw`, {
    method: 'POST',
    token,
    body: { amount: 15001 },
  });
  assert.equal(tooMuchOut.status, 409);
  assert.equal(tooMuchOut.json.error.code, 'SAVINGS_INSUFFICIENT');

  // 10. Tout récupérer : toute l'épargne rentre, atomique
  const withdrawAll = await api(`/wallets/${walletId}/savings/withdraw-all`, {
    method: 'POST',
    token,
  });
  assert.equal(withdrawAll.status, 200);
  assert.equal(withdrawAll.json.data.wallet.savingsAmount, 0);
  assert.equal(withdrawAll.json.data.wallet.balance, 93000);

  // 11. Remise à zéro avec épargne conservée (par défaut)
  const depositAgain = await api(`/wallets/${walletId}/savings/deposit`, {
    method: 'POST',
    token,
    body: { amount: 10000 },
  });
  assert.equal(depositAgain.json.data.wallet.savingsAmount, 10000);

  const reset = await api(`/wallets/${walletId}/reset`, {
    method: 'POST',
    token,
    body: { includeSavings: false },
  });
  assert.equal(reset.status, 200);
  assert.equal(reset.json.data.wallet.balance, 10000, 'Reste = 0, épargne conservée');
  assert.equal(reset.json.data.wallet.savingsAmount, 10000);
  assert.equal(reset.json.data.wallet.initialAmount, 10000);

  // 12. L'historique est conservé (périodes visibles) + transactions archivées
  const periods = await api(`/wallets/${walletId}/periods`, { token });
  assert.equal(periods.status, 200);
  const archived = periods.json.data.periods.filter((p) => p.status === 'archived');
  assert.ok(archived.length >= 1, 'au moins une période archivée');
  const archivedTotals = archived[0].totals;
  assert.equal(archivedTotals.saved >= 10000, true);

  // 3 user ops pré-reset (1 dépense + 2 épargne) + retrait + withdraw-all = 5
  const listAll = await api(`/wallets/${walletId}/transactions?all=1&limit=100`, { token });
  assert.equal(listAll.json.data.total, 5, 'les opérations archivées sont conservées');

  // 13. Undo 10 s : retour exact à l'état d'avant remise à zéro
  // (le backend attend l'identifiant de la NOUVELLE période active).
  const undo = await api(`/wallets/${walletId}/period/${reset.json.data.period.id}/undo`, {
    method: 'POST',
    token,
  });
  // Après annulation : l'état complet est restauré — épargne incluse (10000, pas 0).
  assert.equal(undo.status, 200);
  assert.equal(undo.json.data.wallet.balance, 93000);
  assert.equal(undo.json.data.wallet.initialAmount, 100000);
  assert.equal(undo.json.data.wallet.savingsAmount, 10000);

  // 14. Remise à zéro AVEC épargne remise à zéro
  const resetAll = await api(`/wallets/${walletId}/reset`, {
    method: 'POST',
    token,
    body: { includeSavings: true },
  });
  assert.equal(resetAll.status, 200);
  assert.equal(resetAll.json.data.wallet.balance, 0);
  assert.equal(resetAll.json.data.wallet.savingsAmount, 0);
  assert.equal(resetAll.json.data.wallet.initialAmount, 0);

  // 15. Les périodes restent accessibles après reset
  const periodsAfter = await api(`/wallets/${walletId}/periods`, { token });
  assert.equal(periodsAfter.status, 200);
  assert.ok(periodsAfter.json.data.periods.length >= 2);
});

test('validation des entrées : montants, types, catégories', async () => {
  app = await startApp();
  const { token, walletId } = await setupWallet();

  const negative = await api(`/wallets/${walletId}/transactions`, {
    method: 'POST',
    token,
    body: { type: 'expense', amount: -100, category: 'Alimentation', date: '2026-11-15', time: '10:00' },
  });
  assert.equal(negative.status, 400);

  const badType = await api(`/wallets/${walletId}/transactions`, {
    method: 'POST',
    token,
    body: { type: 'savings_deposit', amount: 100, category: 'Épargne', date: '2026-11-15', time: '10:00' },
  });
  assert.equal(badType.status, 400, 'les opérations d’épargne passent par /savings/*');

  const badCategory = await api(`/wallets/${walletId}/transactions`, {
    method: 'POST',
    token,
    body: { type: 'expense', amount: 100, category: 'Niche_invalide', date: '2026-11-15', time: '10:00' },
  });
  assert.equal(badCategory.status, 400);
});

test('rapport de plantage client (crash report) est accepté', async () => {
  app = await startApp();
  const res = await fetch(`${app.baseUrl}/client-errors`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ message: 'setState() called after dispose', stack: 'stack', screen: 'HomeScreen', platform: 'android', appVersion: '1.0.0' }),
  });
  assert.equal(res.status, 204);
});

test('restauration d’une période archivée avec des opérations en cours → refus 409', async () => {
  app = await startApp();
  const { token, walletId } = await setupWallet();

  await api(`/wallets/${walletId}/transactions`, {
    method: 'POST',
    token,
    body: { type: 'expense', amount: 500, category: 'Alimentation', date: '2026-11-15', time: '10:00' },
  });

  const reset = await api(`/wallets/${walletId}/reset`, {
    method: 'POST',
    token,
    body: { includeSavings: false },
  });
  assert.equal(reset.status, 200);

  // On crée un revenu sur la NOUVELLE période (solde = 0 après reset, revenu possible) :
  // la restauration doit être refusée car des opérations existent sur la période courante.
  await api(`/wallets/${walletId}/transactions`, {
    method: 'POST',
    token,
    body: { type: 'income', amount: 200, category: 'Salaire', date: '2026-11-15', time: '11:00' },
  });

  const periods = await api(`/wallets/${walletId}/periods`, { token });
  const archived = periods.json.data.periods.find((p) => p.status === 'archived');
  const restore = await api(`/wallets/${walletId}/periods/${archived.id}/restore`, {
    method: 'POST',
    token,
  });
  assert.equal(restore.status, 409);
  assert.equal(restore.json.error.code, 'RESTORE_BLOCKED');
});

test('restauration d’une période archivée sur période courante vide → succès', async () => {
  app = await startApp();
  const { token, walletId } = await setupWallet();

  await api(`/wallets/${walletId}/transactions`, {
    method: 'POST',
    token,
    body: { type: 'expense', amount: 1500, category: 'Logement', date: '2026-11-15', time: '10:00' },
  });

  const reset = await api(`/wallets/${walletId}/reset`, {
    method: 'POST',
    token,
    body: { includeSavings: false },
  });
  assert.equal(reset.status, 200);

  const periods = await api(`/wallets/${walletId}/periods`, { token });
  const archived = periods.json.data.periods.find((p) => p.status === 'archived');
  const restore = await api(`/wallets/${walletId}/periods/${archived.id}/restore`, {
    method: 'POST',
    token,
  });
  assert.equal(restore.status, 200, JSON.stringify(restore.json));
  assert.equal(restore.json.data.wallet.balance, 98500);
  assert.equal(restore.json.data.wallet.initialAmount, 100000);

  // Les opérations de l'archive redeviennent visibles dans la liste active.
  const list = await api(`/wallets/${walletId}/transactions`, { token });
  assert.equal(list.json.data.total, 1);
  assert.equal(list.json.data.transactions[0].amount, 1500);
});
