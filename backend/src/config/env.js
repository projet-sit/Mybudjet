require('dotenv').config();
const crypto = require('crypto');

const required = (name) => process.env[name] || null;

const databaseUrl = process.env.DATABASE_URL || null;
// SSL requis par les Postgres managés (Neon, Render…). Activé si DATABASE_URL
// contient sslmode=require ou si DB_SSL=true. Désactivé pour le Docker local.
const dbSsl =
  /sslmode=require/i.test(databaseUrl || '') || process.env.DB_SSL === 'true';

const env = {
  port: parseInt(process.env.PORT || '3000', 10),
  nodeEnv: process.env.NODE_ENV || 'development',
  corsOrigin: process.env.CORS_ORIGIN || '*',
  database: {
    connectionString: databaseUrl,
    ssl: dbSsl ? { rejectUnauthorized: false } : false,
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '5432', 10),
    database: process.env.DB_NAME || 'mybudget',
    user: process.env.DB_USER || 'mybudget',
    password: process.env.DB_PASSWORD || 'mybudget_dev_password',
  },
  jwt: {
    secret: process.env.JWT_SECRET || null,
    accessExpiresIn: process.env.JWT_ACCESS_EXPIRES_IN || '1h',
    refreshExpiresIn: process.env.JWT_REFRESH_EXPIRES_IN || '30d',
  },
  // Un token de réinitialisation ne doit jamais être exposé sur un environnement
  // partagé. Cette option existe uniquement pour faciliter les essais locaux.
  exposeDevResetToken:
    process.env.NODE_ENV === 'development' && process.env.EXPOSE_DEV_RESET_TOKEN === 'true',
  rateLimit: {
    windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS || '60000', 10),
    max: parseInt(process.env.RATE_LIMIT_MAX || '120', 10),
  },
};

if (!env.jwt.secret) {
  if (env.nodeEnv === 'production') {
    throw new Error('JWT_SECRET manquant : renseigne-le dans backend/.env');
  }
  env.jwt.secret = crypto.randomBytes(32).toString('hex');
  console.warn('[env] JWT_SECRET non défini : secret éphémère généré pour le développement.');
}

module.exports = env;
