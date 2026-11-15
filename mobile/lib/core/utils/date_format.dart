import 'package:intl/intl.dart';

/// Utilitaires de date UNIQUES pour toute l'app.
///
/// Règles :
/// - affichage toujours en heure LOCALE de l'appareil (Bénin, UTC+1) ;
/// - stockage côté serveur en UTC, on convertit au parsing ;
/// - jamais de date brute ni de toString à l'écran ;
/// - date seule stockée en "YYYY-MM-DD" = jour civil, JAMAIS décalée par le fuseau ;
/// - format d'affichage : JJ/MM/AAAA ; dans les listes : "JJ/MM/AAAA · HH:mm".
abstract final class DateFormatUtil {
  DateFormatUtil._();

  static final DateFormat _day = DateFormat('dd/MM/yyyy', 'fr_FR');
  static final DateFormat _time = DateFormat('HH:mm', 'fr_FR');
  static final DateFormat _dayTime = DateFormat('dd/MM/yyyy · HH:mm', 'fr_FR');
  static final DateFormat _monthYear = DateFormat('MM/yyyy', 'fr_FR');
  static final DateFormat _dayMonth = DateFormat('dd/MM', 'fr_FR');
  static final DateFormat _monthLong = DateFormat('MMMM yyyy', 'fr_FR');

  static final RegExp _dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  /// Parse une date stockée ("YYYY-MM-DD" ou ISO complet) vers un DateTime LOCAL.
  /// Une date seule est un jour civil : elle n'est JAMAIS décalée d'un jour par le fuseau.
  static DateTime? parseLocal(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    final onlyDate = _dateOnly.firstMatch(value);
    if (onlyDate != null) {
      return DateTime(
        int.parse(onlyDate.group(1)!),
        int.parse(onlyDate.group(2)!),
        int.parse(onlyDate.group(3)!),
      );
    }
    final parsed = DateTime.tryParse(value);
    return parsed?.toLocal();
  }

  /// "14/11/2026" — jamais brut, jamais vide (retourne '—' si illisible).
  static String formatDate(String? iso) {
    final d = parseLocal(iso);
    return d == null ? '—' : _day.format(d);
  }

  /// "14/11/2026 · 12:32" (24 h, locale du métier).
  static String formatDateTime(String? isoDate, String? isoTime) {
    final d = parseLocal(isoDate);
    if (d == null) return '—';
    final t = (isoTime ?? '').trim();
    if (t.isEmpty) return _day.format(d);
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(t);
    if (m != null) {
      final local = DateTime(d.year, d.month, d.day, int.parse(m.group(1)!), int.parse(m.group(2)!));
      return _dayTime.format(local);
    }
    return _day.format(d);
  }

  /// "Aujourd'hui", "Hier", sinon "JJ/MM/AAAA".
  static String relativeDayLabel(String? iso) {
    final d = parseLocal(iso);
    if (d == null) return '—';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    final diff = today.difference(target).inDays;
    if (diff == 0) return "Aujourd'hui";
    if (diff == 1) return 'Hier';
    return _day.format(d);
  }

  /// En-tête de mois : "11/2026".
  static String formatMonthHeader(DateTime date) => _monthYear.format(date);

  /// Libellé long de mois : "novembre 2026".
  static String formatMonthLong(DateTime date) => _monthLong.format(date);

  /// Court "14/11" pour les graphiques.
  static String formatDayMonth(DateTime date) => _dayMonth.format(date);

  static String formatTime(String? hhmm) {
    final t = (hhmm ?? '').trim();
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(t);
    if (m == null) return t;
    return _time.format(DateTime(2000, 1, 1, int.parse(m.group(1)!), int.parse(m.group(2)!)));
  }

  /// Minuit local du début du mois (jamais UTC).
  static DateTime startOfMonthLocal(DateTime date) => DateTime(date.year, date.month, 1);

  /// Dernier instant du mois, heure locale.
  static DateTime endOfMonthLocal(DateTime date) => DateTime(date.year, date.month + 1, 0, 23, 59, 59, 999);

  /// Clé 'YYYY-MM' en heure locale.
  static String toMonthKeyLocal(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}';

  /// Clé 'YYYY-MM-DD' en heure locale.
  static String toDayKeyLocal(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
