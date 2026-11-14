const test = require('node:test');
const assert = require('node:assert/strict');
const app = require('../../src/app');

test('Ciel API Phase 5 - Stats, Export CSV & Alertes Budget', async (t) => {
  let server;
  let baseUrl;

  await new Promise((resolve) => {
    server = app.listen(0, () => {
      const port = server.address().port;
      baseUrl = `http://127.0.0.1:${port}`;
      resolve();
    });
  });

  t.after(() => {
    server.close();
  });

  await t.test('GET /stats/monthly - Refuse les requêtes sans token', async () => {
    const res = await fetch(`${baseUrl}/stats/monthly`);
    assert.equal(res.status, 401);
    const json = await res.json();
    assert.equal(json.success, false);
  });

  await t.test('GET /stats/monthly - Retourne 6 mois à 0 pour un compte sans opération (aucune valeur fictive)', async () => {
    const res = await fetch(`${baseUrl}/stats/monthly`, {
      headers: { Authorization: 'Bearer test_user_empty' },
    });
    assert.equal(res.status, 200);
    const json = await res.json();
    assert.equal(json.success, true);
    assert.equal(Array.isArray(json.data.months), true);
    assert.equal(json.data.months.length, 6);

    // Chaque mois doit avoir strictement 0 dépense et 0 catégorie inventée
    for (const m of json.data.months) {
      assert.equal(m.totalExpense, 0);
      assert.equal(m.totalIncome, 0);
      assert.deepEqual(m.categories, []);
    }
  });

  await t.test('GET /stats/monthly?months=3 - Respecte le paramètre de fenêtre mensuelle', async () => {
    const res = await fetch(`${baseUrl}/stats/monthly?months=3`, {
      headers: { Authorization: 'Bearer test_user_empty' },
    });
    assert.equal(res.status, 200);
    const json = await res.json();
    assert.equal(json.data.months.length, 3);
  });

  await t.test('GET /stats/monthly?months=999 - Validation Zod rejette les valeurs hors limites', async () => {
    const res = await fetch(`${baseUrl}/stats/monthly?months=999`, {
      headers: { Authorization: 'Bearer test_user_empty' },
    });
    assert.equal(res.status, 400);
    const json = await res.json();
    assert.equal(json.success, false);
  });

  await t.test('GET /export/excel - Génère un classeur Excel XML avec onglets financiers et épargne', async () => {
    const res = await fetch(`${baseUrl}/export/excel`, {
      headers: { Authorization: 'Bearer test_user_empty' },
    });
    assert.equal(res.status, 200);
    const contentType = res.headers.get('content-type') || '';
    assert.equal(contentType.includes('application/vnd.ms-excel'), true);

    const text = await res.text();
    assert.equal(text.includes('<?xml version="1.0" encoding="UTF-8"?>'), true);
    assert.equal(text.includes('<Worksheet ss:Name="Synthèse &amp; Épargne">'), true);
    assert.equal(text.includes('<Worksheet ss:Name="Opérations">'), true);
  });

  await t.test('GET /export/csv - Renvoie seulement l\'en-tête CSV si aucune opération n\'existe', async () => {
    const res = await fetch(`${baseUrl}/export/csv`, {
      headers: { Authorization: 'Bearer test_user_empty' },
    });
    assert.equal(res.status, 200);
    const contentType = res.headers.get('content-type') || '';
    assert.equal(contentType.includes('text/csv'), true);

    const text = await res.text();
    // Le texte commence par le BOM utf-8 puis l'en-tête
    assert.equal(text.includes('"ID","Date","Type","Montant (FCFA)","Catégorie","Note","Objectif"'), true);
    // Aucune fausse ligne de transaction présente
    const lines = text.trim().split('\n');
    assert.equal(lines.length, 1);
  });

  await t.test('POST /alerts/check - Rejette sans token et valide les seuils de budget', async () => {
    const unauthRes = await fetch(`${baseUrl}/alerts/check`, { method: 'POST' });
    assert.equal(unauthRes.status, 401);

    const authRes = await fetch(`${baseUrl}/alerts/check`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer test_user_empty',
      },
      body: JSON.stringify({ month: '2026-11' }),
    });
    assert.equal(authRes.status, 200);
    const json = await authRes.json();
    assert.equal(json.success, true);
    assert.equal(json.data.month, '2026-11');
    assert.equal(Array.isArray(json.data.alerts), true);
  });
});
