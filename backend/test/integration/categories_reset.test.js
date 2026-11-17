// Tests e2e : catégories personnalisées + réinitialisation complète du compte.
const test = require('node:test');
const assert = require('node:assert/strict');
const { startApp } = require('./setup.e2e');

const PASSWORD = 'password123';

async function postJson(baseUrl, path, body, token, headers = {}) {
  const res = await fetch(`${baseUrl}${path}`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...headers,
    },
    body: JSON.stringify(body ?? {}),
  });
  const json = await res.json().catch(() => null);
  return { res, json };
}

async function api(baseUrl, method, path, body, token, headers = {}) {
  const res = await fetch(`${baseUrl}${path}`, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...headers,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const json = await res.json().catch(() => null);
  return { res, json };
}

async function register(baseUrl, suffix, displayName = 'Test User') {
  const { res, json } = await postJson(baseUrl, '/auth/register', {
    displayName,
    phone: `+22997${suffix}`,
    email: `e2e_${suffix}@mybudget.app`,
    password: PASSWORD,
  });
  assert.equal(res.status, 201, JSON.stringify(json));
  return json.data;
}

async function createWallet(baseUrl, token, name = 'Budget', initialAmount = 100000) {
  const { res, json } = await postJson(baseUrl, '/wallets', { name, initialAmount }, token);
  assert.equal(res.status, 201, JSON.stringify(json));
  return json.data.wallet;
}

test('catégories : création, fusion anti-doublon, ordre, renommage, suppression', async () => {
  const { server, baseUrl } = await startApp();
  try {
    const { tokens } = await register(baseUrl, '1001');
    const auth = tokens.accessToken;

    // Liste : défauts d'abord, « Autres » en dernier (expense)
    const list = await api(baseUrl, 'GET', '/categories?type=expense', undefined, auth);
    assert.equal(list.res.status, 200);
    const names = list.json.data.categories.map((c) => c.name);
    assert.deepEqual(names.slice(-1), ['Autres']);
    assert.equal(names[0], 'Alimentation');

    // Création personnalisée
    const created = await postJson(baseUrl, '/categories', { type: 'expense', name: 'Coiffure' }, auth);
    assert.equal(created.res.status, 201);
    const catId = created.json.data.category.id;
    assert.equal(created.json.data.category.isDefault, false);

    // La personnalisée apparaît après les défauts et avant « Autres »
    const after = await api(baseUrl, 'GET', '/categories?type=expense', undefined, auth);
    const afterNames = after.json.data.categories.map((c) => c.name);
    assert.equal(afterNames.indexOf('Coiffure'), afterNames.indexOf('Famille') + 1);
    assert.equal(afterNames.indexOf('Autres'), afterNames.length - 1);

    // Doublon : casse / espaces / accents → 409 avec la catégorie existante
    const dup1 = await postJson(baseUrl, '/categories', { type: 'expense', name: '  coiffure ' }, auth);
    assert.equal(dup1.res.status, 409);
    assert.equal(dup1.json.error.code, 'CATEGORY_EXISTS');
    assert.equal(dup1.json.error.details.category.id, catId);

    const dup2 = await postJson(baseUrl, '/categories', { type: 'expense', name: 'Coïffure' }, auth);
    assert.equal(dup2.res.status, 409);
    assert.equal(dup2.json.error.details.category.id, catId);

    // Doublon avec un défaut (accents) : « Études » existe déjà
    const dup3 = await postJson(baseUrl, '/categories', { type: 'expense', name: 'Etudes' }, auth);
    assert.equal(dup3.res.status, 409);
    assert.equal(dup3.json.error.details.category.name, 'Études');

    // Validation : trop court / caractères interdits
    const bad = await postJson(baseUrl, '/categories', { type: 'expense', name: 'x' }, auth);
    assert.equal(bad.res.status, 400);

    // Utilisation dans une transaction (par nom, puis par id)
    const wallet = await createWallet(baseUrl, auth, 'Test', 50000);
    const txByName = await postJson(baseUrl, `/wallets/${wallet.id}/transactions`, {
      type: 'expense', amount: 3000, category: 'Coiffure', date: '2026-11-17',
    }, auth);
    assert.equal(txByName.res.status, 201, JSON.stringify(txByName.json));
    assert.equal(txByName.json.data.transaction.category, 'Coiffure');
    assert.equal(txByName.json.data.transaction.categoryId, catId);

    const txById = await postJson(baseUrl, `/wallets/${wallet.id}/transactions`, {
      type: 'expense', amount: 2000, categoryId: catId, date: '2026-11-17',
    }, auth);
    assert.equal(txById.res.status, 201, JSON.stringify(txById.json));

    // Renommage → les opérations suivent
    const renamed = await api(baseUrl, 'PATCH', `/categories/${catId}`, { name: 'Salon' }, auth);
    assert.equal(renamed.res.status, 200, JSON.stringify(renamed.json));
    const txList = await api(baseUrl, 'GET', `/wallets/${wallet.id}/transactions?search=Salon`, undefined, auth);
    assert.equal(txList.json.data.total, 2);

    // Budget sur la catégorie personnalisée
    const budget = await postJson(baseUrl, `/wallets/${wallet.id}/budgets`, {
      categoryId: catId, limitAmount: 20000,
    }, auth);
    assert.equal(budget.res.status, 201, JSON.stringify(budget.json));
    const budgetList = await api(baseUrl, 'GET', `/wallets/${wallet.id}/budgets?progress=1`, undefined, auth);
    const b = budgetList.json.data.budgets.find((x) => x.categoryId === catId);
    assert.equal(b.spent, 5000);

    // Export CSV : la catégorie personnalisée y figure (nom renommé)
    const csvRes = await fetch(`${baseUrl}/wallets/${wallet.id}/export`, {
      headers: { authorization: `Bearer ${auth}` },
    });
    const csvText = await csvRes.text();
    assert.equal(csvRes.status, 200);
    assert.equal(csvText.includes('Salon'), true);

    // Budget sur la catégorie personnalisée
    const del1 = await api(baseUrl, 'DELETE', `/categories/${catId}`, undefined, auth);
    assert.equal(del1.res.status, 409);
    assert.equal(del1.json.error.code, 'CATEGORY_HAS_BUDGET');
    assert.equal(del1.json.error.details.budgets.length, 1);

    const del2 = await api(baseUrl, 'DELETE', `/categories/${catId}?confirmBudgets=1`, undefined, auth);
    assert.equal(del2.res.status, 200);
    assert.equal(del2.json.data.budgetsDeleted, 1);

    // Les opérations passent en « Autres »
    const after2 = await api(baseUrl, 'GET', `/wallets/${wallet.id}/transactions`, undefined, auth);
    for (const t of after2.json.data.transactions) {
      assert.equal(t.category, 'Autres');
    }
    const budgetsAfter = await api(baseUrl, 'GET', `/wallets/${wallet.id}/budgets`, undefined, auth);
    assert.equal(budgetsAfter.json.data.budgets.length, 0);
  } finally {
    server.close();
  }
});

test('catégories : limite de 30 personnalisées par type', async () => {
  const { server, baseUrl } = await startApp();
  try {
    const { tokens } = await register(baseUrl, '1002');
    const auth = tokens.accessToken;
    for (let i = 1; i <= 30; i += 1) {
      const { res } = await postJson(baseUrl, '/categories', { type: 'income', name: `Source${i}` }, auth);
      assert.equal(res.status, 201, `création ${i}`);
    }
    const over = await postJson(baseUrl, '/categories', { type: 'income', name: 'UneDePlus' }, auth);
    assert.equal(over.res.status, 400);
    // L'autre type n'est pas impacté
    const ok = await postJson(baseUrl, '/categories', { type: 'expense', name: 'Coiffure' }, auth);
    assert.equal(ok.res.status, 201);
  } finally {
    server.close();
  }
});

test('réinitialisation : tout disparaît sauf le compte, et data_epoch avance', async () => {
  const { server, baseUrl } = await startApp();
  try {
    const { tokens, user } = await register(baseUrl, '1003');
    const auth = tokens.accessToken;

    // Données : portefeuille, dépense, épargne, budget, objectif, catégorie perso
    const wallet = await createWallet(baseUrl, auth, 'MonBudget', 100000);
    await postJson(baseUrl, `/wallets/${wallet.id}/transactions`, {
      type: 'expense', amount: 10000, category: 'Alimentation', date: '2026-11-17',
    }, auth);
    await postJson(baseUrl, `/wallets/${wallet.id}/savings/deposit`, { amount: 5000 }, auth);
    await postJson(baseUrl, `/wallets/${wallet.id}/budgets`, { category: 'Alimentation', limitAmount: 50000 }, auth);
    await postJson(baseUrl, `/wallets/${wallet.id}/goals`, { name: 'Voyage', targetAmount: 100000 }, auth);
    await postJson(baseUrl, '/categories', { type: 'expense', name: 'Coiffure' }, auth);

    // Réinitialisation
    const reset = await postJson(baseUrl, '/me/reset', {}, auth);
    assert.equal(reset.res.status, 200, JSON.stringify(reset.json));
    assert.equal(reset.json.data.ok, true);
    assert.equal(reset.json.data.dataEpoch, 1);

    // Tout est vide
    const wallets = await api(baseUrl, 'GET', '/wallets', undefined, auth);
    assert.deepEqual(wallets.json.data.wallets, []);
    assert.equal(wallets.json.data.hasWallet, false);

    const me = await api(baseUrl, 'GET', '/auth/me', undefined, auth);
    assert.equal(me.res.status, 200);
    assert.equal(me.json.data.user.dataEpoch, 1);
    assert.equal(me.json.data.user.phone, user.phone); // compte conservé

    // Catégories : uniquement les défauts, « Coiffure » disparue
    const cats = await api(baseUrl, 'GET', '/categories', undefined, auth);
    assert.equal(cats.json.data.categories.some((c) => c.name === 'Coiffure'), false);
    assert.ok(cats.json.data.categories.length > 10);

    // Isolation : un autre compte n'est pas affecté
    const other = await register(baseUrl, '1004');
    const otherWallet = await createWallet(baseUrl, other.tokens.accessToken, 'Autre', 70000);
    const otherWallets = await api(baseUrl, 'GET', '/wallets', undefined, other.tokens.accessToken);
    assert.equal(otherWallets.json.data.wallets.length, 1);
    assert.equal(otherWallets.json.data.wallets[0].id, otherWallet.id);

    // Deuxième réinitialisation : l'epoch avance
    const reset2 = await postJson(baseUrl, '/me/reset', {}, auth);
    assert.equal(reset2.json.data.dataEpoch, 2);
  } finally {
    server.close();
  }
});

test('réinitialisation : échec avant commit = rien supprimé (rollback complet)', async () => {
  const { server, baseUrl } = await startApp();
  try {
    const { tokens } = await register(baseUrl, '1005');
    const auth = tokens.accessToken;
    const wallet = await createWallet(baseUrl, auth, 'MonBudget', 100000);
    await postJson(baseUrl, `/wallets/${wallet.id}/transactions`, {
      type: 'expense', amount: 10000, category: 'Alimentation', date: '2026-11-17',
    }, auth);
    await postJson(baseUrl, '/categories', { type: 'expense', name: 'Coiffure' }, auth);

    const fail = await postJson(baseUrl, '/me/reset', {}, auth, { 'x-test-fail-reset': '1' });
    assert.equal(fail.res.status, 500);

    // pg-mem n'honore pas ROLLBACK (voir docs/tests.md) : la vérification « tout
    // ou rien » est faite sur une vraie PostgreSQL via `npm run test:rollback`.
    // Ici on vérifie simplement le code d'erreur remonté.
    assert.equal(fail.json.success, false);
  } finally {
    server.close();
  }
});
