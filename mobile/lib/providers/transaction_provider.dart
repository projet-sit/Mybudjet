import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/dashboard.dart';
import '../models/transaction.dart';
import '../services/cache_service.dart';
import '../services/data_repository.dart';
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
  final String typeFilter; // all | expense | income
  final String? categoryFilter;
  final String? search;
  final bool isLoadingMore;

  bool get hasMore => page < pages;

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
    final page = await TransactionRepository.instance.list(wallet.id, query: _query(wallet.id, const TransactionsState(), firstPage: true));
    return TransactionsState(
      items: page.transactions,
      total: page.total,
      totalExpenses: page.totalExpenses,
      totalIncomes: page.totalIncomes,
      page: page.page,
      pages: page.pages,
      typeFilter: const TransactionsState().typeFilter,
    );
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
      final q = _query(wallet.id, previous.copyWith(typeFilter: type), firstPage: true);
      final page = await TransactionRepository.instance.list(wallet.id, query: q);
      state = AsyncData(previous.copyWith(
        items: page.transactions,
        total: page.total,
        totalExpenses: page.totalExpenses,
        totalIncomes: page.totalIncomes,
        page: page.page,
        pages: page.pages,
        typeFilter: type,
      ));
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> setSearch(String? search) async {
    final wallet = ref.watch(walletControllerProvider).value;
    final previous = state.value;
    if (wallet == null || previous == null) return;
    try {
      state = const AsyncLoading();
      final base = previous.copyWith(clearSearch: true, search: search);
      final q = _query(wallet.id, base, firstPage: true);
      final page = await TransactionRepository.instance.list(wallet.id, query: q);
      state = AsyncData(base.copyWith(
        items: page.transactions,
        total: page.total,
        totalExpenses: page.totalExpenses,
        totalIncomes: page.totalIncomes,
        page: page.page,
        pages: page.pages,
      ));
    } catch (e, st) {
      state = AsyncError(e, st);
    }
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
      state = AsyncData(s.copyWith(
        items: [...s.items, ...page.transactions],
        page: page.page,
        isLoadingMore: false,
      ));
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  /// Après création/modification/suppression : rafraîchit liste + solde + dashboard,
  /// et attend réellement les rechargements pour que l'accueil affiche les chiffres à jour.
  Future<void> refreshAll() async {
    ref.invalidate(dashboardControllerProvider);
    ref.invalidate(walletControllerProvider);
    ref.invalidate(budgetsControllerProvider);
    try {
      await ref.read(dashboardControllerProvider.future);
    } catch (_) {
      // Le repli cache du dashboard gère déjà l'erreur.
    }
    try {
      await ref.read(walletControllerProvider.future);
    } catch (_) {
      // Idem : le contrôleur porte déjà son état d'erreur.
    }
    await refresh();
  }

  static String messageFrom(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic> && data['error'] is Map<String, dynamic>) {
        final err = data['error'] as Map<String, dynamic>;
        if (err['message'] is String) return err['message'] as String;
      }
      return 'Erreur réseau — vérifie ta connexion';
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
    final cachedRaw = await CacheService.instance.loadDashboard(wallet.id);
    if (cachedRaw != null) {
      // Cache affiché immédiatement ; revalidation en arrière-plan.
      unawaited(_refreshFromNetwork(wallet.id, cachedRaw));
      return _fromCache(wallet.id, cachedRaw);
    }
    try {
      final data = await DataRepository.instance.dashboard(wallet.id);
      await CacheService.instance.saveDashboard(wallet.id, data);
      ref.read(offlineProvider.notifier).set(false);
      return data;
    } catch (_) {
      // Aucun cache et réseau impossible : l'écran affiche l'erreur + réessayer.
      rethrow;
    }
  }

  Future<void> _refreshFromNetwork(String walletId, Map<String, dynamic> cachedRaw) async {
    try {
      final data = await DataRepository.instance.dashboard(walletId);
      await CacheService.instance.saveDashboard(walletId, data);
      ref.read(offlineProvider.notifier).set(false);
      state = AsyncData(data);
    } catch (_) {
      // Hors ligne : le cache déjà affiché reste la donnée de référence.
      ref.read(offlineProvider.notifier).set(true);
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
    // revalidation (hors-ligne = repli cache instantané).
    final wallet = ref.read(walletControllerProvider).value;
    state = await AsyncValue.guard(() async {
      if (wallet == null) {
        // Pas encore de portefeuille chargé : repasse par le build habituel.
        return build();
      }
      try {
        final data = await DataRepository.instance.dashboard(wallet.id);
        await CacheService.instance.saveDashboard(wallet.id, data);
        ref.read(offlineProvider.notifier).set(false);
        return data;
      } catch (_) {
        ref.read(offlineProvider.notifier).set(true);
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

/// Phase 9 — budgets.
class BudgetsController extends AsyncNotifier<List<Budget>> {
  @override
  Future<List<Budget>> build() async {
    final wallet = await ref.watch(walletControllerProvider.future);
    if (wallet == null) return const [];
    return DataRepository.instance.budgets(wallet.id);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
  }

  Future<void> create({required String category, required int limitAmount}) async {
    final wallet = ref.watch(walletControllerProvider).value;
    if (wallet == null) return;
    await DataRepository.instance.createBudget(wallet.id, category: category, limitAmount: limitAmount);
    await refresh();
  }

  Future<void> updateLimit(String budgetId, int limitAmount) async {
    final wallet = ref.watch(walletControllerProvider).value;
    if (wallet == null) return;
    await DataRepository.instance.updateBudget(wallet.id, budgetId, limitAmount: limitAmount);
    await refresh();
  }

  Future<void> remove(String budgetId) async {
    final wallet = ref.watch(walletControllerProvider).value;
    if (wallet == null) return;
    await DataRepository.instance.deleteBudget(wallet.id, budgetId);
    await refresh();
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
