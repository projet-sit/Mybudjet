import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/money.dart';
import '../models/dashboard.dart';

/// Seuils notifiés (une seule fois par seuil et par période mensuelle).
const budgetAlertThresholds = [80, 100];

class BudgetAlertDecision {
  const BudgetAlertDecision({required this.budget, required this.threshold});
  final Budget budget;
  final int threshold;
}

String budgetAlertKey(String monthKey, String budgetId, int threshold) =>
    '$monthKey|$budgetId|$threshold';

/// Décide quelles alertes émettre pour des budgets donnés.
/// Pure : ne touche ni aux prefs ni au plugin (testable).
List<BudgetAlertDecision> decideBudgetAlerts({
  required List<Budget> budgets,
  required String monthKey,
  required Set<String> alreadyNotified,
}) {
  final decisions = <BudgetAlertDecision>[];
  for (final budget in budgets) {
    for (final threshold in budgetAlertThresholds) {
      if (budget.percent >= threshold &&
          !alreadyNotified.contains(budgetAlertKey(monthKey, budget.id, threshold))) {
        decisions.add(BudgetAlertDecision(budget: budget, threshold: threshold));
      }
    }
  }
  return decisions;
}

/// Alertes locales de budget. L'interrupteur du profil coupe tout.
/// Une opération qui fait atteindre 80 % puis 100 % déclenche une notification
/// (une seule fois par seuil et par période).
class BudgetAlertsService {
  BudgetAlertsService._();
  static final BudgetAlertsService instance = BudgetAlertsService._();

  static const pendingKey = 'budget_alerts_pending';
  static const notifiedKey = 'budget_alerts_notified';
  static const enabledKey = 'budget_alerts';
  static const _channelId = 'budget_alerts';
  static const _channelName = 'Budgets';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Initialise le plugin (idempotent). Appelée au démarrage.
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings();
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: darwin),
      );
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Alertes de budget MyBudget',
        importance: Importance.high,
      ));
    } catch (_) {
      // Plugin indisponible (tests ou plateforme non supportée) : alertes ignorées.
    }
    _initialized = true;
  }

  /// Vrai si l'utilisateur veut recevoir des alertes (défaut : oui).
  Future<bool> get enabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(enabledKey) ?? true;
  }

  /// Marque une vérification comme nécessaire (après une opération).
  Future<void> markPending(String walletId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(pendingKey, walletId);
  }

  /// Évalue les budgets affichés et notifie si un seuil est franchi.
  /// Ne notifie que si une vérification est en attente (posée par une écriture).
  /// Retourne le nombre d'alertes émises.
  Future<int> evaluate(List<Budget> budgets) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getString(pendingKey);
    if (pending == null) return 0;
    await prefs.remove(pendingKey);
    if (!(prefs.getBool(enabledKey) ?? true)) return 0;

    final monthKey = _monthKey(DateTime.now());
    final already = (prefs.getStringList(notifiedKey) ?? const <String>[]).toSet();
    final decisions = decideBudgetAlerts(
      budgets: budgets,
      monthKey: monthKey,
      alreadyNotified: already,
    );
    if (decisions.isEmpty) return 0;

    for (final decision in decisions) {
      already.add(budgetAlertKey(monthKey, decision.budget.id, decision.threshold));
    }
    await prefs.setStringList(notifiedKey, already.toList());
    await initialize();
    for (final decision in decisions) {
      try {
        await _show(decision);
      } catch (_) {
        // Une alerte ratée ne doit jamais interrompre le flux de l'app.
      }
    }
    return decisions.length;
  }

  Future<void> _show(BudgetAlertDecision decision) async {
    final isHundred = decision.threshold >= 100;
    await _plugin.show(
      decision.budget.hashCode ^ decision.threshold,
      isHundred ? 'Budget dépassé' : 'Budget bientôt atteint',
      '« ${decision.budget.category} » : '
          '${formatXof(decision.budget.spent)} utilisés sur ${formatXof(decision.budget.limitAmount)}'
          '${isHundred ? ' — le budget est dépassé.' : ' — 80 % du budget utilisés.'}',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Alertes de budget MyBudget',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  /// Demande la permission POST_NOTIFICATIONS (Android 13+).
  /// Retourne true si accordée (ou inutile sur cette plateforme / indisponible).
  Future<bool> requestPermission() async {
    try {
      await initialize();
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return true;
      return await android.requestNotificationsPermission() ?? false;
    } catch (_) {
      // Plateforme sans support ou refusée : pas de permission.
      return false;
    }
  }

  String _monthKey(DateTime now) =>
      '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
}
