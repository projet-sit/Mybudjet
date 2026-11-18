import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/search/transaction_search.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/app_feedback.dart';
import '../../models/transaction.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/cache_service.dart';
import '../../services/data_repository.dart';
import '../../services/outbox.dart';
import '../../widgets/transaction_tile.dart';
import '../transactions/transaction_detail_sheet.dart';

/// Opérations : recherche instantanée sur TOUT l'historique (cache local),
/// filtres Tout/Dépenses/Revenus/Épargne, regroupement par jour,
/// suppression par glissement avec annulation.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _searchController = TextEditingController();
  final Set<String> _hidden = <String>{};
  Timer? _debounce;
  String _query = '';
  List<Transaction>? _searchResults;
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    showErrorSnackBar(context, message);
  }

  bool get _isSearching => _query.trim().isNotEmpty;

  /// Suppression immédiate (glissement) avec annulation possible.
  Future<void> _delete(Transaction tx) async {
    final wallet = ref.read(walletControllerProvider).value;
    if (wallet == null) {
      _snack('Aucun portefeuille actif.');
      return;
    }
    setState(() => _hidden.add(tx.id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await TransactionRepository.instance.delete(wallet.id, tx.id);
      await ref.read(transactionsProvider.notifier).refreshAll();
      if (mounted) setState(() => _hidden.remove(tx.id));
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      await showSuccessDialog(
        context,
        title: 'Opération supprimée !',
        message: 'Votre opération a été supprimée avec succès.',
        actionLabel: 'Annuler',
        onAction: () {
          if (context.mounted) Navigator.of(context).pop();
          _restore(tx);
        },
      );
      if (_isSearching) await _runSearch();
    } catch (e) {
      if (mounted) setState(() => _hidden.remove(tx.id));
      if (mounted) showErrorSnackBar(context, TransactionsController.messageFrom(e));
    }
  }

  Future<void> _restore(Transaction tx) async {
    final wallet = ref.read(walletControllerProvider).value;
    if (wallet == null) return;
    try {
      await TransactionRepository.instance.create(wallet.id, tx);
      await ref.read(transactionsProvider.notifier).refreshAll();
      if (_isSearching) await _runSearch();
      if (!mounted) return;
      await showSuccessDialog(
        context,
        title: 'Opération restaurée !',
        message: 'Votre opération a été restaurée avec succès.',
      );
    } catch (e) {
      if (mounted) showErrorSnackBar(context, TransactionsController.messageFrom(e));
    }
  }

  void _openDetail(Transaction tx) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => TransactionDetailSheet(transaction: tx),
    );
  }

  void _clearSearch() {
    _searchController.clear();
    _debounce?.cancel();
    setState(() {
      _query = '';
      _searchResults = null;
      _searching = false;
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    setState(() => _query = value);
    // ~300 ms : laisse l'utilisateur finir de taper avant de lancer la recherche.
    _debounce = Timer(const Duration(milliseconds: 300), _runSearch);
  }

  Future<void> _runSearch() async {
    final q = _query.trim();
    final typeFilter = ref.read(transactionsProvider).value?.typeFilter ?? 'all';
    if (q.isEmpty) {
      if (mounted) {
        setState(() {
          _searchResults = null;
          _searching = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _searching = true);
    try {
      final wallet = ref.read(walletControllerProvider).value;
      if (wallet == null) {
        if (mounted) {
          setState(() {
            _searchResults = const [];
            _searching = false;
          });
        }
        return;
      }
      var ledger = await CacheService.instance.loadTransactions(wallet.id);
      ledger = await Outbox.instance.applyOverlay(ledger);
      if (ledger.isEmpty) {
        try {
          ledger = await TransactionRepository.instance.fetchAll(wallet.id);
        } catch (_) {
          ledger = const [];
        }
      }
      List<Transaction> results;
      try {
        results = await searchFullLedger(
          ledger,
          q,
          typeFilter: typeFilter,
          walletName: wallet.name,
        );
      } catch (_) {
        // Repli : recherche synchrone sur le thread UI (jamais bloquant).
        results = searchTransactions(
          ledger,
          q,
          typeFilter: typeFilter,
          walletName: wallet.name,
        );
      }
      final visible = results.where((t) => !_hidden.contains(t.id)).toList();
      if (!mounted) return;
      setState(() {
        _searchResults = visible;
        _searching = false;
      });
    } catch (_) {
      // Jamais de chargement infini : en cas d'erreur, on affiche l'état vide.
      if (!mounted) return;
      setState(() {
        _searchResults = const [];
        _searching = false;
      });
    }
  }

  Future<void> _setFilter(String type) async {
    await ref.read(transactionsProvider.notifier).setTypeFilter(type);
    if (_isSearching) await _runSearch();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(transactionsProvider);

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Opérations',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: scheme.onSurface),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Rechercher une opération…',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        tooltip: 'Effacer la recherche',
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: _clearSearch,
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: state.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data: (s) => ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _chip('Tout', s.typeFilter == 'all', () => _setFilter('all')),
                  const SizedBox(width: 8),
                  _chip('Dépenses', s.typeFilter == 'expense', () => _setFilter('expense')),
                  const SizedBox(width: 8),
                  _chip('Revenus', s.typeFilter == 'income', () => _setFilter('income')),
                  const SizedBox(width: 8),
                  _chip('Épargne', s.typeFilter == 'savings', () => _setFilter('savings')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _isSearching
                ? _searchList(scheme)
                : state.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (error, _) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              TransactionsController.messageFrom(error),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: scheme.error),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: () => ref.read(transactionsProvider.notifier).refresh(),
                              child: const Text('Réessayer'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    data: (s) {
                      final visible = s.items
                          .where((tx) => !_hidden.contains(tx.id))
                          .toList(growable: false);
                      return _transactionList(
                        scheme,
                        visible,
                        emptyTitle: 'Aucune opération',
                        emptySubtitle: 'Ajoute ta première dépense ou ton premier revenu.',
                        emptyIcon: Icons.receipt_long_outlined,
                        hasMore: s.hasMore,
                        isLoadingMore: s.isLoadingMore,
                        highlight: null,
                        footerCount: s.total,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _searchList(ColorScheme scheme) {
    // Résultats pas encore calculés (recherche en cours ou debounce) : jamais
    // l'état vide pour ne pas faire clignoter « Aucune opération trouvée ».
    if (_searching || _searchResults == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final results = _searchResults ?? const <Transaction>[];
    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, size: 48, color: scheme.onSurfaceVariant),
              const SizedBox(height: 10),
              Text(
                'Aucune opération trouvée pour “${_query.trim()}”',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _clearSearch,
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Effacer la recherche'),
              ),
            ],
          ),
        ),
      );
    }
    return _transactionList(
      scheme,
      results,
      emptyTitle: '',
      emptySubtitle: '',
      emptyIcon: Icons.search_off_rounded,
      hasMore: false,
      isLoadingMore: false,
      highlight: _query.trim(),
      footerCount: results.length,
    );
  }

  Widget _transactionList(
    ColorScheme scheme,
    List<Transaction> items, {
    required String emptyTitle,
    required String emptySubtitle,
    required IconData emptyIcon,
    required bool hasMore,
    required bool isLoadingMore,
    required String? highlight,
    required int footerCount,
  }) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(emptyIcon, size: 48, color: scheme.onSurfaceVariant),
              const SizedBox(height: 10),
              Text(
                emptyTitle,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                emptySubtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    final groups = <String, List<Transaction>>{};
    for (final tx in items) {
      groups.putIfAbsent(tx.date, () => []).add(tx);
    }

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(walletControllerProvider.notifier).refresh();
        await ref.read(transactionsProvider.notifier).refresh();
        if (_isSearching) await _runSearch();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        children: [
          Text(
            '$footerCount opération${footerCount > 1 ? 's' : ''}',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          for (final entry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
              child: Row(
                children: [
                  Text(
                    relativeDateLabel(entry.key),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  if (_hasCountableOps(entry.value))
                    Text(
                      formatMoneyCurrent(
                        entry.value.fold<int>(
                          0,
                          (sum, tx) => sum + (tx.isExpense ? -tx.amount : (tx.isIncome ? tx.amount : 0)),
                        ),
                        withCurrency: false,
                      ),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: scheme.outline),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < entry.value.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, indent: 66, color: scheme.outline),
                    Dismissible(
                      key: ValueKey(entry.value[i].id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: scheme.error,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: Icon(Icons.delete_outline, color: scheme.onError),
                      ),
                      onDismissed: (_) => _delete(entry.value[i]),
                      child: TransactionTile(
                        transaction: entry.value[i],
                        onTap: () => _openDetail(entry.value[i]),
                        highlight: highlight,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (hasMore && !_isSearching) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: isLoadingMore
                  ? null
                  : () => ref.read(transactionsProvider.notifier).loadMore(),
              child: isLoadingMore
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Charger plus'),
            ),
          ],
        ],
      ),
    );
  }

  bool _hasCountableOps(List<Transaction> list) =>
      list.any((tx) => !tx.isSavings);

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : scheme.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? scheme.primary : scheme.outline),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
