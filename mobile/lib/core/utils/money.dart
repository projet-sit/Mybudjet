import 'package:intl/intl.dart';

import '../../services/currency_service.dart';
import 'date_format.dart';

/// Devises supportées. Le montant est TOUJOURS stocké en base en XOF (entier) ;
/// la devise n'influe que sur l'affichage et la saisie.
const supportedCurrencies = ['XOF', 'EUR', 'USD'];

const currencyLabels = {
  'XOF': 'Franc CFA (FCFA)',
  'EUR': 'Euro (€)',
  'USD': 'Dollar américain (\$)',
};

const currencyShortLabels = {
  'XOF': 'FCFA (XOF)',
  'EUR': 'Euro (EUR)',
  'USD': 'Dollar (USD)',
};

/// Formatage monétaire selon la devise.
/// - XOF : 0 décimale — « 25 000 FCFA »
/// - EUR : 2 décimales (virgule) — « 38,11 € »
/// - USD : 2 décimales — « 41.20 $ »
/// [amountXof] est toujours l'entier stocké en base (XOF).
String formatMoney(int amountXof, {bool withCurrency = true, String currency = 'XOF'}) {
  final code = supportedCurrencies.contains(currency) ? currency : 'XOF';
  final value = CurrencyService.convertFromXof(amountXof, code);

  switch (code) {
    case 'EUR':
      final grouped = NumberFormat('#,##0.00', 'fr_FR')
          .format(value)
          .replaceAll('\u00A0', ' ')
          .replaceAll('\u202F', ' ');
      return withCurrency ? '$grouped €' : grouped;
    case 'USD':
      final grouped = NumberFormat('#,##0.00', 'en_US').format(value);
      return withCurrency ? '$grouped \$' : grouped;
    case 'XOF':
    default:
      final grouped = NumberFormat('#,##0', 'fr_FR')
          .format(amountXof)
          .replaceAll('\u00A0', ' ')
          .replaceAll('\u202F', ' ');
      return withCurrency ? '$grouped FCFA' : grouped;
  }
}

/// Forme « devise courante » : lit la devise active du [CurrencyService].
/// À utiliser dans les écrans (les widgets qui regardent [currencyControllerProvider]
/// se reconstruisent au changement de devise).
String formatMoneyCurrent(int amountXof, {bool withCurrency = true}) =>
    formatMoney(amountXof, withCurrency: withCurrency, currency: CurrencyService.instance.current);

/// Symbole court d'une devise (pour les suffixes de saisie).
String currencySymbol(String code) => switch (code) {
      'EUR' => '€',
      'USD' => '\$',
      _ => 'FCFA',
    };

/// Saisie utilisateur → entier XOF à stocker. Accepte la virgule et le point.
/// Une virgule finale (« 10, ») est tolérée (→ 10). Renvoie null si illisible.
int? enteredToXof(String raw, String currency) {
  var normalized = raw.trim().replaceAll('\u00A0', '').replaceAll(' ', '').replaceAll(',', '.');
  normalized = normalized.replaceAll(RegExp(r'\.$'), ''); // « 10, » → « 10 »
  if (normalized.isEmpty) return null;
  final value = double.tryParse(normalized);
  if (value == null || value < 0) return null;
  return CurrencyService.convertToXof(value, currency);
}

/// Groupe les milliers d'une saisie en cours (partie entière), en gardant la
/// fraction tapée telle quelle. Ex : « 1234567,8 » → « 1 234 567,8 ».
String groupEnteredInput(String raw) {
  final normalized = raw.replaceAll('.', ',');
  final comma = normalized.indexOf(',');
  final intPart = comma == -1 ? normalized : normalized.substring(0, comma);
  final fracPart = comma == -1 ? null : normalized.substring(comma + 1);
  final digits = intPart.replaceAll(RegExp(r'\s+'), '');
  if (digits.isEmpty) return fracPart == null ? '' : ',$fracPart';
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(' ');
    grouped.write(digits[i]);
  }
  return fracPart == null ? grouped.toString() : '$grouped,$fracPart';
}

/// Date ISO → "17/11/2026" (tolère un suffixe d'heure ; jamais de date brute).
String formatDateFr(String isoDate) => DateFormatUtil.formatDate(isoDate);

/// Date + heure locale : "14/11/2026 · 14:05"
String formatDateTimeFr(String isoDate, String? time) =>
    DateFormatUtil.formatDateTime(isoDate, time);
