import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dashboard.dart';
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

  /// À utiliser lors de la déconnexion / suppression de compte.
  Future<void> clearWallet() async {
    final prefs = await _prefs;
    await prefs.remove('cache_wallet');
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

/// Phase 10 — état « hors ligne » observé par les écrans (bandeau).
class OfflineNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) {
    if (state != value) state = value;
  }
}

final offlineProvider = NotifierProvider<OfflineNotifier, bool>(OfflineNotifier.new);
