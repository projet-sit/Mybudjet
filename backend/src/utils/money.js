/**
 * Utilitaires monétaires — FCFA (XOF).
 * RÈGLE ABSOLUE : tous les montants sont des ENTIERS. Jamais de flottants.
 */

/** Valide qu'un montant est un entier strictement positif. */
function isValidAmount(value) {
  return Number.isSafeInteger(value) && value > 0;
}

/** Convertit une entrée utilisateur (string/number) en entier FCFA, ou null si invalide. */
function parseAmount(value) {
  if (typeof value === 'number') {
    return Number.isInteger(value) ? value : null;
  }
  if (typeof value === 'string') {
    // FCFA : seuls les séparateurs d'espaces des milliers sont autorisés.
    // Retirer '.' ou ',' transformerait par exemple « 1.5 » en « 15 ».
    const cleaned = value.replace(/\s/g, '');
    if (!/^\d+$/.test(cleaned)) return null;
    const parsed = parseInt(cleaned, 10);
    return Number.isSafeInteger(parsed) ? parsed : null;
  }
  return null;
}

/** Formate un montant en FCFA : 155000 -> "155 000 FCFA" */
function formatXof(amount) {
  return `${amount.toLocaleString('fr-FR')} FCFA`;
}

module.exports = { isValidAmount, parseAmount, formatXof };
