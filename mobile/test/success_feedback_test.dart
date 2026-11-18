import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mybudget/features/success_feedback/models/success_event.dart';
import 'package:mybudget/features/success_feedback/providers/success_feedback_provider.dart';
import 'package:mybudget/features/success_feedback/widgets/success_feedback_overlay.dart';

SuccessEvent eventFor(SuccessEventType type) => switch (type) {
      SuccessEventType.expenseAdded => const SuccessEvent(type: SuccessEventType.expenseAdded, detail: '5 000 FCFA'),
      SuccessEventType.incomeAdded => const SuccessEvent(type: SuccessEventType.incomeAdded, detail: '150 000 FCFA'),
      SuccessEventType.walletCreated => const SuccessEvent(type: SuccessEventType.walletCreated, detail: 'Mon budget'),
      SuccessEventType.savingsDeposited => const SuccessEvent(type: SuccessEventType.savingsDeposited, detail: '20 000 FCFA'),
      SuccessEventType.savingsWithdrawn => const SuccessEvent(type: SuccessEventType.savingsWithdrawn, detail: '10 000 FCFA'),
      SuccessEventType.savingsRecovered => const SuccessEvent(type: SuccessEventType.savingsRecovered, detail: '15 000 FCFA'),
    };

String expectedTitle(SuccessEventType type) => switch (type) {
      SuccessEventType.expenseAdded => 'Dépense enregistrée',
      SuccessEventType.incomeAdded => 'Revenu enregistré',
      SuccessEventType.walletCreated => 'Portefeuille créé',
      SuccessEventType.savingsDeposited => 'Versement enregistré',
      SuccessEventType.savingsWithdrawn => 'Retrait enregistré',
      SuccessEventType.savingsRecovered => 'Épargne récupérée',
    };

Widget harness(ProviderContainer container, {bool reduceMotion = false}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      builder: (context, child) {
        if (!reduceMotion) return child!;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        );
      },
      home: Stack(
        children: const [
          Scaffold(body: Center(child: Text('body'))),
          SuccessFeedbackOverlay(),
        ],
      ),
    ),
  );
}

Future<ProviderContainer> boot(WidgetTester tester, {bool reduceMotion = false}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(harness(container, reduceMotion: reduceMotion));
  return container;
}

Future<void> emitAndSettle(WidgetTester tester, ProviderContainer container, SuccessEvent event) async {
  container.read(successFeedbackProvider.notifier).emit(event);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1300));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('chaque événement autorisé affiche le bon titre et sous-titre', (tester) async {
    for (final type in SuccessEventType.values) {
      final container = await boot(tester);
      final event = eventFor(type);

      container.read(successFeedbackProvider.notifier).emit(event);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(expectedTitle(type)), findsOneWidget, reason: 'titre pour $type');
      expect(find.text(event.detail), findsOneWidget, reason: 'sous-titre pour $type');
      expect(find.byKey(const ValueKey('success-card')), findsOneWidget);

      // Nettoyage : laisser la sortie se jouer et l'enfant sortant être retiré.
      container.read(successFeedbackProvider.notifier).clear();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('aucune animation tant qu’aucun cas d’usage n’a émis (démarrage / synchro)', (tester) async {
    await boot(tester);
    expect(find.byKey(const ValueKey('success-card')), findsNothing);
    expect(find.text('Dépense enregistrée'), findsNothing);
  });

  testWidgets('un tap n’importe où ferme l’animation immédiatement', (tester) async {
    final container = await boot(tester);
    await emitAndSettle(tester, container, eventFor(SuccessEventType.expenseAdded));

    container.read(successFeedbackProvider.notifier).emit(eventFor(SuccessEventType.expenseAdded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('success-card')), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    expect(container.read(successFeedbackProvider), isNull);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('success-card')), findsNothing);
    await tester.pump(const Duration(milliseconds: 1300));
  });

  testWidgets('deux enregistrements rapides : seule la dernière animation reste', (tester) async {
    final container = await boot(tester);

    container.read(successFeedbackProvider.notifier).emit(eventFor(SuccessEventType.expenseAdded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    container.read(successFeedbackProvider.notifier).emit(eventFor(SuccessEventType.savingsDeposited));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Dépense enregistrée'), findsNothing);
    expect(find.text('Versement enregistré'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1000));
  });

  testWidgets('mode réduire les animations : fondu simple, coche déjà dessinée', (tester) async {
    final container = await boot(tester, reduceMotion: true);
    container.read(successFeedbackProvider.notifier).emit(eventFor(SuccessEventType.expenseAdded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const ValueKey('success-card')), findsOneWidget);
    expect(find.text('Dépense enregistrée'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('success-card')), findsNothing);
  });

  testWidgets('l’annonce d’accessibilité (liveRegion) contient le titre et le montant', (tester) async {
    final container = await boot(tester);
    container.read(successFeedbackProvider.notifier).emit(eventFor(SuccessEventType.expenseAdded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final liveRegions = tester.widgetList<Semantics>(find.byType(Semantics)).where(
          (s) => s.properties.liveRegion == true,
        );
    expect(liveRegions, isNotEmpty);
    expect(
      liveRegions.any((s) => (s.properties.label ?? '').contains('Dépense enregistrée')),
      isTrue,
    );
    expect(
      liveRegions.any((s) => (s.properties.label ?? '').contains('5 000 FCFA')),
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 1300));
  });

  testWidgets('aucun overflow à 360×640', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = await boot(tester);
    container.read(successFeedbackProvider.notifier).emit(eventFor(SuccessEventType.savingsRecovered));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byKey(const ValueKey('success-card')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets('expiration automatique après ~1,2 s', (tester) async {
    final container = await boot(tester);
    container.read(successFeedbackProvider.notifier).emit(eventFor(SuccessEventType.incomeAdded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1250));

    expect(container.read(successFeedbackProvider), isNull);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('success-card')), findsNothing);
  });

  test('SuccessFeedbackController : emit puis clear immédiat', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(successFeedbackProvider), isNull);
    container.read(successFeedbackProvider.notifier).emit(eventFor(SuccessEventType.walletCreated));
    expect(container.read(successFeedbackProvider)?.type, SuccessEventType.walletCreated);
    container.read(successFeedbackProvider.notifier).clear();
    expect(container.read(successFeedbackProvider), isNull);
  });
}
