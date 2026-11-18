import 'package:flutter/foundation.dart';

import '../../models/transaction.dart';

/// Recherche d'opérations sur TOUT l'historique local :
/// index de texte normalisé (minuscules, sans accents), jamais limité
/// aux 30 dernières lignes affichées.
///
/// Critères couverts : note, catégorie, portefeuille, montant
/// (« 10000 », « 10 000 », « -10000 »), date (« 14/11 », « novembre »,
/// « 14/11/2026 »), type (« dépense », « revenu », « épargne »).
///
/// Le chemin de recherche ne dépend PAS d'intl/DateFormat : tout est formaté
/// manuellement (noms de mois en dur, groupement des milliers fait main), ce
/// qui permet de l'exécuter dans un isolate (compute) sans initialiser de
/// données de locale — c'était la cause du chargement infini sur la recherche.

const Map<String, String> _diacritics = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'î': 'i', 'ï': 'i', 'í': 'i',
  'ô': 'o', 'ö': 'o', 'ó': 'o', 'õ': 'o',
  'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
  'ç': 'c', 'ñ': 'n', 'ÿ': 'y',
  'œ': 'oe', 'æ': 'ae',
};

String normalizeSearchText(String input) {
  var s = input.toLowerCase();
  _diacritics.forEach((k, v) => s = s.replaceAll(k, v));
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

/// Groupement manuel des milliers (espace normal), ex : 10000 → « 10 000 ».
/// Aucune dépendance à NumberFormat : utilisable dans un isolate sans locale.
String _groupedAmount(int amount) {
  final negative = amount < 0;
  final digits = amount.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return negative ? '-$buffer' : buffer.toString();
}

/// « 14/11/2026 » en manuel (DateFormat exigerait la locale initialisée).
String _formatDayManual(int year, int month, int day) =>
    '${day.toString().padLeft(2, '0')}/${month.toString().padLeft(2, '0')}/$year';

const _monthLongFr = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

const _monthShortFr = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
];

/// Type recherchable en français.
String typeSearchLabel(String type) {
  switch (type) {
    case 'expense':
      return 'depense';
    case 'income':
      return 'revenu';
    case 'savings_deposit':
    case 'savings_withdrawal':
      return 'epargne';
    default:
      return '';
  }
}

/// Vrai si l'opération [tx] correspond à [rawQuery].
bool transactionMatches(Transaction tx, String rawQuery, {String? walletName}) {
  final q = normalizeSearchText(rawQuery);
  if (q.isEmpty) return true;

  // Variantes de date : « 14/11 », « novembre », « novembre 2026 », « nov. »
  final d = DateTime.tryParse(tx.date);

  final haystack = <String>[
    normalizeSearchText(tx.category),
    if (tx.description != null) normalizeSearchText(tx.description!),
    if (tx.paymentMethod != null) normalizeSearchText(tx.paymentMethod!),
    if (walletName != null && walletName.isNotEmpty) normalizeSearchText(walletName),
    typeSearchLabel(tx.type),
    '${tx.amount}',
    normalizeSearchText(_groupedAmount(tx.amount)),
    if (d != null) _formatDayManual(d.year, d.month, d.day),
  ];
  if (d != null) {
    haystack.add('${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}');
    final monthLong = _monthLongFr[d.month - 1];
    haystack.add(normalizeSearchText(monthLong));
    haystack.add(normalizeSearchText('$monthLong ${d.year}'));
    haystack.add(normalizeSearchText(_monthShortFr[d.month - 1]));
  }

  final joined = haystack.join(' ');
  if (joined.contains(q)) return true;

  // Montant : « 10000 », « 10 000 », « 10.000 » ou « -10000 » (signe ignoré).
  final qDigits = _digitsOnly(q);
  if (qDigits.length >= 2) {
    final amountStr = tx.amount.toString();
    if (amountStr.contains(qDigits)) return true;
    if (_digitsOnly(_groupedAmount(tx.amount)).contains(qDigits)) return true;
  }
  return false;
}

/// Filtre complet : recherche + filtre type (Tout/Dépenses/Revenus/Épargne).
List<Transaction> searchTransactions(
  List<Transaction> source,
  String query, {
  String typeFilter = 'all',
  String? walletName,
}) {
  var results = source.where((t) => transactionMatches(t, query, walletName: walletName));
  switch (typeFilter) {
    case 'expense':
      results = results.where((t) => t.isExpense);
      break;
    case 'income':
      results = results.where((t) => t.isIncome);
      break;
    case 'savings':
      results = results.where((t) => t.isSavings);
      break;
    default:
      break;
  }
  return results.toList();
}

// ---------- Exécution hors thread UI (compute) ----------

/// Fonction top-level pour compute() : reçoit des maps JSON, renvoie des ids.
List<String> searchTransactionMaps(Map<String, dynamic> args) {
  final rawTxs = (args['txs'] as List).cast<Map<String, dynamic>>();
  final query = (args['query'] ?? '') as String;
  final typeFilter = (args['typeFilter'] ?? 'all') as String;
  final walletName = args['walletName'] as String?;
  final txs = rawTxs.map(Transaction.fromJson).toList();
  final matches = searchTransactions(txs, query, typeFilter: typeFilter, walletName: walletName);
  return matches.map((t) => t.id).toList();
}

/// Recherche asynchrone sur tout l'historique (hors thread UI).
Future<List<Transaction>> searchFullLedger(
  List<Transaction> all,
  String query, {
  String typeFilter = 'all',
  String? walletName,
}) async {
  final byId = {for (final t in all) t.id: t};
  final ids = await compute(searchTransactionMaps, {
    'txs': all.map((t) => t.toJson()).toList(),
    'query': query,
    'typeFilter': typeFilter,
    'walletName': walletName,
  });
  return [for (final id in ids) if (byId[id] != null) byId[id]!];
}
