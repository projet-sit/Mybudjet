/**
 * Vérification de l'atomicité de POST /api/v1/me/reset sur une VRAIE PostgreSQL.
 *
 * Nécessite une base locale éphémère (Docker `mybudget-db`, port 5434) :
 *   npm run test:rollback
 *
 * Le test crée une base jetable `mybudget_rollback_test`, y joue TOUTES les migrations
 * (y compris 010 + backfill), démarre le vrai serveur sur un port libre, et vérifie :
 *   1. un reset forcé à échouer avant le commit ne supprime RIEN ;
 *   2. un reset normal vide tout (et data_epoch avance de 0 à 1).
 * La base jetable est supprimée à la fin (finally).
 *
 * Remarque : pg-mem (test:e2e) n'honore pas les ROLLBACK, donc ce scénario ne peut
 * pas y être prouvé.
 */
const { execFileSync } = require('child_process');
process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'rollback_test_secret_not_for_production';
process.env.JWT_ACCESS_EXPIRES_IN = '1h';
process.env.PGCONNECT_TIMEOUT = '5';

const ADMIN_URL = 'postgresql://mybudget:mybudget_dev_password@localhost:5434/postgres';
const TEST_DB = 'mybudget_rollback_test';
const TEST_URL = `postgresql://mybudget:mybudget_dev_password@localhost:5434/${TEST_DB}`;
const PORT = 3998;

async function psql(sql, url) {
  const { Client } = require('pg');
  const client = new Client({ connectionString: url });
  await client.connect();
  try {
    return await client.query(sql);
  } finally {
    await client.end();
  }
}

async function http(method, path, { body, token, headers } = {}) {
  const res = await fetch(`http://127.0.0.1:${PORT}${path}`, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...headers,
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, json: await res.json().catch(() => null) };
}

(async () => {
  console.log(`[rollback] création de la base jetable ${TEST_DB}…`);
  await psql(`DROP DATABASE IF EXISTS ${TEST_DB}`, ADMIN_URL);
  await psql(`CREATE DATABASE ${TEST_DB}`, ADMIN_URL);

  try {
    // 1) Migrations + backfill sur la base jetable
    execFileSync(process.execPath, ['src/database/migrate.js'], {
      env: { ...process.env, DATABASE_URL: TEST_URL, NODE_ENV: 'test' },
      stdio: 'inherit',
    });

    // 2) Démarre le vrai serveur sur la base jetable
    const server = require('child_process').spawn(process.execPath, ['src/server.js'], {
      env: {
        ...process.env,
        DATABASE_URL: TEST_URL,
        NODE_ENV: 'test',
        JWT_SECRET: process.env.JWT_SECRET,
        PORT: String(PORT),
      },
      stdio: 'pipe',
    });
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('serveur non démarré (5 s)')), 5000);
      server.stdout.on('data', (d) => {
        if (String(d).includes(String(PORT))) { clearTimeout(timer); resolve(); }
      });
      server.on('error', reject);
    });

    try {
      // 3) Crée des données
      const reg = await http('POST', '/api/v1/auth/register', {
        body: { displayName: 'Test Rollback', phone: '+22995000001', email: 'rollback@mybudget.app', password: 'secret123' },
      });
      const auth = reg.json.data.tokens.accessToken;
      const wallet = await http('POST', '/api/v1/wallets', { body: { name: 'Budget', initialAmount: 100000 }, token: auth });
      const walletId = wallet.json.data.wallet.id;
      await http('POST', `/api/v1/wallets/${walletId}/transactions`, {
        body: { type: 'expense', amount: 10000, category: 'Alimentation', date: '2026-11-17' }, token: auth,
      });
      await http('POST', '/api/v1/categories', { body: { type: 'expense', name: 'Coiffure' }, token: auth });

      // 4) Reset forcé à échouer AVANT le commit → tout doit rester
      const fail = await http('POST', '/api/v1/me/reset', { body: {}, token: auth, headers: { 'x-test-fail-reset': '1' } });
      if (fail.status !== 500) throw new Error(`le reset forcé devrait répondre 500, reçu ${fail.status}`);
      const walletsAfterFail = await http('GET', '/api/v1/wallets', { token: auth });
      if (walletsAfterFail.json.data.wallets.length !== 1) {
        throw new Error(`reset forcé : le portefeuille a disparu (${walletsAfterFail.json.data.wallets.length})`);
      }
      const txs = await http('GET', `/api/v1/wallets/${walletId}/transactions`, { token: auth });
      if (txs.json.data.total !== 1) throw new Error('reset forcé : la transaction a disparu');
      const cats = await http('GET', '/api/v1/categories?type=expense', { token: auth });
      if (!cats.json.data.categories.some((c) => c.name === 'Coiffure')) {
        throw new Error('reset forcé : la catégorie personnalisée a disparu');
      }
      console.log('[rollback] OK : un échec avant commit ne supprime RIEN');

      // 5) Reset normal → tout disparaît, epoch avancé
      const ok = await http('POST', '/api/v1/me/reset', { body: {}, token: auth });
      if (ok.json.data.dataEpoch !== 1) throw new Error('reset normal : dataEpoch attendu = 1');
      const walletsAfter = await http('GET', '/api/v1/wallets', { token: auth });
      if (walletsAfter.json.data.wallets.length !== 0) throw new Error('reset normal : des portefeuilles restent');
      console.log('[rollback] OK : reset normal vide tout et data_epoch = 1');
      console.log('[rollback] SUCCÈS');
    } finally {
      server.kill();
    }
  } finally {
    await psql(`DROP DATABASE IF EXISTS ${TEST_DB}`, ADMIN_URL);
    console.log(`[rollback] base jetable supprimée`);
    process.exit(0);
  }
})().catch((err) => {
  console.error('[rollback] ÉCHEC :', err.message);
  process.exit(1);
});
