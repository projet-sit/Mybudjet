import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mybudget/models/dashboard.dart';
import 'package:mybudget/services/budget_alerts_service.dart';

Budget _budget(String id, int limit, int percent) => Budget(
      id: id,
      walletId: 'w1',
      category: 'Alimentation',
      limitAmount: limit,
      spent: (limit * percent / 100).round(),
      percent: percent,
      alertLevel: percent >= 100 ? 100 : percent >= 80 ? 80 : 50,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('decideBudgetAlerts', () {
    test('seuil 80 % déclenche une alerte, 100 % en déclenche une autre', () {
      final decisions = decideBudgetAlerts(
        budgets: [_budget('b1', 10000, 80), _budget('b2', 10000, 100)],
        monthKey: '2026-11',
        alreadyNotified: {},
      );
      expect(decisions.length, 3);
      expect(decisions.map((d) => d.threshold).toList()..sort(), [80, 80, 100]);
    });

    test('seuil 50 % ne déclenche rien (hors périmètre des alertes)', () {
      final decisions = decideBudgetAlerts(
        budgets: [_budget('b1', 10000, 50)],
        monthKey: '2026-11',
        alreadyNotified: {},
      );
      expect(decisions, isEmpty);
    });

    test('un budget déjà notifié à 80 % ne repart pas à 80, mais à 100 oui', () {
      final decisions = decideBudgetAlerts(
        budgets: [_budget('b1', 10000, 100)],
        monthKey: '2026-11',
        alreadyNotified: {budgetAlertKey('2026-11', 'b1', 80)},
      );
      expect(decisions.length, 1);
      expect(decisions.single.threshold, 100);
    });

    test('une autre période réinitialise les alertes', () {
      final decisions = decideBudgetAlerts(
        budgets: [_budget('b1', 10000, 100)],
        monthKey: '2026-12',
        alreadyNotified: {
          budgetAlertKey('2026-11', 'b1', 80),
          budgetAlertKey('2026-11', 'b1', 100),
        },
      );
      expect(decisions.length, 2);
    });
  });

  group('evaluate', () {
    test('sans opération en attente (pending null) : aucune alerte même si 100 %', () async {
      SharedPreferences.setMockInitialValues({});
      final service = BudgetAlertsService.instance;
      final emitted = await service.evaluate([_budget('b1', 10000, 100)]);
      expect(emitted, 0);
    });

    test('interrupteur éteint : aucune alerte même après une opération', () async {
      SharedPreferences.setMockInitialValues({'budget_alerts': false});
      final service = BudgetAlertsService.instance;
      await service.markPending('w1');
      final emitted = await service.evaluate([_budget('b1', 10000, 100)]);
      expect(emitted, 0);
    });

    test('une opération : alerte émise une seule fois par seuil et par période', () async {
      SharedPreferences.setMockInitialValues({});
      final service = BudgetAlertsService.instance;
      await service.markPending('w1');
      final first = await service.evaluate([_budget('b1', 10000, 100)]);
      expect(first, 2); // 80 et 100

      // Deuxième évaluation sans nouvelle opération : rien.
      final second = await service.evaluate([_budget('b1', 10000, 100)]);
      expect(second, 0);

      // Nouvelle opération (pending reposé) : toujours rien (déjà notifiés).
      await service.markPending('w1');
      final third = await service.evaluate([_budget('b1', 10000, 100)]);
      expect(third, 0);
    });
  });
}
