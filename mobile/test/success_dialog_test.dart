import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mybudget/core/widgets/app_feedback.dart';

void main() {
  Widget harness(void Function(BuildContext context) onOpen) {
    return ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => onOpen(context),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    );
  }

  testWidgets('SuccessDialog : cercle + coche animés + « Effectué », aucun bouton', (tester) async {
    await tester.pumpWidget(
      harness((context) => showSuccessDialog(context)),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Effectué'), findsOneWidget);
    // Aucun bouton de confirmation dans la boîte de succès.
    expect(find.widgetWithText(FilledButton, 'C’est compris'), findsNothing);
    expect(find.byKey(const ValueKey('success-circle')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SuccessDialog : se ferme tout seul après la durée', (tester) async {
    await tester.pumpWidget(
      harness((context) => showSuccessDialog(context, duration: const Duration(milliseconds: 600))),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Effectué'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Effectué'), findsNothing);
  });

  testWidgets('SuccessDialog : se ferme en touchant en dehors', (tester) async {
    await tester.pumpWidget(
      harness((context) => showSuccessDialog(context, duration: const Duration(days: 1))),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Effectué'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Effectué'), findsNothing);
  });
}
