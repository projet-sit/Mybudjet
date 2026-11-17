import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/dashboard.dart';
import '../models/transaction.dart';
import '../services/cache_service.dart';
import '../services/data_repository.dart';
import '../services/outbox.dart';
import '../services/budget_alerts_service.dart';
import '../core/search/transaction_search.dart';
import '../providers/sync_provider.dart';
import 'wallet_provider.dart';

/// État de la liste paginée + filtres (Phase 7).
class TransactionsState {
  const TransactionsState({
    this.items = const [],
    this.total = 0,
    this.totalExpenses = 0,
    this.totalIncomes = 0,
    this.page = 1,
    this.pages = 1,
    this.typeFilter = 'all',
    this.categoryFilter,
    this.search,
    this.isLoadingMore = false,
  });

  final List<Transaction> items;
  final int total;
  final int totalExpenses;
  final int totalIncomes;
  final int page;
  final int pages;
  final String typeFilter; // all | expense | income | savings
  final String? categoryFilter;
  final String? search;
  final bool isLoadingMore;

  bool get hasMore => page < pages;

  /// Nombre d'opérations réellement affichable après overlay (information pour l'UI).

  TransactionsState copyWith({
    List<Transaction>? items,
    int? total,
    int? totalExpenses,
    int? totalIncomes,
    int? page,
    int? pages,
    String? typeFilter,
    String? categoryFilter,
    bool clearCategory = false,
    String? search,
    bool clearSearch = false,
    bool? isLoadingMore,
  }) {
    return TransactionsState(
      items: items ?? this.items,
      total: total ?? this.total,
      totalExpenses: totalExpenses ?? this.totalExpenses,
      totalIncomes: totalIncomes ?? this.totalIncomes,
      page: page ?? this.page,
      pages: pages ?? this.pages,
      typeFilter: typeFilter ?? this.typeFilter,
      categoryFilter: clearCategory ? null : (categoryFilter ?? this.categoryFilter),
      search: clearSearch ? null : (search ?? this.search),
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

class TransactionsController extends AsyncNotifier<TransactionsState> {
  Map<String, String> _query(String walletId, TransactionsState s, {required bool firstPage}) {
    final q = <String, String>{'page': firstPage ? '1' : '${s.page}', 'limit': '30', 'sortBy': 'date', 'sortDir': 'desc'};
    if (s.typeFilter != 'all') q['type'] = s.typeFilter;
    if (s.categoryFilter != null) q['category'] = s.categoryFilter!;
    if (s.search != null && s.search!.trim().isNotEmpty) q['search'] = s.search!.trim();
    return q;
  }

  @override
  Future<TransactionsState> build() async {
    final wallet = await ref.watch(walletControllerProvider.future);
    if (wallet == null) {
      return const TransactionsState();
    }
    // Rejoue d'abord ce qui était en attente (backend à nouveau disponible).
    unawaited(_flushOutboxQuietly());
    final online = await _isOnline();
    if (!online) {
      // Pas de réseau : repli direct sur le cache, sans spinner ni requête.
      return _fromCacheAndOverlay(wallet.id);
    }
    try {
      final page = await TransactionRepository.instance.list(
        wallet.id,
        query: _query(wallet.id, const TransactionsState(), firstPage: true),
      );
      unawaited(_refreshFullCache(wallet.id));
      final merged = await Outbox.instance.applyOverlay(page.transactions);
      return TransactionsState(
        items: merged,
        total: merged.length,
        totalExpenses: page.totalExpenses,
        totalIncomes: page.totalIncomes,
        page: page.page,
        pages: page.pages,
        typeFilter: 'all',
      );
    } catch (e) {
      // Backend injoignable : repli sur le cache local complet (jamais bloquant).
      try {
        return await _fromCacheAndOverlay(wallet.id);
      } catch (_) {
        rethrow;
      }
    }
  }

  Future<TransactionsState> _fromCacheAndOverlay(String walletId) async {
    final cached = await CacheService.instance.loadTransactions(walletId);
    final merged = await Outbox.instance.applyOverlay(cached);
    if (merged.isEmpty && cached.isEmpty) {
      throw StateError('Synchronisation indisponible et aucune donnée enregistrée');
    }
    return TransactionsState(
      items: merged,
      total: merged.length,
      totalExpenses: 0,
      totalIncomes: 0,
      page: 1,
      pages: 1,
      typeFilter: 'all',
    );
  }

  Future<bool> _isOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      // En cas de doute, on tente le réseau : un timeout backend n'est pas « hors ligne ».
      return true;
    }
  }

  Future<void> _flushOutboxQuietly() async {
    try {
      final result = await Outbox.instance.flush();
      if (result.replayed > 0 || result.hasFailures) {
        await ref.read(syncInfoProvider.notifier).refresh();
      }
      if (result.hasFailures) {
        ref.read(syncNoticeProvider.notifier).setFailed(
              result.failures.length,
              result.failures.first.message,
            );
      } else {
        ref.read(syncNoticeProvider.notifier).clear();
      }
    } catch (_) {
      // Laisse la place à un autre passage (réseau, prochain resume…).
    }
  }

  Future<void> _refreshFullCache(String walletId) async {
    try {
      // fetchAll sauvegarde déjà le cache complet (fusionné avec l'overlay).
      await TransactionRepository.instance.fetchAll(walletId);
      await Outbox.instance.clearOverlayIfAllSynced();
    } catch (_) {
      // Cache complet non rafraîchi : on garde le dernier connu.
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
  }

  Future<void> setTypeFilter(String type) async {
    final wallet = ref.watch(walletControllerProvider).value;
    final previous = state.value;
    if (wallet == null || previous == null) return;
    try {
      state = const AsyncLoading();
      final base = previous.copyWith(typeFilter: type);
      final q = _query(wallet.id, base, firstPage: true);
      final page = await TransactionRepository.instance.list(wallet.id, query: q);
      final merged = await Outbox.instance.applyOverlay(page.transactions);
      state = AsyncData(base.copyWith(
        items: merged,
        total: merged.length,
        totalExpenses: page.totalExpenses,
        totalIncomes: page.totalIncomes,
        page: page.page,
        pages: page.pages,
        typeFilter: type,
      ));
    } catch (e, st) {
      // Repli local : filtre côté client sur le cache complet.
      final fallback = await _localFiltered(wallet.id, previous, typeFilter: type);
      if (fallback != null) {
        state = AsyncData(fallback);
      } else {
        state = AsyncError(e, st);
      }
    }
  }

  Future<TransactionsState?> _localFiltered(
    String walletId,
    TransactionsState previous, {
    String? typeFilter,
  }) async {
    final cached = await CacheService.instance.loadTransactions(walletId);
    var merged = await Outbox.instance.applyOverlay(cached);
    final filter = typeFilter ?? previous.typeFilter;
    if (filter == 'expense') merged = merged.where((t) => t.isExpense).toList();
    if (filter == 'income') merged = merged.where((t) => t.isIncome).toList();
    if (filter == 'savings') merged = merged.where((t) => t.isSavings).toList();
    return previous.copyWith(
      items: merged,
      total: merged.length,
      page: 1,
      pages: 1,
      typeFilter: filter,
    );
  }

  Future<void> setSearch(String? search) async {
    final wallet = ref.watch(walletControllerProvider).value;
    final previous = state.value;
    if (wallet == null || previous == null) return;
    final q = (search ?? '').trim();
    state = const AsyncLoading();
    final base = previous.copyWith(clearSearch: true, search: search);
    final cached = await CacheService.instance.loadTransactions(wallet.id);
    final mergedAll = await Outbox.instance.applyOverlay(cached);
    // Recherche dans tout l'historique local (instantanée, fonctionne hors-ligne).
    final filtered = q.isEmpty
        ? mergedAll
        : searchTransactions(mergedAll, q, typeFilter: base.typeFilter, walletName: wallet.name);
    state = AsyncData(base.copyWith(
      items: filtered,
      total: filtered.length,
      page: 1,
      pages: 1,
    ));
  }

  Future<void> loadMore() async {
    final wallet = ref.watch(walletControllerProvider).value;
    final s = state.value;
    if (wallet == null || s == null || !s.hasMore || s.isLoadingMore) return;
    state = AsyncData(s.copyWith(isLoadingMore: true));
    try {
      final q = _query(wallet.id, s, firstPage: false);
      q['page'] = '${s.page + 1}';
      final page = await TransactionRepository.instance.list(wallet.id, query: q);
      final merged = await Outbox.instance.applyOverlay(page.transactions);
      // Les opérations pending n'apparaissent qu'en première page : on déduplique.
      final existingIds = s.items.map((t) => t.id).toSet();
      final fresh = merged.where((t) => !existingIds.contains(t.id)).toList();
      state = AsyncData(s.copyWith(
        items: [...s.items, ...fresh],
        page: page.page,
        isLoadingMore: false,
      ));
    } catch (_) {
      state = AsyncData(s.copyWith(isLoadingMore: false));
    }
  }

  /// Après création/modification/suppression : rejoue la file puis rafraîchit
  /// liste + solde + dashboard, et attend réellement les rechargements.
  /// Se termine toujours (jamais de chargement infini).
  Future<void> refreshAll() async {
    final walletId = ref.read(walletControllerProvider).value?.id;
    if (walletId != null) {
      // Signale aux alertes qu'une écriture a eu lieu (évaluation des budgets à venir).
      await BudgetAlertsService.instance.markPending(walletId);
    }
    final flushResult = await Outbox.instance.flush();
    if (flushResult.hasFailures) {
      ref.read(syncNoticeProvider.notifier).setFailed(
            flushResult.failures.length,
            flushResult.failures.first.message,
          );
    } else if (flushResult.replayed > 0) {
      ref.read(syncNoticeProvider.notifier).clear();
    }
    ref.invalidate(dashboardControllerProvider);
    ref.invalidate(walletControllerProvider);
    ref.invalidate(budgetsControllerProvider);
    ref.invalidate(statsControllerProvider);
    try {
      await ref.read(dashboardControllerProvider.future).timeout(const Duration(seconds: 30));
    } catch (_) {
      // Le repli cache du dashboard gère déjà l'erreur.
    }
    try {
      await ref.read(walletControllerProvider.future).timeout(const Duration(seconds: 30));
    } catch (_) {
      // Idem : le contrôleur porte déjà son état de repli.
    }
    await refresh();
    await ref.read(syncInfoProvider.notifier).refresh();
  }

  static String messageFrom(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic> && data['error'] is Map<String, dynamic>) {
        final err = data['error'] as Map<String, dynamic>;
        if (err['message'] is String) return err['message'] as String;
      }
      return 'Synchronisation indisponible — réessayez';
    }
    return 'Une erreur est survenue';
  }
}

final transactionsProvider =
    AsyncNotifierProvider<TransactionsController, TransactionsState>(TransactionsController.new);

/// Phase 6 — tableau de bord. En cas de coupure réseau :
/// fallback sur le dernier cache réel + bandeau hors-ligne.
class DashboardController extends AsyncNotifier<DashboardData?> {
  @override
  Future<DashboardData?> build() async {
    final wallet = await ref.watch(walletControllerProvider.future);
    if (wallet == null) return null;
    await Outbox.instance.flush();
    final cachedRaw = await CacheService.instance.loadDashboard(wallet.id);
    if (cachedRaw != null) {
      // Cache affiché immédiatement ; revalidation en arrière-plan.
      unawaited(_refreshFromNetwork(wallet.id, cachedRaw));
      final fromCache = _fromCache(wallet.id, cachedRaw);
      return fromCache.withLatest(await Outbox.instance.applyOverlay(fromCache.latestTransactions));
    }
    try {
      final data = await DataRepository.instance.dashboard(wallet.id);
      await CacheService.instance.saveDashboard(wallet.id, data);
      return data;
    } catch (_) {
      // Aucun cache et backend injoignable : l'écran affiche l'erreur + réessayer.
      rethrow;
    }
  }

  Future<void> _refreshFromNetwork(String walletId, Map<String, dynamic> cachedRaw) async {
    try {
      final data = await DataRepository.instance.dashboard(walletId);
      await CacheService.instance.saveDashboard(walletId, data);
      state = AsyncData(data);
    } catch (_) {
      // Backend injoignable : le cache déjà affiché reste la donnée de référence.
      state = AsyncData(_fromCache(walletId, cachedRaw));
    }
  }

  DashboardData _fromCache(String walletId, Map<String, dynamic> cached) {
    final weekly = (cached['weeklySeries'] as List?)
            ?.map((p) => DailyPoint.fromJson(Map<String, dynamic>.from(p as Map)))
            .toList() ??
        const [];
    final latestRaw = cached['latestTransactions'] as List?;
    final latest = [
      if (latestRaw != null)
        for (final t in latestRaw)
          Transaction.fromJson(Map<String, dynamic>.from(t as Map)),
    ];
    return DashboardData(
      walletId: (cached['walletId'] as String?) ?? walletId,
      walletName: (cached['walletName'] as String?) ?? '',
      currency: (cached['currency'] as String?) ?? 'XOF',
      initialAmount: (cached['initialAmount'] as num?)?.toInt() ?? 0,
      balance: (cached['balance'] as num?)?.toInt() ?? 0,
      totalExpenses: (cached['totalExpenses'] as num?)?.toInt() ?? 0,
      totalIncomes: (cached['totalIncomes'] as num?)?.toInt() ?? 0,
      transactionsCount: (cached['transactionsCount'] as num?)?.toInt() ?? 0,
      percentUsed: (cached['percentUsed'] as num?)?.toInt() ?? 0,
      weeklySeries: weekly,
      latestTransactions: latest,
    );
  }

  Future<void> refresh() async {
    // Pas d'AsyncLoading : les données en cache restent affichées pendant la
    // revalidation (repli cache instantané). Se termine toujours.
    final wallet = ref.read(walletControllerProvider).value;
    state = await AsyncValue.guard(() async {
      if (wallet == null) {
        return build();
      }
      try {
        final data = await DataRepository.instance.dashboard(wallet.id);
        await CacheService.instance.saveDashboard(wallet.id, data);
        return data;
      } catch (_) {
        final raw = await CacheService.instance.loadDashboard(wallet.id);
        if (raw != null) return _fromCache(wallet.id, raw);
        rethrow;
      }
    });
  }
}

final dashboardControllerProvider =
    AsyncNotifierProvider<DashboardController, DashboardData?>(DashboardController.new);

/// Phase 8 — statistiques.
class StatsController extends AsyncNotifier<StatsData?> {
  String period = 'month';

  @override
  Future<StatsData?> build() async {
    final wallet = await ref.watch(walletControllerProvider.future);
    if (wallet == null) return null;
    return DataRepository.instance.stats(wallet.id, period: period);
  }

  Future<void> setPeriod(String p) async {
    period = p;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
  }
}

final statsControllerProvider =
    AsyncNotifierProvider<StatsController, StatsData?>(StatsController.new);

/// Phase 9 — budgets (cache local + file d'attente pour un usage hors-ligne).
class BudgetsController extends AsyncNotifier<List<Budget>> {
  @override
  Future<List<Budget>> build() async {
    final wallet = await ref.watch(walletControllerProvider.future);
    if (wallet == null) return const [];
    try {
      final budgets = await DataRepository.instance.budgets(wallet.id);
      await CacheService.instance.saveBudgets(
        wallet.id,
        budgets.map((b) => b.toJson()).toList(),
      );
      final fresh = await Outbox.instance.applyBudgetOverlay(budgets);
      await BudgetAlertsService.instance.evaluate(fresh);
      return fresh;
    } on DioException catch (_) {
      final cached = await CacheService.instance.loadBudgets(wallet.id);
      final merged = await Outbox.instance.applyBudgetOverlay(cached);
      await BudgetAlertsService.instance.evaluate(merged);
      if (merged.isNotEmpty || cached.isNotEmpty) return merged;
      rethrow;
    }
  }

  Future<void> refresh() async {
    await Outbox.instance.flush();
    final wallet = ref.read(walletControllerProvider).value;
    // Pas de spinner plein écran si un cache existe (repli instantané).
    final hasCache = wallet != null &&
        (await CacheService.instance.loadBudgets(wallet.id)).isNotEmpty;
    if (!hasCache) {
      state = const AsyncLoading();
    }
    state = await AsyncValue.guard(() => build());
  }

  Future<void> _saveCache(String walletId, List<Budget> budgets) async {
    await CacheService.instance.saveBudgets(
      walletId,
      budgets.map((b) => b.toJson()).toList(),
    );
  }

  Future<void> create({required String category, required int limitAmount, String? categoryId}) async {
    final wallet = ref.watch(walletControllerProvider).value;
    if (wallet == null) return;
    try {
      await DataRepository.instance.createBudget(wallet.id, category: category, limitAmount: limitAmount, categoryId: categoryId);
    } on DioException catch (e) {
      if (!_isNetworkish(e)) rethrow;
      final localId = Outbox.instance.newLocalId();
      final cached = await CacheService.instance.loadBudgets(wallet.id);
      await _saveCache(wallet.id, [
        ...cached,
        Budget(id: localId, walletId: wallet.id, category: category, limitAmount: limitAmount),
      ]);
      await Outbox.instance.enqueue(OutboxOp(
        id: localId,
        kind: OutboxKind.budgetUpsert,
        walletId: wallet.id,
        payload: {'id': localId, 'category': category, 'limitAmount': limitAmount, 'categoryId': ?categoryId},
        createdAt: DateTime.now(),
      ));
      await ref.read(syncInfoProvider.notifier).refresh();
    }
    await refresh();
  }

  Future<void> updateLimit(String budgetId, int limitAmount) async {
    final wallet = ref.watch(walletControllerProvider).value;
    if (wallet == null) return;
    if (Outbox.instance.isLocalId(budgetId)) {
      // Budget pas encore synchronisé : patcher le cache + l'opération en attente.
      final cached = await CacheService.instance.loadBudgets(wallet.id);
      final patched = cached
          .map((b) => b.id == budgetId
              ? Budget(
                  id: b.id,
                  walletId: b.walletId,
                  category: b.category,
                  limitAmount: limitAmount,
                )
              : b)
          .toList();
      await _saveCache(wallet.id, patched);
      await Outbox.instance.updatePendingUpsertAmount(budgetId, limitAmount);
      return refresh();
    }
    try {
      await DataRepository.instance.updateBudget(wallet.id, budgetId, limitAmount: limitAmount);
    } on DioException catch (e) {
      if (!_isNetworkish(e)) rethrow;
      final cached = await CacheService.instance.loadBudgets(wallet.id);
      final patched = cached
          .map((b) => b.id == budgetId
              ? Budget(
                  id: b.id,
                  walletId: b.walletId,
                  category: b.category,
                  limitAmount: limitAmount,
                  spent: b.spent,
                  percent: limitAmount > 0 ? ((b.spent / limitAmount) * 100).round() : 0,
                  alertLevel: b.alertLevel,
                )
              : b)
          .toList();
      await _saveCache(wallet.id, patched);
      await Outbox.instance.enqueue(OutboxOp(
        id: budgetId,
        kind: OutboxKind.budgetUpsert,
        walletId: wallet.id,
        payload: {'id': budgetId, 'limitAmount': limitAmount},
        createdAt: DateTime.now(),
      ));
      await ref.read(syncInfoProvider.notifier).refresh();
    }
    await refresh();
  }

  Future<void> remove(String budgetId) async {
    final wallet = ref.watch(walletControllerProvider).value;
    if (wallet == null) return;
    final cached = await CacheService.instance.loadBudgets(wallet.id);
    if (Outbox.instance.isLocalId(budgetId)) {
      // Jamais synchronisé : retirer la création de la file + du cache.
      await Outbox.instance.removePendingOp(budgetId);
      await _saveCache(wallet.id, cached.where((b) => b.id != budgetId).toList());
      return refresh();
    }
    try {
      await DataRepository.instance.deleteBudget(wallet.id, budgetId);
    } on DioException catch (e) {
      if (!_isNetworkish(e)) rethrow;
      await _saveCache(wallet.id, cached.where((b) => b.id != budgetId).toList());
      await Outbox.instance.enqueue(OutboxOp(
        id: budgetId,
        kind: OutboxKind.budgetDelete,
        walletId: wallet.id,
        payload: {'id': budgetId},
        createdAt: DateTime.now(),
      ));
      await ref.read(syncInfoProvider.notifier).refresh();
    }
    await refresh();
  }

  bool _isNetworkish(DioException e) {
    final status = e.response?.statusCode;
    if (status == null) return true;
    return status >= 500;
  }

  /// Alerte budget déclenchée à 50 / 80 / 100 %.
  static String alertMessage(Budget b) {
    switch (b.alertLevel) {
      case 100:
        return 'Budget ${b.category} dépassé ! (${b.percent}%)';
      case 80:
        return 'Budget ${b.category} à 80%';
      case 50:
        return 'Budget ${b.category} à 50%';
      default:
        return '';
    }
  }
}

final budgetsControllerProvider =
    AsyncNotifierProvider<BudgetsController, List<Budget>>(BudgetsController.new);
