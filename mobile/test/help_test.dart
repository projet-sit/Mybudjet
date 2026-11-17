import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mybudget/features/help/help_screen.dart';

void main() {
  testWidgets('Aide et FAQ affiche la liste des questions', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HelpScreen()));
    expect(find.text('Aide et FAQ'), findsOneWidget);
    expect(find.text('Que veut dire « Reste » ?'), findsOneWidget);
  });

  testWidgets('Une question s’ouvre puis se ferme au toucher', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HelpScreen()));

    // La réponse est masquée par défaut.
    expect(find.textContaining('ton solde moins ton épargne'), findsNothing);

    // Ouverture.
    await tester.tap(find.text('Que veut dire « Reste » ?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ton solde moins ton épargne'), findsOneWidget);

    // Fermeture.
    await tester.tap(find.text('Que veut dire « Reste » ?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ton solde moins ton épargne'), findsNothing);
  });

  testWidgets('aucun overflow à 360×640 (portrait) : l’écran tient', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: HelpScreen()));
    // Défile jusqu'au bas de la liste : tout le contenu se construit sans erreur.
    await tester.fling(find.byType(ListView), const Offset(0, -500), 1000);
    await tester.pumpAndSettle();
    await tester.fling(find.byType(ListView), const Offset(0, -500), 1000);
    await tester.pumpAndSettle();
    await tester.fling(find.byType(ListView), const Offset(0, 500), 1000);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('toutes les questions s’ouvrent et se ferment à 360×2400', (tester) async {
    tester.view.physicalSize = const Size(360, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: HelpScreen()));
    for (final question in faqItems.map((item) => item.question)) {
      await tester.tap(find.text(question));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(question));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });
}
