import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mybudget/features/reset/reset_flow.dart';

void main() {
  testWidgets('DownloadOrDeleteDialog : « Supprimer sans télécharger » renvoie l’action', (tester) async {
    Object? popped;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  popped = await showDialog<Object?>(
                    context: context,
                    builder: (_) => DownloadOrDeleteDialog(onDownloadPdf: () async {}),
                  );
                },
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();

    expect(find.text('Télécharger mes données en PDF'), findsOneWidget);
    expect(find.text('Supprimer sans télécharger'), findsOneWidget);
    expect(find.text('Annuler'), findsOneWidget);

    await tester.tap(find.text('Supprimer sans télécharger'));
    await tester.pumpAndSettle();

    expect(popped, isNotNull, reason: 'doit renvoyer DeleteChoice.deleteWithoutDownload');
  });

  testWidgets('DownloadOrDeleteDialog : « Annuler » ne supprime pas', (tester) async {
    Object? popped = 'sentinel';
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  popped = await showDialog<Object?>(
                    context: context,
                    builder: (_) => DownloadOrDeleteDialog(onDownloadPdf: () async {}),
                  );
                },
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    expect(popped, isNull);
  });

  testWidgets('DownloadOrDeleteDialog : le bouton PDF appelle onDownloadPdf', (tester) async {
    var called = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => DownloadOrDeleteDialog(
                    onDownloadPdf: () async => called++,
                  ),
                ),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Télécharger mes données en PDF'));
    await tester.pumpAndSettle();

    expect(called, 1);
  });

  testWidgets('FinalDeleteConfirmDialog : texte exact + confirmation', (tester) async {
    bool? result;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showDialog<bool?>(
                    context: context,
                    builder: (_) => const FinalDeleteConfirmDialog(),
                  );
                },
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Cette action est irréversible. Toutes vos opérations, catégories personnalisées et préférences seront supprimées.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Supprimer définitivement'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('FinalDeleteConfirmDialog : Annuler renvoie false', (tester) async {
    bool? result;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showDialog<bool?>(
                    context: context,
                    builder: (_) => const FinalDeleteConfirmDialog(),
                  );
                },
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('FinalDeleteConfirmDialog : pas de débordement à 360×640', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const FinalDeleteConfirmDialog(),
                ),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
