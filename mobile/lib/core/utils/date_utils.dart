import 'package:intl/intl.dart';

class AppDateUtils {
  AppDateUtils._();

  /// Retourne la clé de mois standard 'YYYY-MM' (UTC)
  static String toMonthKey(DateTime date) {
    final utc = date.toUtc();
    final month = utc.month.toString().padLeft(2, '0');
    return '${utc.year}-$month';
  }

  /// Retourne la clé de jour standard 'YYYY-MM-DD' (UTC)
  static String toDayKey(DateTime date) {
    final utc = date.toUtc();
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    return '${utc.year}-$month-$day';
  }

  /// En-tête de mois "11/2026"
  static String formatMonthHeader(DateTime date) {
    return DateFormat('MM/yyyy').format(date);
  }

  /// Nom court du mois pour les graphiques (ex: '01/11')
  static String formatMonthShort(DateTime date) => DateFormat('M/yy').format(date);

  /// Format de date lisible pour les listes de transactions (ex: '12/11/2026')
  static String formatShortDate(DateTime date) => DateFormat('dd/MM/yyyy').format(date);

  /// En-tête de groupement journalier (ex: 'Aujourd'hui', 'Hier', ou '12/11/2026')
  static String formatDayHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = today.difference(target).inDays;

    if (diff == 0) return "Aujourd'hui";
    if (diff == 1) return 'Hier';
    return DateFormat('dd/MM/yyyy').format(date);
  }

  /// Retourne la liste des [count] derniers mois dans l'ordre chronologique
  static List<DateTime> getLastMonths(int count, {DateTime? referenceDate}) {
    final ref = referenceDate ?? DateTime.now();
    final List<DateTime> months = [];
    for (int i = count - 1; i >= 0; i--) {
      var year = ref.year;
      var month = ref.month - i;
      while (month <= 0) {
        month += 12;
        year -= 1;
      }
      months.add(DateTime.utc(year, month, 1));
    }
    return months;
  }
}
