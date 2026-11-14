const app = require('./app');
const env = require('./config/env');

const server = app.listen(env.port, () => {
  const dbTarget = env.database.connectionString
    ? 'DATABASE_URL (hébergement managé)'
    : `${env.database.host}:${env.database.port}/${env.database.database}`;
  console.log(`\nMYBUDGET API démarrée : http://localhost:${env.port}/api/v1/health`);
  console.log(`Environnement : ${env.nodeEnv}`);
  console.log(`Base PostgreSQL : ${dbTarget}`);
});

module.exports = server;
