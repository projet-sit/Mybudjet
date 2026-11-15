const walletService = require('./walletService');
const transactionRepository = require('../repositories/transactionRepository');
const { toWallet } = require('../repositories/walletRepository');
const { isValidAmount } = require('../utils/money');
const ApiError = require('../utils/ApiError');

function validateAmount(value) {
  const amount = Number(value);
  if (!isValidAmount(amount)) {
    throw ApiError.validation('Le montant doit être un entier positif (FCFA)', { field: 'amount' });
  }
  return amount;
}

function todayAndNow() {
  const now = new Date();
  // Heure béninoise (UTC+1) pour l'horodatage lisible.
  const local = new Date(now.getTime() + 60 * 60 * 1000);
  return {
    date: local.toISOString().slice(0, 10),
    time: local.toISOString().slice(11, 16),
  };
}

/** Versement à l'épargne : l'argent sort du Reste vers l'épargne (atomique). */
async function deposit(uid, walletId, body) {
  const wallet = await walletService.getWallet(uid, walletId);
  const amount = validateAmount(body && body.amount);
  const { date, time } = todayAndNow();
  const result = await transactionRepository.createSavingsTransaction({
    walletId: wallet.id,
    type: 'savings_deposit',
    amount,
    date,
    time,
  });
  return { wallet: toWallet(result.wallet), transaction: result.transaction };
}

/** Retrait d'épargne : l'argent revient dans le Reste (atomique). */
async function withdraw(uid, walletId, body) {
  const wallet = await walletService.getWallet(uid, walletId);
  const amount = validateAmount(body && body.amount);
  const { date, time } = todayAndNow();
  const result = await transactionRepository.createSavingsTransaction({
    walletId: wallet.id,
    type: 'savings_withdrawal',
    amount,
    date,
    time,
  });
  return { wallet: toWallet(result.wallet), transaction: result.transaction };
}

/** « Tout récupérer » : toute l'épargne retourne dans le Reste, une seule écriture atomique. */
async function withdrawAll(uid, walletId) {
  const wallet = await walletService.getWallet(uid, walletId);
  const { date, time } = todayAndNow();
  const result = await transactionRepository.withdrawAllSavings({ walletId: wallet.id, date, time });
  return {
    wallet: toWallet(result.wallet),
    transaction: result.transaction, // null si déjà à 0
  };
}

module.exports = { deposit, withdraw, withdrawAll };
