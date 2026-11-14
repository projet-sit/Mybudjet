const express = require('express');
const statsService = require('../services/statsService');
const transactionService = require('../services/transactionService');
const { success } = require('../utils/response');
const ApiError = require('../utils/ApiError');
const { authenticate } = require('../middlewares/authenticate');

const router = express.Router();

router.use(authenticate);

const requireWalletId = (req) => {
  const id = req.params.walletId;
  if (!id || !/^[0-9a-f-]{36}$/i.test(id)) {
    throw ApiError.validation('Identifiant de portefeuille invalide');
  }
  return id;
};

// Phase 6 — tableau de bord
router.get('/:walletId/dashboard', async (req, res, next) => {
  try {
    const data = await statsService.dashboard(req.uid, requireWalletId(req));
    return success(res, data);
  } catch (err) {
    return next(err);
  }
});

// Phase 8 — statistiques
router.get('/:walletId/stats', async (req, res, next) => {
  try {
    const data = await statsService.stats(req.uid, requireWalletId(req), req.query || {});
    return success(res, data);
  } catch (err) {
    return next(err);
  }
});

// Phase 10 — export CSV des transactions
router.get('/:walletId/export', async (req, res, next) => {
  try {
    const { wallet, csv } = await transactionService.exportCsv(req.uid, requireWalletId(req));
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="mybudget-${wallet.name}.csv"`);
    return res.send(`\uFEFF${csv}`);
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
