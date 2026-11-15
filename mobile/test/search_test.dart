import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:mybudget/core/search/transaction_search.dart';
import 'package:mybudget/models/transaction.dart';

Transaction _tx({
  required String id,
  String type = 'expense',
  int amount = 10000,
  String category = 'Alimentation',
  String? description,
  String date = '2026-11-14',
  String time = '12:32',
}) =>
    Transaction(
      id: id,
      walletId: 'w1',
      type: type,
      amount: amount,
      category: category,
      description: description,
      date: date,
      time: time,
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
  });

  group('recherche textuelle', () {
    test('trouve par note, insensible à la casse et aux accents', () {
      final list = [_tx(id: '1', description: 'Repas au marché')];
      expect(searchTransactions(list, 'REPAS'), hasLength(1));
      expect(searchTransactions(list, 'repas au marché'), hasLength(1));
      expect(searchTransactions(list, 'repas'), hasLength(1));
    });

    test('trouve par catégorie avec accents', () {
      final list = [_tx(id: '1', category: 'Santé')];
      expect(searchTransactions(list, 'sante'), hasLength(1));
      expect(searchTransactions(list, 'Santé'), hasLength(1));
      expect(searchTransactions(list, 'SANTÉ'), hasLength(1)); // casse variée
    });

    test('trouve par type : dépense / revenu / épargne', () {
      final list = [
        _tx(id: 'e', type: 'expense'),
        _tx(id: 'i', type: 'income', category: 'Salaire'),
        _tx(id: 's', type: 'savings_deposit', category: 'Épargne'),
      ];
      expect(searchTransactions(list, 'dépense').map((t) => t.id), contains('e'));
      expect(searchTransactions(list, 'depense').map((t) => t.id), contains('e'));
      expect(searchTransactions(list, 'revenu').map((t) => t.id), contains('i'));
      expect(searchTransactions(list, 'épargne').map((t) => t.id), contains('s'));
      expect(searchTransactions(list, 'epargne').map((t) => t.id), contains('s'));
    });
  });

  group('recherche par montant', () {
    final list = [
      _tx(id: 'a', amount: 10000),
      _tx(id: 'b', amount: 1000500),
      _tx(id: 'c', amount: 250),
    ];

    test('montant simple', () {
      expect(searchTransactions(list, '10000').map((t) => t.id), contains('a'));
    });

    test('montant avec espace (formaté)', () {
      expect(searchTransactions(list, '10 000').map((t) => t.id), contains('a'));
      expect(searchTransactions(list, '1 000 500').map((t) => t.id), contains('b'));
    });

    test('montant avec signe moins', () {
      expect(searchTransactions(list, '-10000').map((t) => t.id), contains('a'));
    });
  });

  group('recherche par date', () {
    final list = [
      _tx(id: 'nov14', date: '2026-11-14'),
      _tx(id: 'nov28', date: '2026-11-28'),
      _tx(id: 'dec01', date: '2026-12-01'),
    ];

    test('date courte JJ/MM', () {
      final r = searchTransactions(list, '14/11').map((t) => t.id).toList();
      expect(r, contains('nov14'));
      expect(r, isNot(contains('nov28')));
    });

    test('date complète JJ/MM/AAAA', () {
      expect(searchTransactions(list, '14/11/2026').map((t) => t.id), contains('nov14'));
    });

    test('nom du mois', () {
      final r = searchTransactions(list, 'novembre').map((t) => t.id).toList();
      expect(r, containsAll(['nov14', 'nov28']));
      expect(r, isNot(contains('dec01')));
    });

    test('mois + année', () {
      final r = searchTransactions(list, 'novembre 2026').map((t) => t.id).toList();
      expect(r, containsAll(['nov14', 'nov28']));
    });
  });

  group('combinaison avec les filtres', () {
    final list = [
      _tx(id: 'exp', type: 'expense', amount: 10000, category: 'Alimentation'),
      _tx(id: 'inc', type: 'income', amount: 10000, category: 'Salaire'),
      _tx(id: 'sav', type: 'savings_deposit', amount: 10000, category: 'Épargne'),
    ];

    test('filtre dépenses', () {
      final r = searchTransactions(list, '10000', typeFilter: 'expense');
      expect(r.map((t) => t.id), ['exp']);
    });

    test('filtre revenus', () {
      final r = searchTransactions(list, '10000', typeFilter: 'income');
      expect(r.map((t) => t.id), ['inc']);
    });

    test('filtre épargne', () {
      final r = searchTransactions(list, '10000', typeFilter: 'savings');
      expect(r.map((t) => t.id), ['sav']);
    });

    test('filtre tout', () {
      expect(searchTransactions(list, '10000', typeFilter: 'all'), hasLength(3));
    });
  });

  test('recherche sur plus de 30 opérations (tout l’historique)', () {
    final list = [
      for (var i = 0; i < 45; i++)
        _tx(
          id: 'tx$i',
          amount: 1000 * (i + 1),
          date: '2026-11-${((i % 28) + 1).toString().padLeft(2, '0')}',
          description: i == 42 ? 'UniqueMarkerZebra' : 'Repas $i',
        ),
    ];
    final r = searchTransactions(list, 'UniqueMarkerZebra');
    expect(r.map((t) => t.id), ['tx42']);
    // Montant présent uniquement dans la 40e+ opération (au-delà des 30 chargées).
    expect(searchTransactions(list, '45000').map((t) => t.id), contains('tx44'));
  });

  test('requête vide renvoie tout', () {
    final list = [_tx(id: '1'), _tx(id: '2')];
    expect(searchTransactions(list, ''), hasLength(2));
    expect(searchTransactions(list, '   '), hasLength(2));
  });
}
