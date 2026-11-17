import 'package:dio/dio.dart';

import '../models/dashboard.dart';
import '../models/transaction.dart';
import 'api_client.dart';
import 'cache_service.dart';
import 'outbox.dart';

/// Toutes les données financières proviennent du backend — aucune donnée fictive.
class TransactionRepository {
  TransactionRepository._internal();

  static final TransactionRepository instance = TransactionRepository._internal();

  final Dio _dio = ApiClient.instance.dio;

  Future<TransactionPage> list(String walletId, {Map<String, String> query = const {}}) async {
    final response = await _dio.get('/wallets/$walletId/transactions', queryParameters: query);
    return TransactionPage.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  /// TOUTES les opérations (toutes périodes), paginées côté client au besoin.
  /// Sauvegarde aussi dans le cache local (sert à la recherche hors-ligne).
  Future<List<Transaction>> fetchAll(String walletId) async {
    final out = <Transaction>[];
    var page = 1;
    while (true) {
      final response = await _dio.get(
        '/wallets/$walletId/transactions',
        queryParameters: {
          'all': '1',
          'page': '$page',
          'limit': '100',
          'sortBy': 'date',
          'sortDir': 'desc',
        },
      );
      final data = TransactionPage.fromJson(response.data['data'] as Map<String, dynamic>);
      out.addAll(data.transactions);
      if (page >= data.pages) break;
      page++;
      if (page > 200) break; // garde-fou
    }
    // Overlay local (opérations en attente, masquées après remise à zéro).
    final merged = await Outbox.instance.applyOverlay(out);
    try {
      await CacheService.instance.saveTransactions(
        walletId,
        merged.map((t) => t.toJson()).toList(),
      );
    } catch (_) {
      // Cache facultatif : la recherche retombera sur la liste en mémoire.
    }
    return merged;
  }

  Future<({Transaction transaction, int newBalance})> create(
    String walletId,
    Transaction tx,
  ) async {
    final response = await _dio.post('/wallets/$walletId/transactions', data: tx.toRequest());
    return (
      transaction: Transaction.fromJson(response.data['data']['transaction'] as Map<String, dynamic>),
      newBalance: Transaction.asInt(response.data['data']['newBalance']),
    );
  }

  Future<({Transaction transaction, int newBalance})> update(
    String walletId,
    String txId,
    Transaction tx,
  ) async {
    final response = await _dio.patch('/wallets/$walletId/transactions/$txId', data: tx.toRequest());
    return (
      transaction: Transaction.fromJson(response.data['data']['transaction'] as Map<String, dynamic>),
      newBalance: Transaction.asInt(response.data['data']['newBalance']),
    );
  }

  Future<int> delete(String walletId, String txId) async {
    final response = await _dio.delete('/wallets/$walletId/transactions/$txId');
    return Transaction.asInt(response.data['data']['newBalance']);
  }
}

class DataRepository {
  DataRepository._internal();

  static final DataRepository instance = DataRepository._internal();

  final Dio _dio = ApiClient.instance.dio;

  Future<DashboardData> dashboard(String walletId) async {
    final response = await _dio.get('/wallets/$walletId/dashboard');
    return DashboardData.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<StatsData> stats(String walletId, {String period = 'month'}) async {
    final response = await _dio.get('/wallets/$walletId/stats', queryParameters: {'period': period});
    return StatsData.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<List<Budget>> budgets(String walletId) async {
    final response = await _dio.get('/wallets/$walletId/budgets', queryParameters: {'progress': '1'});
    return (response.data['data']['budgets'] as List)
        .map((b) => Budget.fromJson(b as Map<String, dynamic>))
        .toList();
  }

  Future<Budget> createBudget(String walletId, {required String category, required int limitAmount, String? categoryId}) async {
    final response = await _dio.post('/wallets/$walletId/budgets', data: {
      'category': category,
      'limitAmount': limitAmount,
      'categoryId': ?categoryId,
    });
    return Budget.fromJson(response.data['data']['budget'] as Map<String, dynamic>);
  }

  Future<Budget> updateBudget(String walletId, String budgetId, {required int limitAmount}) async {
    final response = await _dio.patch('/wallets/$walletId/budgets/$budgetId', data: {
      'limitAmount': limitAmount,
    });
    return Budget.fromJson(response.data['data']['budget'] as Map<String, dynamic>);
  }

  Future<void> deleteBudget(String walletId, String budgetId) async {
    await _dio.delete('/wallets/$walletId/budgets/$budgetId');
  }
}
