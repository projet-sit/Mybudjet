const express = require('express');
const rateLimit = require('express-rate-limit');
const logger = require('../utils/logger');

// Rapport de plantage côté mobile : anonyme, minimaliste, fire-and-forget.
// Objectif : savoir qu'un téléphone plante en production sans embarquer de SDK.
const router = express.Router();

router.use(
  rateLimit({
    windowMs: 60 * 1000,
    max: 20,
    standardHeaders: true,
    legacyHeaders: false,
    message: { success: false, error: { code: 'RATE_LIMITED', message: 'Trop de rapports' } },
  })
);

// Authentification facultative : on veut les rapports même avant connexion,
// mais un token valide est associé pour aider au diagnostic sans exposer l'IP.
router.post('/', (req, res) => {
  const body = req.body || {};
  const review = (v, max) => (typeof v === 'string' ? v.slice(0, max) : undefined);
  const entry = {
    message: review(body.message, 300) || 'erreur inconnue',
    stack: review(body.stack, 1500),
    screen: review(body.screen, 80),
    platform: review(body.platform, 80),
    appVersion: review(body.appVersion, 40),
    uid: typeof req.headers.authorization === 'string' ? 'present' : 'anonyme',
  };
  logger.warn('client_error', entry);
  return res.status(204).end();
});

module.exports = router;
