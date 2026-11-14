const express = require('express');
const goalService = require('../services/goalService');
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

const requireGoalId = (req) => {
  const id = req.params.goalId;
  if (!id || !/^[0-9a-f-]{36}$/i.test(id)) {
    throw ApiError.validation('Identifiant d’objectif invalide');
  }
  return id;
};

router.get('/:walletId/goals', async (req, res, next) => {
  try {
    const data = await goalService.list(req.uid, requireWalletId(req));
    return success(res, data);
  } catch (err) {
    return next(err);
  }
});

router.post('/:walletId/goals', async (req, res, next) => {
  try {
    const data = await goalService.create(req.uid, requireWalletId(req), req.body || {});
    return success(res, data, 201);
  } catch (err) {
    return next(err);
  }
});

router.patch('/:walletId/goals/:goalId', async (req, res, next) => {
  try {
    const data = await goalService.update(
      req.uid,
      requireWalletId(req),
      requireGoalId(req),
      req.body || {}
    );
    return success(res, data);
  } catch (err) {
    return next(err);
  }
});

router.delete('/:walletId/goals/:goalId', async (req, res, next) => {
  try {
    const data = await goalService.remove(req.uid, requireWalletId(req), requireGoalId(req));
    return success(res, data);
  } catch (err) {
    return next(err);
  }
});

router.post('/:walletId/goals/:goalId/contribute', async (req, res, next) => {
  try {
    const data = await goalService.contribute(
      req.uid,
      requireWalletId(req),
      requireGoalId(req),
      req.body || {}
    );
    return success(res, data);
  } catch (err) {
    return next(err);
  }
});

router.post('/:walletId/goals/:goalId/withdraw', async (req, res, next) => {
  try {
    const data = await goalService.withdraw(
      req.uid,
      requireWalletId(req),
      requireGoalId(req),
      req.body || {}
    );
    return success(res, data);
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
