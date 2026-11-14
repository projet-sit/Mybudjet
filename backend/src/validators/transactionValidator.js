const ApiError = require('../utils/ApiError');
const { isValidAmount } = require('../utils/money');
const transactionRepository = require('../repositories/transactionRepository');

const EXPENSE_CATEGORIES = [
  'Alimentation', 'Transport', 'Logement', 'Santé', 'Études',
  'Communication', 'Loisirs', 'Shopping', 'Abonnements', 'Famille', 'Autres',
];
const INCOME_CATEGORIES = ['Salaire', 'Business', 'Cadeau', 'Bourse', 'Autres'];
const PAYMENT_METHODS = ['Espèces', 'Mobile Money', 'Carte', 'Virement'];
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const TIME_RE = /^\d{2}:\d{2}$/;

function validateTransactionBody(body, { partial = false, current = null } = {}) {
  if (!body || typeof body !== 'object') throw ApiError.validation('Corps de requête invalide');
  const out = {};

  // Montant : entier strictement positif
  if (body.amount !== undefined || !partial) {
    const amount = Number(body.amount);
    if (!isValidAmount(amount)) {
      throw ApiError.validation('Le montant doit être un entier positif (FCFA)', { field: 'amount' });
    }
    out.amount = amount;
  }

  // Type
  if (body.type !== undefined || !partial) {
    const type = String(body.type || '');
    if (!['expense', 'income'].includes(type)) {
      throw ApiError.validation("Le type doit être 'expense' ou 'income'", { field: 'type' });
    }
    out.type = type;
  }

  const type = out.type || current?.type || 'expense';

  // Catégorie (whitelist selon le type)
  if (body.category !== undefined || !partial) {
    const category = String(body.category || '').trim();
    const allowed = type === 'expense' ? EXPENSE_CATEGORIES : INCOME_CATEGORIES;
    if (!allowed.includes(category)) {
      throw ApiError.validation(
        `Catégorie invalide pour ${type === 'expense' ? 'une dépense' : 'un revenu'}`,
        { field: 'category', allowed }
      );
    }
    out.category = category;
  }

  // Description (optionnelle)
  if (body.description !== undefined) {
    out.description = body.description ? String(body.description).trim().slice(0, 200) : null;
  } else if (!partial) {
    out.description = null;
  }

  // Date
  if (body.date !== undefined || !partial) {
    const date = String(body.date || '').slice(0, 10);
    if (!DATE_RE.test(date) || Number.isNaN(Date.parse(date))) {
      throw ApiError.validation('La date doit être au format YYYY-MM-DD', { field: 'date' });
    }
    out.date = date;
  }

  // Heure (défaut : maintenant)
  if (body.time !== undefined || !partial) {
    const time = body.time || new Date().toISOString().slice(11, 16);
    if (!TIME_RE.test(time)) {
      throw ApiError.validation("L'heure doit être au format HH:mm", { field: 'time' });
    }
    out.time = time;
  }

  // Mode de paiement (dépenses)
  if (body.paymentMethod !== undefined) {
    if (body.paymentMethod && !PAYMENT_METHODS.includes(body.paymentMethod)) {
      throw ApiError.validation('Mode de paiement invalide', { field: 'paymentMethod', allowed: PAYMENT_METHODS });
    }
    out.paymentMethod = body.paymentMethod || null;
  } else if (!partial) {
    out.paymentMethod = type === 'expense' ? 'Espèces' : null;
  }

  return out;
}

module.exports = { validateTransactionBody, EXPENSE_CATEGORIES, INCOME_CATEGORIES, PAYMENT_METHODS };
