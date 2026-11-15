import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dashboard.dart';
import '../models/transaction.dart';
import '../models/wallet.dart';
import 'api_client.dart';

/// Cache local (SharedPreferences) : dernières données RÉELLES reçues du backend.
/// Aucune donnée fictive — uniquement la dernière réponse valide.
class CacheService {
  CacheService._internal();

  static final CacheService instance = CacheService._internal();

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<void> saveDashboard(String walletId, DashboardData dashboard) async {
    final prefs = await _prefs;
    await prefs.setString(
      'cache_dashboard_$walletId',
      jsonEncode({
        'walletId': dashboard.walletId,
        'walletName': dashboard.walletName,
        'currency': dashboard.currency,
        'balance': dashboard.balance,
        'initialAmount': dashboard.initialAmount,
        'totalExpenses': dashboard.totalExpenses,
        'totalIncomes': dashboard.totalIncomes,
        'transactionsCount': dashboard.transactionsCount,
        'percentUsed': dashboard.percentUsed,
        'weeklySeries': [
          for (final p in dashboard.weeklySeries) {'date': p.date, 'expenses': p.expenses},
        ],
        'latestTransactions': [
          for (final t in dashboard.latestTransactions) t.toJson(),
        ],
        'savedAt': DateTime.now().toIso8601String(),
      }),
    );
  }

  Future<Map<String, dynamic>?> loadDashboard(String walletId) async {
    final prefs = await _prefs;
    final raw = prefs.getString('cache_dashboard_$walletId');
    if (raw == null) return null;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    // Compatibilité avec les anciens caches (champs récents absents).
    decoded['weeklySeries'] ??= const [];
    decoded['latestTransactions'] ??= const [];
    decoded['transactionsCount'] ??= 0;
    return decoded;
  }

  /// Sauvegarde le portefeuille (dernière donnée réelle connue).
  Future<void> saveWallet(Wallet wallet) async {
    final prefs = await _prefs;
    await prefs.setString('cache_wallet', jsonEncode(wallet.toJson()));
  }

  /// Charge le portefeuille depuis le cache (null si absent/illisible).
  Future<Wallet?> loadWallet() async {
    try {
      final prefs = await _prefs;
      final raw = prefs.getString('cache_wallet');
      if (raw == null) return null;
      return Wallet.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Cache local des budgets (dernière réponse réelle du serveur).
  Future<void> saveBudgets(String walletId, List<Map<String, dynamic>> budgets) async {
    final prefs = await _prefs;
    await prefs.setString('cache_budgets_$walletId', jsonEncode(budgets));
  }

  Future<List<Budget>> loadBudgets(String walletId) async {
    final prefs = await _prefs;
    final raw = prefs.getString('cache_budgets_$walletId');
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Budget.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Cache local complet des opérations (dernière liste connue du serveur).
  /// Sert à la recherche hors-ligne et au démarrage instantané.
  Future<void> saveTransactions(String walletId, List<Map<String, dynamic>> txs) async {
    final prefs = await _prefs;
    await prefs.setString('cache_txs_$walletId', jsonEncode(txs));
  }

  Future<List<Transaction>> loadTransactions(String walletId) async {
    final prefs = await _prefs;
    final raw = prefs.getString('cache_txs_$walletId');
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Transaction.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> clearWallet() async {
    final prefs = await _prefs;
    await prefs.remove('cache_wallet');
    final keys = prefs.getKeys().where((k) => k.startsWith('cache_dashboard_') || k.startsWith('cache_txs_') || k.startsWith('cache_budgets_')).toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
  }

  /// Phase 10 — export CSV : téléchargé puis partagé via la feuille de partage.
  Future<String> exportCsv(String walletId) async {
    final response = await ApiClient.instance.dio.get<String>(
      '/wallets/$walletId/export',
      options: Options(responseType: ResponseType.plain),
    );
    final content = response.data ?? '';
    final dir = await getApplicationDocumentsDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path = '${dir.path}/mybudget-$walletId-$stamp.csv';
    await File(path).writeAsString(content);
    return path;
  }

  Future<void> shareFile(String path) async {
    await Share.shareXFiles([XFile(path)]);
  }
}
