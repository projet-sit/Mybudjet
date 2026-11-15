const savingsService = require('../services/savingsService');
const { success } = require('../utils/response');
const ApiError = require('../utils/ApiError');

const UUID_RE = /^[0-9a-f-]{36}$/i;

const requireWalletId = (req) => {
  const id = req.params.id || req.params.walletId;
  if (!id || !UUID_RE.test(id)) {
    throw ApiError.validation('Identifiant de portefeuille invalide');
  }
  return id;
};

async function deposit(req, res, next) {
  try {
    const walletId = requireWalletId(req);
    const result = await savingsService.deposit(req.uid, walletId, req.body);
    return success(res, { wallet: result.wallet, transaction: result.transaction });
  } catch (err) {
    return next(err);
  }
}

async function withdraw(req, res, next) {
  try {
    const walletId = requireWalletId(req);
    const result = await savingsService.withdraw(req.uid, walletId, req.body);
    return success(res, { wallet: result.wallet, transaction: result.transaction });
  } catch (err) {
    return next(err);
  }
}

async function withdrawAll(req, res, next) {
  try {
    const walletId = requireWalletId(req);
    const result = await savingsService.withdrawAll(req.uid, walletId);
    return success(res, { wallet: result.wallet, transaction: result.transaction });
  } catch (err) {
    return next(err);
  }
}

module.exports = { deposit, withdraw, withdrawAll };
