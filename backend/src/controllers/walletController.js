const walletService = require('../services/walletService');
const { success } = require('../utils/response');
const ApiError = require('../utils/ApiError');

async function create(req, res, next) {
  try {
    if (!req.body || typeof req.body !== 'object') {
      throw ApiError.validation('Corps de requête invalide');
    }
    const wallet = await walletService.createWallet(req.uid, req.body);
    return success(res, { wallet }, 201);
  } catch (err) {
    return next(err);
  }
}

async function list(req, res, next) {
  try {
    const wallets = await walletService.listWallets(req.uid);
    return success(res, { wallets, hasWallet: wallets.length > 0 });
  } catch (err) {
    return next(err);
  }
}

async function get(req, res, next) {
  try {
    const wallet = await walletService.getWallet(req.uid, req.params.id);
    return success(res, { wallet });
  } catch (err) {
    return next(err);
  }
}

async function updateInitialAmount(req, res, next) {
  try {
    if (!req.body || typeof req.body !== 'object') {
      throw ApiError.validation('Corps de requête invalide');
    }
    const wallet = await walletService.updateInitialAmount(req.uid, req.params.id, req.body);
    return success(res, { wallet });
  } catch (err) {
    return next(err);
  }
}

async function getHistory(req, res, next) {
  try {
    const history = await walletService.getHistory(req.uid, req.params.id);
    return success(res, { history });
  } catch (err) {
    return next(err);
  }
}

async function reset(req, res, next) {
  try {
    const result = await walletService.resetWallet(req.uid, req.params.id, req.body || {});
    return success(res, {
      period: result.period,
      wallet: result.wallet,
      previousPeriodId: result.previousPeriodId,
      mode: result.mode,
      undoExpiresAt: result.undoExpiresAt,
    });
  } catch (err) {
    return next(err);
  }
}

module.exports = {
  create,
  list,
  get,
  updateInitialAmount,
  getHistory,
  reset,
};
