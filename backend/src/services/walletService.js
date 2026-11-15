const ApiError = require('../utils/ApiError');
const { isValidAmount } = require('../utils/money');
const walletRepository = require('../repositories/walletRepository');
const periodRepository = require('../repositories/periodRepository');

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const NAME_MAX = 100;

function validateName(name) {
  const clean = String(name || '').trim().replace(/\s+/g, ' ');
  if (clean.length < 2 || clean.length > NAME_MAX) {
    throw ApiError.validation('Le nom du portefeuille doit contenir entre 2 et 100 caractères', {
      field: 'name',
    });
  }
  return clean;
}

function validateInitialAmount(value) {
  if (value === undefined || value === null || value === '') {
    return 0; // Un portefeuille peut démarrer à 0.
  }
  const amount = Number(value);
  if (!isValidAmount(amount) && amount !== 0) {
    throw ApiError.validation('Le montant initial doit être un entier positif (FCFA)', {
      field: 'initialAmount',
    });
  }
  return amount;
}

function validateStartDate(value) {
  if (!value) return new Date().toISOString().slice(0, 10);
  if (typeof value !== 'string' || !DATE_RE.test(value) || Number.isNaN(Date.parse(value))) {
    throw ApiError.validation('La date de début doit être au format YYYY-MM-DD', {
      field: 'startDate',
    });
  }
  return value;
}

function validateCurrency(value) {
  const currency = value ? String(value).toUpperCase().trim() : 'XOF';
  if (currency.length < 3 || currency.length > 8 || !/^[A-Z0-9]+$/.test(currency)) {
    throw ApiError.validation('Devise invalide', { field: 'currency' });
  }
  return currency;
}

async function createWallet(uid, body) {
  const wallet = await walletRepository.create({
    userId: uid,
    name: validateName(body.name),
    initialAmount: validateInitialAmount(body.initialAmount),
    startDate: validateStartDate(body.startDate),
    currency: validateCurrency(body.currency),
  });
  return wallet;
}

async function listWallets(uid) {
  return walletRepository.findByUserId(uid);
}

async function getWallet(uid, walletId) {
  const wallet = await walletRepository.findById(walletId);
  if (!wallet) throw ApiError.notFound('Portefeuille introuvable');
  if (wallet.userId !== uid) throw ApiError.forbidden('Ce portefeuille ne t’appartient pas');
  return wallet;
}

async function updateInitialAmount(uid, walletId, body) {
  const wallet = await getWallet(uid, walletId);
  const newAmount = validateInitialAmount(body.initialAmount);
  const updated = await walletRepository.updateInitialAmount(wallet.id, newAmount);
  return updated;
}

async function getHistory(uid, walletId) {
  const wallet = await getWallet(uid, walletId);
  return walletRepository.getInitialAmountHistory(wallet.id);
}

async function resetWallet(uid, walletId, body = {}) {
  const wallet = await getWallet(uid, walletId); // vérifie propriété
  const includeSavings = body.includeSavings === true;
  // Archive d'abord (la période part dans l'historique), annulation possible 10 s.
  return periodRepository.resetWithArchive({ walletId: wallet.id, userId: uid, includeSavings });
}

module.exports = {
  createWallet,
  listWallets,
  getWallet,
  updateInitialAmount,
  getHistory,
  resetWallet,
};
