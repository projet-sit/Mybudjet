const express = require('express');
const budgetRepository = require('../repositories/budgetRepository');
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

const requireBudgetId = (req) => {
  const id = req.params.budgetId;
  if (!id || !/^[0-9a-f-]{36}$/i.test(id)) {
    throw ApiError.validation('Identifiant de budget invalide');
  }
  return id;
};

router.get('/:walletId/budgets', async (req, res, next) => {
  try {
    const withProgress = req.query.progress === '1' || req.query.progress === 'true';
    const data = await budgetRepository.list(req.uid, requireWalletId(req), {
      withProgress,
      dateFrom: req.query.dateFrom,
      dateTo: req.query.dateTo,
    });
    return success(res, data);
  } catch (err) {
    return next(err);
  }
});

router.post('/:walletId/budgets', async (req, res, next) => {
  try {
    const budget = await budgetRepository.create(req.uid, requireWalletId(req), req.body || {});
    return success(res, { budget }, 201);
  } catch (err) {
    return next(err);
  }
});

router.patch('/:walletId/budgets/:budgetId', async (req, res, next) => {
  try {
    const budget = await budgetRepository.update(
      req.uid,
      requireWalletId(req),
      requireBudgetId(req),
      req.body || {}
    );
    return success(res, { budget });
  } catch (err) {
    return next(err);
  }
});

router.delete('/:walletId/budgets/:budgetId', async (req, res, next) => {
  try {
    const result = await budgetRepository.remove(req.uid, requireWalletId(req), requireBudgetId(req));
    return success(res, result);
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
