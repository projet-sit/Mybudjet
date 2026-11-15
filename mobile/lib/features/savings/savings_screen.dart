import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../models/transaction.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/cache_service.dart';
import '../../services/outbox.dart';
import '../../widgets/transaction_tile.dart';

/// Mon épargne : l'argent reste dans le même compte, en réserve.
/// - Versement : sort du Reste, augmente l'épargne (jamais une dépense).
/// - Retrait : revient dans le Reste.
/// - Tout récupérer : toute l'épargne retourne dans le Reste, atomique.
class SavingsScreen extends ConsumerStatefulWidget {
  const SavingsScreen({super.key});

  @override
  ConsumerState<SavingsScreen> createState() => _SavingsScreenState();
}

class _SavingsScreenState extends ConsumerState<SavingsScreen> {
  bool _busy = false;

  Future<void> _move({required bool deposit}) async {
    final wallet = ref.read(walletControllerProvider).value;
    if (wallet == null) return;
    final reste = wallet.available;
    final max = deposit ? reste : wallet.savingsAmount;
    if (max <= 0 && deposit) {
      _snack('Ton Reste est à zéro — rien à épargner');
      return;
    }
    if (max <= 0 && !deposit) {
      _snack('Ton épargne est vide');
      return;
    }
    final controller = TextEditingController();
    final amount = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(deposit ? 'Verser à l’épargne' : 'Retirer de l’épargne'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              deposit
                  ? 'L’argent sort de ton Reste (${formatXof(reste)} max) vers l’épargne.'
                  : 'L’argent revient dans ton Reste (${formatXof(wallet.savingsAmount)} max).',
              style: const TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                hintText: 'Montant (FCFA)',
                suffixText: 'FCFA',
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(dialogContext, max),
                child: Text(deposit ? 'Tout épargner : ${formatXof(max, withCurrency: false)}'
                    : 'Tout retirer : ${formatXof(max, withCurrency: false)}'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.replaceAll(' ', ''));
              if (parsed == null || parsed <= 0) return;
              Navigator.pop(dialogContext, parsed);
            },
            child: Text(deposit ? 'Verser' : 'Retirer'),
          ),
        ],
      ),
    );
    if (amount == null || !mounted) return;
    if (amount > max) {
      _snack(deposit
          ? 'Montant trop élevé : il reste ${formatXof(max)} dans ton Reste'
          : 'Montant trop élevé : ton épargne est de ${formatXof(max)}');
      return;
    }
    setState(() => _busy = true);
    try {
      if (deposit) {
        await ref.read(walletControllerProvider.notifier).savingsDeposit(amount);
      } else {
        await ref.read(walletControllerProvider.notifier).savingsWithdraw(amount);
      }
      await ref.read(transactionsProvider.notifier).refreshAll();
      if (mounted) {
        _snack(deposit
            ? 'Versement de ${formatXof(amount)} enregistré'
            : 'Retrait de ${formatXof(amount)} enregistré');
      }
    } catch (e) {
      if (mounted) _snack(WalletController.messageFrom(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withdrawAll() async {
    final wallet = ref.read(walletControllerProvider).value;
    if (wallet == null) return;
    final savings = wallet.savingsAmount;
    if (savings <= 0) {
      _snack('Ton épargne est déjà vide');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tout récupérer ?'),
        content: Text(
          'Les ${formatXof(savings)} épargnés reviennent dans ton Reste en une seule fois.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Tout récupérer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(walletControllerProvider.notifier).savingsWithdrawAll();
      await ref.read(transactionsProvider.notifier).refreshAll();
      if (mounted) {
        _snack(result.queued
            ? 'Récupération enregistrée — elle sera synchronisée au retour du réseau'
            : 'Épargne récupérée : ${formatXof(savings)} de retour dans ton Reste');
      }
    } catch (e) {
      if (mounted) _snack(WalletController.messageFrom(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<List<Transaction>> _loadHistory() async {
    final wallet = ref.read(walletControllerProvider).value;
    if (wallet == null) return const [];
    // Cache complet + opérations en attente (fusion, ordre décroissant).
    final cached = await CacheService.instance.loadTransactions(wallet.id);
    final merged = await Outbox.instance.applyOverlay(cached);
    final savings = merged.where((t) => t.isSavings).toList()
      ..sort((a, b) {
        final cmp = b.date.compareTo(a.date);
        return cmp != 0 ? cmp : b.time.compareTo(a.time);
      });
    return savings;
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wallet = ref.watch(walletControllerProvider).value;
    // Recharge l'historique quand les transactions changent.
    ref.watch(transactionsProvider);

    if (wallet == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mon épargne')),
        body: const Center(child: Text('Crée d’abord ton budget.')),
      );
    }

    final savings = wallet.savingsAmount;
    final reste = wallet.available;

    return Scaffold(
      appBar: AppBar(title: const Text('Mon épargne')),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(walletControllerProvider.notifier).refresh();
          await ref.read(transactionsProvider.notifier).refresh();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.deepGreenLight, AppColors.deepGreen, AppColors.deepGreenDark],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Épargne totale',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatXof(savings),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Reste à dépenser : ${formatXof(reste)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Solde total : ${formatXof(wallet.balance)}',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _move(deposit: true),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Ajouter'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _move(deposit: false),
                    icon: const Icon(Icons.remove_rounded, size: 18),
                    label: const Text('Retirer'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy || savings <= 0 ? null : _withdrawAll,
                icon: const Icon(Icons.savings_outlined, size: 18),
                label: const Text('Tout récupérer'),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Historique des versements et retraits',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<Transaction>>(
              future: _loadHistory(),
              builder: (context, snapshot) {
                final entries = snapshot.data ?? const <Transaction>[];
                if (snapshot.connectionState == ConnectionState.waiting && entries.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (entries.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        Icon(Icons.savings_outlined, size: 40, color: scheme.onSurfaceVariant),
                        const SizedBox(height: 8),
                        Text(
                          'Aucune opération d’épargne pour le moment',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                }
                return Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: scheme.outline),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < entries.length; i++) ...[
                        if (i > 0) Divider(height: 1, indent: 66, color: scheme.outline),
                        TransactionTile(transaction: entries[i]),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

