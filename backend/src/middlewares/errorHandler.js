const env = require('../config/env');
const logger = require('../utils/logger');

function notFoundHandler(req, res) {
  return res.status(404).json({
    success: false,
    error: { code: 'NOT_FOUND', message: `Route introuvable : ${req.method} ${req.originalUrl}` },
  });
}

function errorHandler(err, req, res, _next) {
  const statusCode = err.statusCode || 500;
  const code = err.code || (statusCode === 500 ? 'INTERNAL_ERROR' : 'ERROR');

  if (statusCode >= 500) {
    logger.error('request_error', {
      requestId: req.requestId,
      method: req.method,
      path: req.originalUrl,
      status: statusCode,
      code,
      err: (err && err.stack) || String(err),
    });
    if (err.code === 'auth/id-token-expired') {
      return res.status(401).json({
        success: false,
        error: { code: 'UNAUTHORIZED', message: 'Session expirée, reconnecte-toi' },
      });
    }
  }

  const message =
    statusCode >= 500 && env.nodeEnv === 'production'
      ? 'Erreur interne du serveur'
      : err.message || 'Erreur interne du serveur';

  return res.status(statusCode).json({
    success: false,
    error: {
      code,
      message,
      ...(err.details ? { details: err.details } : {}),
    },
  });
}

module.exports = { notFoundHandler, errorHandler };
