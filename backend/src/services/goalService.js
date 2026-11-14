const ApiError = require('../utils/ApiError');
const walletService = require('./walletService');
const goalRepository = require('../repositories/goalRepository');

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function validateName(value) {
  const name = String(value || '').trim().replace(/\s+/g, ' ');
  if (name.length < 2 || name.length > 100) {
    throw ApiError.validation('Le nom de l’objectif doit contenir entre 2 et 100 caractères', {
      field: 'name',
    });
  }
  return name;
}

function validateAmount(value, field = 'targetAmount') {
  const amount = Number(value);
  if (!Number.isInteger(amount) || amount <= 0) {
    throw ApiError.validation('Le montant doit être un entier positif (FCFA)', { field });
  }
  return amount;
}

function validateDeadline(value) {
  if (value === undefined || value === null || value === '') return null;
  if (typeof value !== 'string' || !DATE_RE.test(value) || Number.isNaN(Date.parse(value))) {
    throw ApiError.validation('La date limite doit être au format YYYY-MM-DD', {
      field: 'deadline',
    });
  }
  return value;
}

async function list(uid, walletId) {
  const wallet = await walletService.getWallet(uid, walletId);
  return { goals: await goalRepository.list(wallet.id) };
}

async function create(uid, walletId, body) {
  const wallet = await walletService.getWallet(uid, walletId);
  const goal = await goalRepository.create({
    userId: uid,
    walletId: wallet.id,
    name: validateName(body.name),
    targetAmount: validateAmount(body.targetAmount),
    deadline: validateDeadline(body.deadline),
  });
  return { goal };
}

async function update(uid, walletId, goalId, body) {
  const wallet = await walletService.getWallet(uid, walletId);
  const existing = await goalRepository.findById(wallet.id, goalId);
  if (!existing) throw ApiError.notFound('Objectif introuvable');

  const targetAmount = validateAmount(body.targetAmount ?? existing.targetAmount);
  if (targetAmount < existing.savedAmount) {
    throw ApiError.validation(
      'La cible ne peut pas être inférieure au montant déjà épargné',
      { field: 'targetAmount', saved: existing.savedAmount }
    );
  }

  const goal = await goalRepository.update({
    walletId: wallet.id,
    goalId,
    name: validateName(body.name ?? existing.name),
    targetAmount,
    deadline: validateDeadline(body.deadline !== undefined ? body.deadline : existing.deadline),
  });
  return { goal };
}

async function remove(uid, walletId, goalId) {
  const wallet = await walletService.getWallet(uid, walletId);
  return goalRepository.remove(wallet.id, goalId);
}

async function contribute(uid, walletId, goalId, body) {
  const wallet = await walletService.getWallet(uid, walletId);
  const amount = validateAmount(body.amount, 'amount');
  return goalRepository.contribute({ walletId: wallet.id, goalId, amount });
}

async function withdraw(uid, walletId, goalId, body) {
  const wallet = await walletService.getWallet(uid, walletId);
  const amount = validateAmount(body.amount, 'amount');
  return goalRepository.withdraw({ walletId: wallet.id, goalId, amount });
}

module.exports = { list, create, update, remove, contribute, withdraw };
