import 'package:intl/intl.dart';

/// Formatage monétaire FCFA — entiers uniquement.
/// Exemple : 155000 → "155 000 FCFA"
String formatXof(int amount, {bool withCurrency = true}) {
  final formatter = NumberFormat('#,##0', 'fr_FR');
  final grouped = formatter.format(amount).replaceAll('\u202F', ' ').replaceAll('\u00A0', ' ');
  return withCurrency ? '$grouped FCFA' : grouped;
}

/// Date ISO (YYYY-MM-DD) → "01/04/2025"
String formatDateFr(String isoDate) {
  if (isoDate.length < 10) return isoDate;
  final parts = isoDate.split('-');
  return '${parts[2]}/${parts[1]}/${parts[0]}';
}

/// Date + heure temps réel (heure du Bénin) : "14/11/2026 · 14:05"
String formatDateTimeFr(String isoDate, String? time) {
  final base = formatDateFr(isoDate);
  final t = (time ?? '').trim();
  return t.isEmpty ? base : '$base · $t';
}
