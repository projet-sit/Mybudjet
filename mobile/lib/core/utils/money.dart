import 'package:intl/intl.dart';

/// Formatage monétaire FCFA — entiers uniquement.
/// Exemple : 155000 → "155 000 FCFA"
String formatXof(int amount, {bool withCurrency = true}) {
  final formatter = NumberFormat('#,##0', 'fr_FR');
  final grouped = formatter.format(amount).replaceAll('\u202F', ' ').replaceAll('\u00A0', ' ');
  return withCurrency ? '$grouped FCFA' : grouped;
}

/// Date ISO → "17/11/2026" (tolère un suffixe d'heure)
String formatDateFr(String isoDate) {
  final raw = (isoDate).trim();
  if (raw.isEmpty) return raw;
  final parsed = DateTime.tryParse(raw);
  if (parsed != null) {
    final d = parsed.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
  final parts = raw.split('-');
  if (parts.length >= 3) {
    final day = parts[2].split(RegExp(r'[T ]')).first.padLeft(2, '0');
    return '$day/${parts[1].padLeft(2, '0')}/${parts[0]}';
  }
  return raw;
}

/// Date + heure temps réel (heure du Bénin) : "14/11/2026 · 14:05"
String formatDateTimeFr(String isoDate, String? time) {
  final base = formatDateFr(isoDate);
  final t = (time ?? '').trim();
  return t.isEmpty ? base : '$base · $t';
}
