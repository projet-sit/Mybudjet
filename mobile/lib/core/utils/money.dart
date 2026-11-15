import 'package:intl/intl.dart';

import 'date_format.dart';

/// Formatage monétaire FCFA — entiers uniquement.
/// Exemple : 155000 → "155 000 FCFA"
String formatXof(int amount, {bool withCurrency = true}) {
  final formatter = NumberFormat('#,##0', 'fr_FR');
  final grouped = formatter.format(amount).replaceAll('\u202F', ' ').replaceAll('\u00A0', ' ');
  return withCurrency ? '$grouped FCFA' : grouped;
}

/// Date ISO → "17/11/2026" (tolère un suffixe d'heure ; jamais de date brute).
String formatDateFr(String isoDate) => DateFormatUtil.formatDate(isoDate);

/// Date + heure locale : "14/11/2026 · 14:05"
String formatDateTimeFr(String isoDate, String? time) =>
    DateFormatUtil.formatDateTime(isoDate, time);
