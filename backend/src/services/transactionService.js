const transactionRepository = require('../repositories/transactionRepository');
const periodRepository = require('../repositories/periodRepository');
const walletService = require('./walletService');
const categoryRepository = require('../repositories/categoryRepository');
const ApiError = require('../utils/ApiError');

async function create(uid, walletId, body) {
  const wallet = await walletService.getWallet(uid, walletId); // vérifie propriétaire
  const data = require('../validators/transactionValidator').validateTransactionBody(body);
  const cat = await categoryRepository.resolve(uid, data.type, {
    categoryId: data.categoryId,
    category: data.category,
  });
  return transactionRepository.createTransaction({
    walletId: wallet.id,
    ...data,
    category: cat.name,
    categoryId: cat.id,
  });
}

async function update(uid, walletId, txId, body) {
  const wallet = await walletService.getWallet(uid, walletId);
  const existing = await transactionRepository.getTransactionForWallet({ walletId: wallet.id, txId });
  if (!existing) throw ApiError.notFound('Transaction introuvable');
  const data = require('../validators/transactionValidator').validateTransactionBody(body, {
    partial: true,
    current: existing,
  });
  // PATCH partiel : fusion avec la transaction existante (aucun champ perdu).
  const merged = {
    type: data.type ?? existing.type,
    amount: data.amount ?? existing.amount,
    category: data.category ?? existing.category,
    categoryId: data.categoryId,
    description: data.description !== undefined ? data.description : existing.description,
    date: data.date ?? existing.date,
    time: data.time ?? existing.time,
    paymentMethod: data.paymentMethod !== undefined ? data.paymentMethod : existing.paymentMethod,
  };
  // Catégorie : résolution base (personnalisée utilisateur ou défaut) si fournie.
  if (data.categoryId !== undefined || data.category !== undefined) {
    const cat = await categoryRepository.resolve(uid, merged.type, {
      categoryId: data.categoryId,
      category: data.category,
    });
    merged.category = cat.name;
    merged.categoryId = cat.id;
  } else {
    delete merged.categoryId;
  }
  return transactionRepository.updateTransaction({ walletId: wallet.id, txId, ...merged });
}

async function remove(uid, walletId, txId) {
  const wallet = await walletService.getWallet(uid, walletId);
  return transactionRepository.deleteTransaction({ walletId: wallet.id, txId });
}

async function get(uid, walletId, txId) {
  const wallet = await walletService.getWallet(uid, walletId);
  const tx = await transactionRepository.getTransactionForWallet({ walletId: wallet.id, txId });
  if (!tx) throw ApiError.notFound('Transaction introuvable');
  return tx;
}

async function list(uid, walletId, query) {
  const wallet = await walletService.getWallet(uid, walletId);

  const page = Math.max(1, parseInt(query.page || '1', 10) || 1);
  const limit = Math.min(100, Math.max(1, parseInt(query.limit || '20', 10) || 20));

  const minAmount = query.minAmount !== undefined ? Number(query.minAmount) : undefined;
  const maxAmount = query.maxAmount !== undefined ? Number(query.maxAmount) : undefined;

  const activePeriod =
    query.all === '1' || query.all === 'true'
      ? null
      : (await periodRepository.getInfo(wallet.id)).period;

  return transactionRepository.listTransactions({
    walletId: wallet.id,
    periodId: activePeriod ? activePeriod.id : undefined,
    type: query.type,
    category: query.category,
    dateFrom: query.dateFrom,
    dateTo: query.dateTo,
    minAmount: Number.isFinite(minAmount) ? minAmount : undefined,
    maxAmount: Number.isFinite(maxAmount) ? maxAmount : undefined,
    search: query.search,
    sortBy: query.sortBy,
    sortDir: query.sortDir,
    page,
    limit,
  });
}

async function recalculate(uid, walletId) {
  const wallet = await walletService.getWallet(uid, walletId);
  return transactionRepository.recalculateBalance(wallet.id);
}

/** Phase 10 — export CSV (entièrement reconstitué depuis la base, aucune donnée fictive). */
function csvEscape(value) {
  const str = value === null || value === undefined ? '' : String(value);
  if (/[;"\n]/.test(str)) return `"${str.replace(/"/g, '""')}"`;
  return str;
}

async function exportCsv(uid, walletId) {
  const wallet = await walletService.getWallet(uid, walletId);
  const transactions = await transactionRepository.exportAll(wallet.id);

  const header = 'Date;Heure;Type;Categorie;Description;Mode de paiement;Montant;Solde apres';
  let running = Number(wallet.initialAmount);
  const typeLabels = {
    'expense': 'Dépense',
    'income': 'Revenu',
    'savings_deposit': 'Versement épargne',
    'savings_withdrawal': 'Retrait épargne',
  };

  const lines = transactions.map((t) => {
    // Les opérations d'épargne ne modifient pas le solde (même compte).
    const delta = t.type === 'income' ? t.amount : (t.type === 'expense' ? -t.amount : 0);
    running += delta;
    return [
      t.date,
      t.time,
      typeLabels[t.type] || t.type,
      t.category,
      t.description,
      t.paymentMethod,
      t.amount,
      running,
    ]
      .map(csvEscape)
      .join(';');
  });
  return { wallet, csv: [header, ...lines].join('\n') };
}

module.exports = { create, update, remove, get, list, recalculate, exportCsv };
