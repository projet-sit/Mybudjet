/**
 * Tests financiers MYBUDGET (Phase 12) — Node pur, sans dépendance.
 * Usage : démarrer le backend puis `node test/finance.test.js`
 */
const BASE = process.env.BASE_URL || 'http://localhost:3000/api/v1';

const stamp = Date.now();
const email = `test-finance-${stamp}@mybudget.test`;
const password = 'MotDePasse123';

let token = null;
let walletId = null;
const txIds = [];
let failures = 0;

function check(name, ok, extra = '') {
  const tag = ok ? 'PASS' : 'FAIL';
  console.log(`${tag} - ${name}${extra ? ` (${extra})` : ''}`);
  if (!ok) failures += 1;
}

async function api(method, path, { body, auth = true, raw = false } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (auth && token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    data = text;
  }
  return { status: res.status, data, text };
}

async function main() {
  // 1. Santé
  const health = await api('GET', '/health', { auth: false });
  check('01 health 200', health.status === 200 && health.data.success === true);

  // 2. Inscription
  const reg = await api('POST', '/auth/register', {
    auth: false,
    body: { displayName: 'Test Finance', email, password },
  });
  check('02 register 201', reg.status === 201, `status=${reg.status}`);
  token = reg.data?.data?.tokens?.accessToken;

  // 3. Login
  const login = await api('POST', '/auth/login', {
    auth: false,
    body: { email, password },
  });
  check('03 login 200 + token', login.status === 200 && !!login.data?.data?.tokens?.accessToken);
  token = login.data?.data?.tokens?.accessToken;

  // 4. /auth/me
  const me = await api('GET', '/auth/me');
  check('04 me 200', me.status === 200 && me.data?.data?.user?.email === email);

  // 5. Sans token → 401
  const noAuth = await api('GET', '/auth/me', { auth: false });
  check('05 me sans token 401', noAuth.status === 401);

  // 6. Email dupliqué → 409
  const dup = await api('POST', '/auth/register', {
    auth: false,
    body: { displayName: 'Dup', email, password },
  });
  check('06 email duplique 409', dup.status === 409, `status=${dup.status}`);

  // 7. Mot de passe court → 400
  const short = await api('POST', '/auth/register', {
    auth: false,
    body: { displayName: 'Court', email: `short-${stamp}@mybudget.test`, password: 'abc' },
  });
  check('07 mot de passe court 400', short.status === 400);

  // 8. Création portefeuille : solde = montant initial (150 000)
  const wallet = await api('POST', '/wallets', {
    body: { name: 'Portefeuille test', initialAmount: 150000 },
  });
  walletId = wallet.data?.data?.wallet?.id;
  const balance0 = wallet.data?.data?.wallet?.balance;
  check(
    '08 wallet: solde = montant initial',
    wallet.status === 201 && Number(balance0) === 150000,
    `balance=${balance0}`
  );

  // 9. Dépense trop grande → 409 BALANCE_INSUFFICIENT
  const over = await api('POST', `/wallets/${walletId}/transactions`, {
    body: { type: 'expense', amount: 99999999, category: 'Autres', date: '2026-01-01' },
  });
  check('09 solde insuffisant 409', over.status === 409, `status=${over.status}`);

  // 10-12. Scénario canonique : +20 000, -5 000, -10 000 → 155 000
  const inc = await api('POST', `/wallets/${walletId}/transactions`, {
    body: { type: 'income', amount: 20000, category: 'Salaire', date: '2026-01-02' },
  });
  txIds.push(inc.data?.data?.transaction?.id);
  check('10 revenu +20000', inc.status === 201 && Number(inc.data?.data?.newBalance) === 170000);

  const ex1 = await api('POST', `/wallets/${walletId}/transactions`, {
    body: {
      type: 'expense',
      amount: 5000,
      category: 'Alimentation',
      paymentMethod: 'Espèces',
      date: '2026-01-03',
    },
  });
  txIds.push(ex1.data?.data?.transaction?.id);
  check('11 depense -5000', ex1.status === 201 && Number(ex1.data?.data?.newBalance) === 165000);

  const ex2 = await api('POST', `/wallets/${walletId}/transactions`, {
    body: { type: 'expense', amount: 10000, category: 'Transport', date: '2026-01-04' },
  });
  txIds.push(ex2.data?.data?.transaction?.id);
  const finalBalance = 150000 + 20000 - 5000 - 10000;
  check(
    '12 depense -10000 → solde 155000',
    ex2.status === 201 && Number(ex2.data?.data?.newBalance) === finalBalance,
    `newBalance=${ex2.data?.data?.newBalance}`
  );

  // 13. Modification → recalcul exact (changer 10 000 → 3 000 → 162 000)
  const upd = await api('PATCH', `/wallets/${walletId}/transactions/${txIds[2]}`, {
    body: { amount: 3000 },
  });
  check(
    '13 modification → recalcul exact',
    upd.status === 200 && Number(upd.data?.data?.newBalance) === finalBalance + 7000,
    `newBalance=${upd.data?.data?.newBalance}`
  );

  // 14. Suppression → recalcul exact (retire 3 000 → 165 000)
  const del = await api('DELETE', `/wallets/${walletId}/transactions/${txIds[2]}`);
  check(
    '14 suppression → recalcul exact',
    del.status === 200 && Number(del.data?.data?.newBalance) === finalBalance + 10000,
    `newBalance=${del.data?.data?.newBalance}`
  );

  // 15. Concurrence : 2 dépenses de 100 000 en parallèle → exactement 1 OK, 1 conflit
  const [a, b] = await Promise.all([
    api('POST', `/wallets/${walletId}/transactions`, {
      body: { type: 'expense', amount: 100000, category: 'Logement', date: '2026-01-05' },
    }),
    api('POST', `/wallets/${walletId}/transactions`, {
      body: { type: 'expense', amount: 100000, category: 'Shopping', date: '2026-01-05' },
    }),
  ]);
  const statuses = [a.status, b.status].sort();
  check(
    '15 concurrence: 1 OK / 1 conflit',
    statuses[0] === 201 && statuses[1] === 409,
    `statuses=${a.status},${b.status}`
  );

  // Bonus — dashboard, stats, budgets, export, isolation
  const dash = await api('GET', `/wallets/${walletId}/dashboard`);
  check('B1 dashboard 200', dash.status === 200);

  const stats = await api('GET', `/wallets/${walletId}/stats?period=month`);
  check('B2 stats 200', stats.status === 200);

  const budget = await api('POST', `/wallets/${walletId}/budgets`, {
    body: { category: 'Alimentation', limitAmount: 50000 },
  });
  const budgetId = budget.data?.data?.budget?.id;
  const progress = await api('GET', `/wallets/${walletId}/budgets?progress=1`);
  const entry = (progress.data?.data?.budgets || []).find((x) => x.id === budgetId);
  check(
    'B3 budget + progression',
    budget.status === 201 && progress.status === 200 && entry?.limitAmount === 50000
  );

  const exportRes = await fetch(`${BASE}/wallets/${walletId}/export`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  const csv = await exportRes.text();
  // solde final attendu : 165000 - 100000 = 65000
  check(
    'B4 export CSV',
    exportRes.status === 200 && csv.includes('Date;Heure;Type') && csv.includes('65000'),
    `rows=${csv.split('\n').length - 1}`
  );

  // Isolation : autre utilisateur → 403 sur ce portefeuille
  const other = await api('POST', '/auth/register', {
    auth: false,
    body: { displayName: 'Autre', email: `other-${stamp}@mybudget.test`, password },
  });
  const otherToken = other.data?.data?.tokens?.accessToken;
  const iso = await fetch(`${BASE}/wallets/${walletId}/transactions`, {
    headers: { Authorization: `Bearer ${otherToken}` },
  });
  check('B5 isolation 403/404', iso.status === 403 || iso.status === 404, `status=${iso.status}`);

  console.log(failures === 0 ? '\nTOUS LES TESTS PASSENT' : `\n${failures} ECHEC(S)`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error('Erreur fatale :', err);
  process.exit(1);
});
