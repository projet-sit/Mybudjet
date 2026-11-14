const { Pool } = require('pg');
const env = require('./env');

const pool = new Pool(
  env.database.connectionString
    ? {
        connectionString: env.database.connectionString,
        ssl: env.database.ssl,
        max: 10,
        idleTimeoutMillis: 30000,
      }
    : {
        host: env.database.host,
        port: env.database.port,
        database: env.database.database,
        user: env.database.user,
        password: env.database.password,
        max: 10,
        idleTimeoutMillis: 30000,
      }
);

pool.on('error', (err) => {
  console.error('[db] erreur inattendue du pool PostgreSQL :', err.message);
});

async function query(text, params) {
  return pool.query(text, params);
}

async function withTransaction(handler) {
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
}

async function ping() {
  const { rows } = await query('SELECT 1 AS ok');
  return rows[0].ok === 1;
}

module.exports = { pool, query, withTransaction, ping };
