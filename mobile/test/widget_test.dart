import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mybudget/core/utils/money.dart';
import 'package:mybudget/models/transaction.dart';
import 'package:mybudget/widgets/transaction_tile.dart';

void main() {
  testWidgets('TransactionTile affiche une dépense en rouge avec le signe -',
      (WidgetTester tester) async {
    final tx = Transaction(
      id: 't1',
      walletId: 'w1',
      type: 'expense',
      amount: 5000,
      category: 'Alimentation',
      description: 'Restaurant',
      date: '2026-01-03',
      time: '12:30',
      paymentMethod: 'Espèces',
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TransactionTile(transaction: tx))),
    );

    expect(find.text('Restaurant'), findsOneWidget);
    expect(find.textContaining('Alimentation'), findsOneWidget);
    expect(find.text('−5 000'), findsOneWidget);
  });

  testWidgets('TransactionTile affiche un revenu en vert avec le signe +',
      (WidgetTester tester) async {
    final tx = Transaction(
      id: 't2',
      walletId: 'w1',
      type: 'income',
      amount: 20000,
      category: 'Salaire',
      description: null,
      date: '2026-01-02',
      time: '08:00',
      paymentMethod: null,
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TransactionTile(transaction: tx))),
    );

    expect(find.text('Salaire'), findsOneWidget);
    expect(find.textContaining('Salaire ·'), findsOneWidget);
    expect(find.text('+20 000'), findsOneWidget);
  });

  test('formatXof groupe les milliers', () {
    expect(formatXof(150000), '150 000 FCFA');
    expect(formatXof(150000, withCurrency: false), '150 000');
    expect(formatXof(0), '0 FCFA');
  });
}
