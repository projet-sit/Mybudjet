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

  testWidgets('SuccessDialog : coche verte, message, aucun bouton', (tester) async {
    await tester.pumpWidget(
      harness(
        (context) => showSuccessDialog(
          context,
          message: 'Dépense de 2 000 FCFA ajoutée.',
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Dépense de 2 000 FCFA ajoutée.'), findsOneWidget);
    // Aucun bouton de confirmation dans la boîte de succès.
    expect(find.widgetWithText(FilledButton, 'C’est compris'), findsNothing);
    expect(find.byKey(const ValueKey('success-circle')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SuccessDialog : se ferme tout seul après la durée', (tester) async {
    await tester.pumpWidget(
      harness(
        (context) => showSuccessDialog(
          context,
          message: 'Compte créé.',
          duration: const Duration(milliseconds: 600),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Compte créé.'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Compte créé.'), findsNothing);
  });

  testWidgets('SuccessDialog : se ferme en touchant en dehors', (tester) async {
    await tester.pumpWidget(
      harness(
        (context) => showSuccessDialog(
          context,
          message: 'Opération enregistrée.',
          duration: const Duration(days: 1), // ne se ferme pas seul pendant le test
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Opération enregistrée.'), findsOneWidget);

    // Touche à l'extérieur du dialogue (le fond).
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Opération enregistrée.'), findsNothing);
  });
}
