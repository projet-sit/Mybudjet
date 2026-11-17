// Normalisation des noms de catégories (miroir exact côté app mobile).
// - trim, espaces multiples réduits à un seul
// - casse insensible
// - accents retirés (NFD + marques diacritiques)
const DIACRITICS = /\p{Diacritic}/gu;

function normalizeName(input) {
  return String(input || '')
    .normalize('NFD')
    .replace(DIACRITICS, '')
    .toLowerCase()
    .trim()
    .replace(/\s+/g, ' ');
}

// Lettres (avec accents), chiffres, espaces, apostrophes, tirets ; 2 à 30 caractères ;
// commence et finit par une lettre/chiffre.
const NAME_RE = /^[A-Za-zÀ-ÖØ-öø-ÿ0-9](?:[A-Za-zÀ-ÖØ-öø-ÿ0-9' \-]*[A-Za-zÀ-ÖØ-öø-ÿ0-9])?$/u;
const MIN_LEN = 2;
const MAX_LEN = 30;
const MAX_CUSTOM_PER_TYPE = 30;

function validateName(input) {
  const value = String(input || '').trim().replace(/\s+/g, ' ');
  if (value.length < MIN_LEN || value.length > MAX_LEN) {
    return { ok: false, error: `Le nom doit faire entre ${MIN_LEN} et ${MAX_LEN} caractères` };
  }
  if (!NAME_RE.test(value)) {
    return { ok: false, error: 'Lettres, chiffres, espaces, apostrophes et tirets uniquement' };
  }
  return { ok: true, value, normalized: normalizeName(value) };
}

const DEFAULT_ORDER = {
  expense: [
    'Alimentation', 'Transport', 'Logement', 'Santé', 'Études',
    'Communication', 'Loisirs', 'Shopping', 'Abonnements', 'Famille',
  ],
  income: ['Salaire', 'Business', 'Cadeau', 'Bourse'],
};
const DEFAULT_LAST = 'Autres';

module.exports = { normalizeName, validateName, DEFAULT_ORDER, DEFAULT_LAST, MAX_CUSTOM_PER_TYPE };
