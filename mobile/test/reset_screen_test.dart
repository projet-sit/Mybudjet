import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mybudget/features/reset/reset_flow.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget harness(void Function(bool? result) onClosed) {
    return ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const ResetScreen()),
              );
              onClosed(result);
            },
            child: const Text('ouvrir'),
          ),
        ),
      ),
    );
  }

  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  FilledButton buttonOf(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Réinitialiser tout'));

  testWidgets('le bouton est désactivé tant que « REINITIALISER » n’est pas exact', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(harness((_) {}));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();

    expect(buttonOf(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'REINITIAL');
    await tester.pump();
    expect(buttonOf(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'reset');
    await tester.pump();
    expect(buttonOf(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'REINITIALISER');
    await tester.pump();
    expect(buttonOf(tester).onPressed, isNotNull);
  });

  testWidgets('taper REINITIALISER puis valider renvoie true', (tester) async {
    useTallSurface(tester);
    bool? popResult;
    await tester.pumpWidget(harness((result) => popResult = result));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'REINITIALISER');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Réinitialiser tout'));
    await tester.pumpAndSettle();

    expect(popResult, isTrue);
  });

  testWidgets('aucun overflow à 360×640', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(harness((_) {}));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
