const express = require('express');
const periodService = require('../services/periodService');
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

router.get('/:walletId/period', async (req, res, next) => {
  try {
    const data = await periodService.getPeriod(req.uid, requireWalletId(req));
    return success(res, data);
  } catch (err) {
    return next(err);
  }
});

router.post('/:walletId/period/next', async (req, res, next) => {
  try {
    const data = await periodService.nextPeriod(req.uid, requireWalletId(req), req.body || {});
    return success(res, data, 201);
  } catch (err) {
    return next(err);
  }
});

router.post('/:walletId/period/:periodId/undo', async (req, res, next) => {
  try {
    const data = await periodService.undoPeriod(
      req.uid,
      requireWalletId(req),
      req.params.periodId
    );
    return success(res, data);
  } catch (err) {
    return next(err);
  }
});

router.get('/:walletId/periods', async (req, res, next) => {
  try {
    const data = await periodService.listPeriods(req.uid, requireWalletId(req));
    return success(res, data);
  } catch (err) {
    return next(err);
  }
});

router.post('/:walletId/periods/:periodId/restore', async (req, res, next) => {
  try {
    const data = await periodService.restorePeriod(req.uid, requireWalletId(req), req.params.periodId);
    return success(res, data);
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
