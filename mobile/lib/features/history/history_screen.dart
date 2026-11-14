import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/money.dart';
import '../../models/transaction.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/data_repository.dart';
import '../../widgets/transaction_tile.dart';
import '../transactions/transaction_detail_sheet.dart';

/// Opérations (maquette) : filtres, regroupement par jour, détail,
/// suppression par glissement avec annulation.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _searchController = TextEditingController();
  final Set<String> _hidden = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

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
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Opération supprimée'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(label: 'Annuler', onPressed: () => _restore(tx)),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _hidden.remove(tx.id));
      messenger.showSnackBar(SnackBar(content: Text(TransactionsController.messageFrom(e))));
    }
  }

  Future<void> _restore(Transaction tx) async {
    final wallet = ref.read(walletControllerProvider).value;
    if (wallet == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await TransactionRepository.instance.create(wallet.id, tx);
      await ref.read(transactionsProvider.notifier).refreshAll();
      messenger.showSnackBar(const SnackBar(content: Text('Opération restaurée')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(TransactionsController.messageFrom(e))));
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
    ref.read(transactionsProvider.notifier).setSearch(null);
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
              onSubmitted: (value) {
                ref.read(transactionsProvider.notifier).setSearch(value.trim().isEmpty ? null : value.trim());
              },
              onChanged: (value) {
                // Effacer le champ revient à réinitialiser la recherche.
                if (value.trim().isEmpty &&
                    (ref.read(transactionsProvider).value?.search?.trim().isNotEmpty ?? false)) {
                  ref.read(transactionsProvider.notifier).setSearch(null);
                }
              },
              decoration: const InputDecoration(
                hintText: 'Rechercher une opération…',
                prefixIcon: Icon(Icons.search_rounded, size: 20),
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
                  _chip('Tout', s.typeFilter == 'all', () {
                    ref.read(transactionsProvider.notifier).setTypeFilter('all');
                  }),
                  const SizedBox(width: 8),
                  _chip('Dépenses', s.typeFilter == 'expense', () {
                    ref.read(transactionsProvider.notifier).setTypeFilter('expense');
                  }),
                  const SizedBox(width: 8),
                  _chip('Revenus', s.typeFilter == 'income', () {
                    ref.read(transactionsProvider.notifier).setTypeFilter('income');
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: state.when(
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

                if (visible.isEmpty) {
                  final searching = s.search?.trim().isNotEmpty ?? false;
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            searching ? Icons.search_off_rounded : Icons.receipt_long_outlined,
                            size: 48,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            searching ? 'Aucun résultat' : 'Aucune opération',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            searching
                                ? 'Essaie un autre mot-clé ou efface la recherche.'
                                : 'Ajoute ta première dépense ou ton premier revenu.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 16),
                          if (searching)
                            OutlinedButton.icon(
                              onPressed: _clearSearch,
                              icon: const Icon(Icons.close_rounded, size: 18),
                              label: const Text('Effacer la recherche'),
                            )
                          else
                            Text(
                              'Utilise le bouton + en bas de l’écran',
                              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                  );
                }

                final groups = <String, List<Transaction>>{};
                for (final tx in visible) {
                  groups.putIfAbsent(tx.date, () => []).add(tx);
                }

                return NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification.metrics.extentAfter < 300) {
                      ref.read(transactionsProvider.notifier).loadMore();
                    }
                    return false;
                  },
                  child: RefreshIndicator(
                    onRefresh: () async {
                      await ref.read(walletControllerProvider.notifier).refresh();
                      await ref.read(transactionsProvider.notifier).refresh();
                    },
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      children: [
                        Text(
                          '${s.total} opération${s.total > 1 ? 's' : ''}',
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
                                Text(
                                  formatXof(
                                    entry.value.fold<int>(
                                      0,
                                      (sum, tx) => sum + (tx.isExpense ? -tx.amount : tx.amount),
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
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                        if (s.hasMore) ...[
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: s.isLoadingMore
                                ? null
                                : () => ref.read(transactionsProvider.notifier).loadMore(),
                            child: s.isLoadingMore
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
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

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
