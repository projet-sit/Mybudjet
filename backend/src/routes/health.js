const express = require('express');
const { ping } = require('../config/db');
const env = require('../config/env');

const router = express.Router();

router.get('/', async (_req, res, next) => {
  try {
    let database = 'erreur de connexion';
    try {
      const ok = await ping();
      database = ok ? 'connecté' : 'réponse inattendue';
    } catch (err) {
      database = `indisponible : ${err.message}`;
    }
    return res.json({
      success: true,
      data: {
        service: 'MYBUDGET API',
        version: '1.1.0',
        status: 'ok',
        nodeEnv: env.nodeEnv,
        database,
        time: new Date().toISOString(),
      },
    });
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
