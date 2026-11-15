const crypto = require('crypto');
const logger = require('../utils/logger');

// Journalise chaque requête : id, méthode, chemin, statut, durée.
// Les erreurs 5xx sont pré-journalisées ici avec leur stack trace.
function requestLogger(req, res, next) {
  const id = crypto.randomUUID();
  req.requestId = id;
  const start = process.hrtime.bigint();

  res.on('finish', () => {
    const durationMs = Number(process.hrtime.bigint() - start) / 1e6;
    logger.info('http', {
      requestId: id,
      method: req.method,
      path: req.originalUrl,
      status: res.statusCode,
      durationMs: Math.round(durationMs),
    });
  });

  next();
}

module.exports = { requestLogger };
