// Harness d'intégration backend complet avec PostgreSQL en mémoire (pg-mem).
// Joue le vrai serveur Express + vraies migrations SQL, sans Docker ni réseau.
// Usage : const { startApp } = require('./setup.e2e');
const path = require('path');
const fs = require('fs');
const { newDb } = require('pg-mem');

function applyMigrations(db) {
  const dir = path.join(__dirname, '..', '..', 'src', 'database', 'migrations');
  const files = fs
    .readdirSync(dir)
    .filter((f) => f.endsWith('.sql'))
    .sort();
  // pg-mem ne supporte pas CREATE EXTENSION, ni les fonctions/triggers plpgsql :
  // on les ignore pour le test (l'app applique les mêmes bornes côté service).
  const stripped = (sql) =>
    sql
      .replace(/CREATE\s+EXTENSION[^;]*;/gi, '')
      .replace(/CREATE\s+OR\s+REPLACE\s+FUNCTION[\s\S]*?LANGUAGE\s+plpgsql\s*;/gi, '')
      .replace(/DROP\s+TRIGGER\s+IF\s+EXISTS[^;]*;/gi, '')
      .replace(/CREATE\s+TRIGGER[\s\S]*?EXECUTE\s+FUNCTION[\s\S]*?;/gi, '')
      // Backfill historique (base vide en test) : pg-mem ne gère pas ce GROUP BY.
      .replace(/INSERT\s+INTO\s+periods[\s\S]*?GROUP\s+BY[^;]*;/gi, '')
      // Idem pour l'attachement des anciennes transactions (base vide en test).
      .replace(/UPDATE\s+transactions\s+t[\s\S]*?IS\s+NULL\s*;/gi, '')
      // pg-mem gère mal ses index secondaires (recherches par $1 retournent des résultats périmés) :
      // le harness s'en passe — les périodes et transactions restent peu nombreuses en test.
      .replace(/CREATE\s+UNIQUE\s+INDEX[^;]*;/gi, '')
      .replace(/CREATE\s+INDEX[^;]*;/gi, '');
  db.public.none(
    'CREATE TABLE IF NOT EXISTS schema_migrations (name VARCHAR(255) PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())',
  );
  for (const file of files) {
    const sql = stripped(fs.readFileSync(path.join(dir, file), 'utf8'));
    db.public.none(sql);
    // Valeur inline (nom de fichier sûr, alphanumérique + tirets + .sql).
    db.public.none(`INSERT INTO schema_migrations (name) VALUES ('${file}')`);
  }
}

/** Démarre tout : base mémoire + migrations + vrai app Express sur port aléatoire. */
async function startApp() {
  const db = newDb();
  db.public.registerFunction({
    name: 'gen_random_uuid',
    returns: 'uuid',
    // Sans « impure », pg-mem évalue la valeur par défaut UNE fois par requête
    // et réinsère le même UUID (violation de clé primaire).
    impure: true,
    implementation: () => require('crypto').randomUUID(),
  });
  const { DataType } = require('pg-mem');
  db.public.registerFunction({
    name: 'to_char',
    args: [DataType.date, DataType.text],
    returns: DataType.text,
    impure: true,
    implementation: (d, fmt) => {
      if (!d) return null;
      const date = new Date(d);
      if (Number.isNaN(date.getTime())) return String(d);
      const pad = (n) => String(n).padStart(2, '0');
      const yyyy = date.getUTCFullYear();
      const mm = pad(date.getUTCMonth() + 1);
      const dd = pad(date.getUTCDate());
      if (fmt === 'YYYY-MM-DD') return `${yyyy}-${mm}-${dd}`;
      if (fmt === 'YYYY-MM') return `${yyyy}-${mm}`;
      return null;
    },
  });
  applyMigrations(db);

  const { Pool: MemPool } = db.adapters.createPg();

  // Branche le pool pg-mem sur la config db existante AVANT que l'app ne la charge.
  const configPath = require.resolve('../../src/config/db');
  delete require.cache[configPath];
  const dbModule = require(configPath);
  const pool = new MemPool();
  dbModule.pool = pool;
  dbModule.query = (text, params) => pool.query(text, params);
  dbModule.withTransaction = async (handler) => {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const result = await handler(client);
      await client.query('COMMIT');
      return result;
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  };
  dbModule.ping = async () => {
    const r = await pool.query('SELECT 1 AS ok');
    return r.rows[0].ok === 1;
  };

  // Variables d'environnement avant de charger l'app.
  process.env.NODE_ENV = 'test';
  process.env.JWT_SECRET = 'e2e_secret_for_tests_only_not_for_production';
  process.env.JWT_ACCESS_EXPIRES_IN = '1h';
  process.env.JWT_REFRESH_EXPIRES_IN = '30d';

  const app = require('../../src/app');
  const server = await new Promise((resolve) => {
    const s = app.listen(0, () => resolve(s));
  });
  const port = server.address().port;
  return { server, db, pool, baseUrl: `http://127.0.0.1:${port}/api/v1` };
}

module.exports = { startApp };
