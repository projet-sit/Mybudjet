import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:mybudget/core/utils/date_format.dart';
import 'package:mybudget/core/utils/money.dart';
import 'package:mybudget/models/transaction.dart';
import 'package:mybudget/widgets/transaction_tile.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
  });

  testWidgets('TransactionTile affiche une dépense en rouge avec le signe −',
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

    // Titre = catégorie (pas de note) et sous-titre SANS doublon « Salaire · Salaire ».
    expect(find.text('Salaire'), findsOneWidget);
    expect(find.textContaining('Salaire · Salaire'), findsNothing);
    expect(find.text('+20 000'), findsOneWidget);
  });

  testWidgets('TransactionTile affiche une opération d’épargne en neutre (pas de rouge)',
      (WidgetTester tester) async {
    final tx = Transaction(
      id: 't3',
      walletId: 'w1',
      type: 'savings_deposit',
      amount: 10000,
      category: 'Épargne',
      description: null,
      date: '2026-01-04',
      time: '09:00',
      paymentMethod: null,
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TransactionTile(transaction: tx))),
    );

    expect(find.text('Épargne'), findsWidgets);
    expect(find.text('10 000'), findsOneWidget);
    // Pas de signe +/- : l'épargne n'est ni une dépense ni un revenu.
    expect(find.text('−10 000'), findsNothing);
    expect(find.text('+10 000'), findsNothing);
  });

  test('formatMoney groupe les milliers (XOF)', () {
    expect(formatMoney(150000), '150 000 FCFA');
    expect(formatMoney(150000, withCurrency: false, currency: 'XOF'), '150 000');
    expect(formatMoney(0), '0 FCFA');
  });

  test('formatMoney : EUR et USD à 2 décimales', () {
    expect(formatMoney(655957, currency: 'EUR'), '1 000,00 €');
    expect(formatMoney(25000, withCurrency: false, currency: 'EUR'), '38,11');
    expect(formatMoney(1000000, currency: 'USD'), '1,750.00 \$');
    expect(formatMoney(1000000, withCurrency: false, currency: 'USD'), '1,750.00');
  });

  test('formatMoney : EUR/USD convertissent depuis XOF (référence)', () {
    // 25 000 XOF = 25 000 / 655,957 EUR
    expect(formatMoney(25000, currency: 'EUR'), '38,11 €');
    // XOF : entiers uniquement, pas de conversion
    expect(formatMoney(25000, currency: 'XOF'), '25 000 FCFA');
  });

  test('formatDateTimeFr produit JJ/MM/AAAA · HH:mm en heure locale', () {
    expect(formatDateTimeFr('2026-11-14', '12:32'), '14/11/2026 · 12:32');
    expect(formatDateFr('2026-01-03'), '03/01/2026');
  });

  test('les dates seules ne sont jamais décalées par le fuseau', () {
    final d = DateFormatUtil.parseLocal('2026-11-14');
    expect(d, isNotNull);
    expect(d!.year, 2026);
    expect(d.month, 11);
    expect(d.day, 14);
    // ISO complète (UTC) → convertie en heure locale, jamais affichée brute.
    final z = DateFormatUtil.parseLocal('2026-11-14T00:00:00.000Z')!;
    expect(z.isUtc, isFalse);
  });
}
