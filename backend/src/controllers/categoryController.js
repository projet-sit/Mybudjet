const categoryRepository = require('../repositories/categoryRepository');
const { success } = require('../utils/response');

async function list(req, res, next) {
  try {
    const data = await categoryRepository.listVisible(req.uid, req.query.type);
    return success(res, data);
  } catch (err) {
    return next(err);
  }
}

async function create(req, res, next) {
  try {
    const { category, created, fused } = await categoryRepository.create(req.uid, req.body || {});
    return success(res, { category, fused }, created ? 201 : 200);
  } catch (err) {
    return next(err);
  }
}

async function rename(req, res, next) {
  try {
    const data = await categoryRepository.rename(req.uid, req.params.id, req.body?.name);
    return success(res, data);
  } catch (err) {
    return next(err);
  }
}

async function remove(req, res, next) {
  try {
    const confirmBudgets = req.query.confirmBudgets === '1' || req.query.confirmBudgets === 'true';
    const data = await categoryRepository.remove(req.uid, req.params.id, { confirmBudgets });
    return success(res, data);
  } catch (err) {
    return next(err);
  }
}

module.exports = { list, create, rename, remove };
