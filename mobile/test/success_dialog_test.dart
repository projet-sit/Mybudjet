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

  testWidgets('SuccessDialog : titre, message, bouton et animation affichés', (tester) async {
    await tester.pumpWidget(
      harness(
        (context) => showSuccessDialog(
          context,
          title: 'Opération enregistrée !',
          message: 'Votre opération a été enregistrée avec succès.',
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pump(); // transition
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Opération enregistrée !'), findsOneWidget);
    expect(find.text('Votre opération a été enregistrée avec succès.'), findsOneWidget);
    expect(find.text('C’est compris'), findsOneWidget);
    // Le cercle animé est présent (CustomPaint dédié).
    expect(find.byKey(const ValueKey('success-circle')), findsOneWidget);
    // Aucun overflow.
    expect(tester.takeException(), isNull);
  });

  testWidgets('SuccessDialog : se ferme automatiquement après la durée', (tester) async {
    await tester.pumpWidget(
      harness(
        (context) => showSuccessDialog(
          context,
          title: 'Erreur non affichée',
          message: 'Test.',
          duration: const Duration(milliseconds: 600),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Erreur non affichée'), findsOneWidget);

    // Après la durée + marge, la boîte est fermée (transition de fermeture incluse).
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Erreur non affichée'), findsNothing);
  });

  testWidgets('SuccessDialog : bouton d’action personnalisé (« Annuler »)', (tester) async {
    var actionCalls = 0;
    await tester.pumpWidget(
      harness(
        (context) => showSuccessDialog(
          context,
          title: 'Opération supprimée !',
          message: 'Votre opération a été supprimée.',
          actionLabel: 'Annuler',
          onAction: () => actionCalls++,
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Annuler'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    expect(actionCalls, 1);
    // Avec une action, la boîte ne se ferme pas automatiquement.
    expect(find.text('Opération supprimée !'), findsOneWidget);
  });

  testWidgets('SuccessDialog : se ferme en touchant le bouton de validation', (tester) async {
    await tester.pumpWidget(
      harness(
        (context) => showSuccessDialog(
          context,
          title: 'Compte créé !',
          message: 'Bienvenue.',
          duration: const Duration(days: 1), // ne se fermera pas seul durant le test
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('C’est compris'));
    await tester.pumpAndSettle();
    expect(find.text('Compte créé !'), findsNothing);
  });
}
