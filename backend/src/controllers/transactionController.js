const transactionService = require('../services/transactionService');
const { success } = require('../utils/response');
const ApiError = require('../utils/ApiError');

const requireId = (req) => {
  const id = req.params.id || req.params.walletId;
  if (!id || typeof id !== 'string' || !/^[0-9a-f-]{36}$/i.test(id)) {
    throw ApiError.validation('Identifiant de portefeuille invalide');
  }
  return id;
};

const requireTxId = (req) => {
  const id = req.params.txId;
  if (!id || !/^[0-9a-f-]{36}$/i.test(id)) {
    throw ApiError.validation('Identifiant de transaction invalide');
  }
  return id;
};

async function create(req, res, next) {
  try {
    const walletId = requireId(req);
    const result = await transactionService.create(req.uid, walletId, req.body);
    return success(res, {
      transaction: result.transaction,
      newBalance: result.newBalance,
    }, 201);
  } catch (err) {
    return next(err);
  }
}

async function update(req, res, next) {
  try {
    const walletId = requireId(req);
    const txId = requireTxId(req);
    const result = await transactionService.update(req.uid, walletId, txId, req.body);
    return success(res, { transaction: result.transaction, newBalance: result.newBalance });
  } catch (err) {
    return next(err);
  }
}

async function remove(req, res, next) {
  try {
    const walletId = requireId(req);
    const txId = requireTxId(req);
    const result = await transactionService.remove(req.uid, walletId, txId);
    return success(res, { newBalance: result.newBalance, deleted: true });
  } catch (err) {
    return next(err);
  }
}

async function get(req, res, next) {
  try {
    const walletId = requireId(req);
    const txId = requireTxId(req);
    const transaction = await transactionService.get(req.uid, walletId, txId);
    return success(res, { transaction });
  } catch (err) {
    return next(err);
  }
}

async function list(req, res, next) {
  try {
    const walletId = requireId(req);
    const result = await transactionService.list(req.uid, walletId, req.query || {});
    return success(res, result);
  } catch (err) {
    return next(err);
  }
}

async function recalculate(req, res, next) {
  try {
    const walletId = requireId(req);
    const result = await transactionService.recalculate(req.uid, walletId);
    return success(res, result);
  } catch (err) {
    return next(err);
  }
}

module.exports = { create, update, remove, get, list, recalculate };
