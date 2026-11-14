const ApiError = require('../utils/ApiError');
const walletService = require('./walletService');
const periodRepository = require('../repositories/periodRepository');

const MODES = ['reset', 'carry'];

function validateMode(value) {
  const mode = String(value || '').toLowerCase();
  if (!MODES.includes(mode)) {
    throw ApiError.validation('Choisis comment démarrer le nouveau mois', { field: 'mode' });
  }
  return mode;
}

async function getPeriod(uid, walletId) {
  const wallet = await walletService.getWallet(uid, walletId);
  return periodRepository.getInfo(wallet.id);
}

async function nextPeriod(uid, walletId, body) {
  const wallet = await walletService.getWallet(uid, walletId);
  const mode = validateMode(body && body.mode);
  return periodRepository.nextPeriod({ walletId: wallet.id, userId: uid, mode });
}

async function undoPeriod(uid, walletId, periodId) {
  const wallet = await walletService.getWallet(uid, walletId);
  if (!/^[0-9a-f-]{36}$/i.test(String(periodId || ''))) {
    throw ApiError.validation('Identifiant de période invalide');
  }
  return periodRepository.undoPeriod({ walletId: wallet.id, userId: uid, periodId });
}

module.exports = { getPeriod, nextPeriod, undoPeriod };
