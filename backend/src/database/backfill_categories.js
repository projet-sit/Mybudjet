/**
 * Backfill des catégories historiques (category_id) — joué par `npm run migrate`
 * juste après les migrations SQL, et/ou seul via `node src/database/backfill_categories.js`.
 *
 * Idempotent : ne touche que les lignes `category_id` NULL.
 * Sans perte : ne modifie pas le texte `category` existant quand il est valide ;
 * les noms invalides (hérités) sont rattachés à « Autres ».
 */
const db = require('../config/db');
const { normalizeName, validateName } = require('../utils/categoryNames');
const crypto = require('crypto');

async function backfillCategories(queryFn) {
  const run = queryFn || db.query;
  const stats = { txMatched: 0, txCreated: 0, budgetsMatched: 0, budgetsCreated: 0 };

  const { rows: defaults } = await run(
    "SELECT id, type, normalized_name FROM categories WHERE is_default = true"
  );
  const sys = new Map(defaults.map((r) => [`${r.type}|${r.normalized_name}`, r.id]));

  const customCache = new Map();
  const getOrCreateCustom = async (client, userId, type, rawName) => {
    const check = validateName(rawName);
    if (!check.ok) return sys.get(`${type}|autres`);
    const key = `${userId}|${type}|${check.normalized}`;
    if (customCache.has(key)) return customCache.get(key);
    const found = await client.query(
      'SELECT id FROM categories WHERE user_id = $1 AND type = $2 AND normalized_name = $3 LIMIT 1',
      [userId, type, check.normalized]
    );
    if (found.rows[0]) {
      customCache.set(key, found.rows[0].id);
      return found.rows[0].id;
    }
    const inserted = await client.query(
      `INSERT INTO categories (id, user_id, type, name, normalized_name, is_default, icon_key)
       VALUES ($1, $2, $3, $4, $5, false, 'label') RETURNING id`,
      [crypto.randomUUID(), userId, type, check.value, check.normalized]
    );
    customCache.set(key, inserted.rows[0].id);
    return inserted.rows[0].id;
  };

  const resolveCategory = async (client, userId, type, rawCategory) => {
    const normalized = normalizeName(rawCategory);
    if (sys.has(`${type}|${normalized}`)) return { id: sys.get(`${type}|${normalized}`), created: false };
    const check = validateName(rawCategory);
    if (!check.ok) return { id: sys.get(`${type}|autres`), created: false };
    const before = customCache.size;
    const id = await getOrCreateCustom(client, userId, type, check.value);
    return { id, created: customCache.size !== before };
  };

  await db.withTransaction(async (client) => {
    const txs = await client.query(
      `SELECT t.id, t.type, t.category, w.user_id
       FROM transactions t JOIN wallets w ON w.id = t.wallet_id
       WHERE t.category_id IS NULL AND t.type IN ('expense', 'income')`
    );
    for (const t of txs.rows) {
      const r = await resolveCategory(client, t.user_id, t.type, t.category);
      const upd = await client.query(
        'UPDATE transactions SET category_id = $1 WHERE id = $2 AND category_id IS NULL',
        [r.id, t.id]
      );
      stats.txMatched += upd.rowCount || 0;
      if (r.created && upd.rowCount) stats.txCreated += 1;
    }

    const budgets = await client.query(
      `SELECT b.id, b.category, w.user_id
       FROM budgets b JOIN wallets w ON w.id = b.wallet_id
       WHERE b.category_id IS NULL`
    );
    for (const b of budgets.rows) {
      const r = await resolveCategory(client, b.user_id, 'expense', b.category);
      const upd = await client.query(
        'UPDATE budgets SET category_id = $1 WHERE id = $2 AND category_id IS NULL',
        [r.id, b.id]
      );
      stats.budgetsMatched += upd.rowCount || 0;
      if (r.created && upd.rowCount) stats.budgetsCreated += 1;
    }
  });

  return stats;
}

if (require.main === module) {
  backfillCategories()
    .then((s) => {
      console.log(`[backfill] transactions : ${s.txMatched} rattachées, ${s.txCreated} catégories créées`);
      console.log(`[backfill] budgets : ${s.budgetsMatched} rattachés, ${s.budgetsCreated} catégories créées`);
      return db.pool.end();
    })
    .catch((err) => {
      console.error('[backfill] échec :', err.message);
      process.exit(1);
    });
}

module.exports = { backfillCategories };
