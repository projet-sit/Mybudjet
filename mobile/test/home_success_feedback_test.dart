import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mybudget/core/theme/app_theme.dart';
import 'package:mybudget/core/utils/money.dart';
import 'package:mybudget/features/home/home_screen.dart';
import 'package:mybudget/features/success_feedback/models/success_event.dart';
import 'package:mybudget/features/success_feedback/providers/success_feedback_provider.dart';
import 'package:mybudget/features/success_feedback/widgets/success_feedback_overlay.dart';
import 'package:mybudget/models/dashboard.dart';
import 'package:mybudget/models/wallet.dart';
import 'package:mybudget/providers/sync_provider.dart';
import 'package:mybudget/providers/transaction_provider.dart';
import 'package:mybudget/providers/wallet_provider.dart';
import 'package:mybudget/models/sync_info.dart';

Wallet wallet({int balance = 150000, int savings = 20000}) => Wallet(
      id: 'wallet-1',
      userId: 'user-1',
      name: 'Mon budget',
      initialAmount: 150000,
      startDate: '2026-11-01',
      currency: 'XOF',
      balance: balance,
      savingsAmount: savings,
    );

DashboardData dashboard({int expenses = 30000, int incomes = 0}) => DashboardData(
      walletId: 'wallet-1',
      walletName: 'Mon budget',
      currency: 'XOF',
      initialAmount: 150000,
      balance: 120000,
      totalExpenses: expenses,
      totalIncomes: incomes,
      transactionsCount: expenses + incomes == 0 ? 0 : 1,
      percentUsed: ((expenses / 150000) * 100).round(),
      weeklySeries: const [DailyPoint(date: '2026-11-18', expenses: 30000)],
      latestTransactions: const [],
    );

class FakeWalletController extends WalletController {
  FakeWalletController(this._value);

  Wallet _value;

  @override
  Future<Wallet?> build() async => _value;

  void setCurrent(Wallet value) {
    _value = value;
    setWallet(value);
  }

  @override
  Future<void> refresh() async {
    // Rafraîchissement simulé avec données déjà présentes : rien ne doit
    // se remplacer par un placeholder.
    state = AsyncData(_value);
  }
}

class FakeDashboardController extends DashboardController {
  FakeDashboardController(this._value);

  final DashboardData _value;

  @override
  Future<DashboardData?> build() async => _value;

  @override
  Future<void> refresh() async {
    state = AsyncData(_value);
  }
}

class FakeSyncController extends SyncController {
  FakeSyncController(this._value);

  final SyncInfo _value;

  @override
  SyncInfo build() => _value;

  @override
  Future<void> refresh() async => state = _value;
}

ProviderContainer makeContainer({
  Wallet? walletValue,
  DashboardData? dashboardValue,
  SyncInfo sync = const SyncInfo(state: SyncState.synced),
}) {
  final container = ProviderContainer(
    overrides: [
      walletControllerProvider.overrideWith(() => FakeWalletController(walletValue ?? wallet())),
      dashboardControllerProvider.overrideWith(() => FakeDashboardController(dashboardValue ?? dashboard())),
      syncInfoProvider.overrideWith(() => FakeSyncController(sync)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget harness(ProviderContainer container, {ThemeData? theme}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Stack(
        children: const [
          Scaffold(
            body: HomeScreen(),
          ),
          SuccessFeedbackOverlay(),
        ],
      ),
    ),
  );
}

Future<double> heroHeight(WidgetTester tester) async =>
    (tester.renderObject(find.byKey(const ValueKey('hero-card'))) as RenderBox).size.height;

Future<void> expectHomeVisibleAndStable(
  WidgetTester tester,
  ProviderContainer container,
  double beforeHeight,
) async {
  container.read(successFeedbackProvider.notifier).emit(
        const SuccessEvent(type: SuccessEventType.expenseAdded, detail: '5 000 FCFA'),
      );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));

  expect(find.text('Reste'), findsOneWidget);
  expect(find.text('Revenus'), findsOneWidget);
  expect(find.text('Dépenses'), findsOneWidget);
  expect(find.text('Budget du mois'), findsOneWidget);
  expect(find.byKey(const ValueKey('hero-card')), findsOneWidget);
  final indicators = tester.widgetList<CircularProgressIndicator>(
    find.byType(CircularProgressIndicator),
  );
  expect(
    indicators.every((indicator) => indicator.value != null),
    isTrue,
    reason: 'seul l’anneau du budget est autorisé, aucun chargement',
  );
  expect(find.byType(BackdropFilter), findsNothing);
  expect(find.byKey(const ValueKey('success-card')), findsOneWidget);

  expect(await heroHeight(tester), beforeHeight);
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  testWidgets('Accueil : l’animation garde la carte stable et tout visible', (tester) async {
    final container = makeContainer();
    await tester.pumpWidget(harness(container));
    await tester.pumpAndSettle();

    final before = await heroHeight(tester);
    await expectHomeVisibleAndStable(tester, container, before);
  });

  testWidgets('Accueil hors ligne : même comportement, rien de grisant', (tester) async {
    final container = makeContainer(
      sync: const SyncInfo(state: SyncState.offline, pendingCount: 1),
    );
    await tester.pumpWidget(harness(container));
    await tester.pumpAndSettle();

    final before = await heroHeight(tester);
    await expectHomeVisibleAndStable(tester, container, before);
    expect(find.textContaining('Hors ligne'), findsOneWidget);
  });

  testWidgets('Accueil : un rafraîchissement avec valeurs existantes garde l’interface', (tester) async {
    final container = makeContainer();
    await tester.pumpWidget(harness(container));
    await tester.pumpAndSettle();

    await container.read(walletControllerProvider.notifier).refresh();
    await tester.pump();

    expect(find.text('Reste'), findsOneWidget);
    expect(find.text('Mon budget'), findsOneWidget);
    final indicators = tester.widgetList<CircularProgressIndicator>(
    find.byType(CircularProgressIndicator),
  );
  expect(
    indicators.every((indicator) => indicator.value != null),
    isTrue,
    reason: 'seul l’anneau du budget est autorisé, aucun chargement',
  );
  });

  testWidgets('Accueil : le compteur Reste évolue sans disparaître', (tester) async {
    final container = makeContainer();
    await tester.pumpWidget(harness(container));
    await tester.pumpAndSettle();

    final notifier = container.read(walletControllerProvider.notifier) as FakeWalletController;
    notifier.setCurrent(wallet(balance: 150000, savings: 100000));
    await tester.pump();
    expect(find.text('Reste'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text(formatMoneyCurrent(50000)), findsOneWidget);
    expect(find.text('Reste'), findsOneWidget);
  });

  testWidgets('Accueil : aucun overflow à 360×640 en thème clair et sombre', (tester) async {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = makeContainer();
      await tester.pumpWidget(harness(container, theme: theme));
      container.read(successFeedbackProvider.notifier).emit(
            const SuccessEvent(type: SuccessEventType.expenseAdded, detail: '5 000 FCFA'),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(const ValueKey('hero-card')), findsOneWidget);
      expect(find.text('Budget du mois'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 800));
    }
  });
}
