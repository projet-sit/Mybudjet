/**
 * Applique les migrations SQL manquantes sur la base PostgreSQL MYBUDGET.
 * Les migrations appliquées sont suivies dans schema_migrations.
 * Usage : npm run migrate
 */
const fs = require('fs');
const path = require('path');
const db = require('../config/db');

const MIGRATIONS_DIR = path.join(__dirname, 'migrations');

async function migrate() {
  // Table de suivi
  await db.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      name       VARCHAR(255) PRIMARY KEY,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `);

  const { rows } = await db.query('SELECT name FROM schema_migrations');
  const applied = new Set(rows.map((r) => r.name));

  const files = fs
    .readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .sort();

  let count = 0;
  for (const file of files) {
    if (applied.has(file)) continue;
    const sql = fs.readFileSync(path.join(MIGRATIONS_DIR, file), 'utf8');
    await db.query(sql);
    await db.query('INSERT INTO schema_migrations (name) VALUES ($1)', [file]);
    console.log(`[migrate] appliquée : ${file}`);
    count++;
  }

  // Rattrapage idempotent des catégories historiques (nécessite Node, pas du SQL brut).
  const { backfillCategories } = require('./backfill_categories');
  const stats = await backfillCategories();
  console.log(
    `[backfill] transactions : ${stats.txMatched} rattachées (${stats.txCreated} catégories créées) · ` +
    `budgets : ${stats.budgetsMatched} rattachés (${stats.budgetsCreated} catégories créées)`
  );

  if (count === 0) console.log('[migrate] aucune migration en attente');
  await db.pool.end();
}

migrate().catch((err) => {
  console.error('[migrate] échec :', err.message);
  process.exit(1);
});
