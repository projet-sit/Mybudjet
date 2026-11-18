/// Normalisation et validation des noms de catégories (miroir exact du backend).
library;

const expenseDefaultOrder = [
  'Alimentation', 'Transport', 'Logement', 'Santé', 'Études',
  'Communication', 'Loisirs', 'Shopping', 'Abonnements', 'Famille',
];
const incomeDefaultOrder = ['Salaire', 'Business', 'Cadeau', 'Bourse'];
const otherName = 'Autres';

/// Minuscules + sans accents + espaces multiples réduits.
String normalizeCategoryName(String input) {
  return input
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .toLowerCase()
      .split('')
      .map(_normalizeChar)
      .join();
}

String _normalizeChar(String ch) {
  final code = ch.codeUnitAt(0);
  // Latin accents courants (NFD non décomposé par le dart sans package : on mappe à la main)
  const map = {
    0xE0: 'a', 0xE1: 'a', 0xE2: 'a', 0xE3: 'a', 0xE4: 'a', 0xE5: 'a',
    0xC0: 'a', 0xC1: 'a', 0xC2: 'a', 0xC3: 'a', 0xC4: 'a', 0xC5: 'a',
    0xE8: 'e', 0xE9: 'e', 0xEA: 'e', 0xEB: 'e',
    0xC8: 'e', 0xC9: 'e', 0xCA: 'e', 0xCB: 'e',
    0xEC: 'i', 0xED: 'i', 0xEE: 'i', 0xEF: 'i',
    0xCC: 'i', 0xCD: 'i', 0xCE: 'i', 0xCF: 'i',
    0xF2: 'o', 0xF3: 'o', 0xF4: 'o', 0xF5: 'o', 0xF6: 'o',
    0xD2: 'o', 0xD3: 'o', 0xD4: 'o', 0xD5: 'o', 0xD6: 'o',
    0xF9: 'u', 0xFA: 'u', 0xFB: 'u', 0xFC: 'u',
    0xD9: 'u', 0xDA: 'u', 0xDB: 'u', 0xDC: 'u',
    0xE7: 'c', 0xC7: 'c',
    0xF1: 'n', 0xD1: 'n',
    0xFF: 'y', 0xDD: 'y',
  };
  return map[code] ?? ch;
}

const _namePattern = r"^[A-Za-zÀ-ÖØ-öø-ÿ0-9](?:[A-Za-zÀ-ÖØ-öø-ÿ0-9' \-]*[A-Za-zÀ-ÖØ-öø-ÿ0-9])?$";
final _nameRegex = RegExp(_namePattern);

class CategoryNameCheck {
  const CategoryNameCheck._(this.ok, this.value, this.normalized, this.error);
  final bool ok;
  final String value;
  final String normalized;
  final String? error;

  static CategoryNameCheck valid(String value) => CategoryNameCheck._(true, value, normalizeCategoryName(value), null);
  static CategoryNameCheck invalid(String error) => CategoryNameCheck._(false, '', '', error);
}

/// Valide un nom de catégorie saisi librement (« Autres ») :
/// - obligatoire (après retrait des espaces),
/// - 2 à 30 caractères,
/// - la première lettre est mise en majuscule (automatique),
/// - lettres, chiffres, espaces, apostrophes et tirets uniquement.
CategoryNameCheck validateCategoryName(String input) {
  final trimmed = input.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (trimmed.isEmpty) {
    return CategoryNameCheck.invalid('Le nom est obligatoire');
  }
  final value = trimmed[0].toUpperCase() + trimmed.substring(1);
  if (value.length < 2 || value.length > 30) {
    return CategoryNameCheck.invalid('Le nom doit faire entre 2 et 30 caractères');
  }
  if (!_nameRegex.hasMatch(value)) {
    return CategoryNameCheck.invalid("Lettres, chiffres, espaces, apostrophes et tirets uniquement");
  }
  return CategoryNameCheck.valid(value);
}
