import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/app_feedback.dart';
import '../../models/transaction.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/data_repository.dart';
import '../../widgets/transaction_tile.dart';
import 'quick_add_sheet.dart';

/// Détail d'une opération (maquette) : montant, infos, Modifier / Supprimer.
class TransactionDetailSheet extends ConsumerWidget {
  const TransactionDetailSheet({super.key, required this.transaction});

  final Transaction transaction;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final wallet = ref.read(walletControllerProvider).value;
    if (wallet == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette opération ?'),
        content: Text(
          '${transaction.category} — ${formatMoneyCurrent(transaction.amount)}. Cette action est définitive.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await TransactionRepository.instance.delete(wallet.id, transaction.id);
      await ref.read(transactionsProvider.notifier).refreshAll();
      if (!context.mounted) return;
      // La boîte de succès s'affiche AU-DESSUS de la fiche, puis on ferme la fiche.
            if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!context.mounted) return;
      showErrorSnackBar(context, TransactionsController.messageFrom(e));
    }
  }

  void _edit(BuildContext context) {
    final navigator = Navigator.of(context);
    final parent = navigator.context;
    navigator.pop();
    showModalBottomSheet<void>(
      context: parent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => QuickAddSheet(editing: transaction),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isExpense = transaction.isExpense;
    final isSavings = transaction.isSavings;
    final title = transactionTitle(transaction);
    final sign = isSavings ? '' : (isExpense ? '−' : '+');
    final accent = isExpense ? scheme.error : (isSavings ? savingsNeutral : AppColors.incomeGreen);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                categoryIcon(transaction.category, isExpense),
                color: accent,
                size: 28,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              '$sign${formatMoneyCurrent(transaction.amount)}',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                color: accent,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              title,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: scheme.onSurface),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.darkBg
                  : AppColors.offWhite,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                _row(context, 'Type', isSavings ? 'Épargne' : (isExpense ? 'Dépense' : 'Revenu')),
                Divider(color: scheme.outline),
                _row(context, 'Catégorie', transaction.category),
                Divider(color: scheme.outline),
                _row(context, 'Date', formatDateFr(transaction.date)),
                Divider(color: scheme.outline),
                _row(context, 'Heure', DateFormatUtil.formatTime(transaction.time)),
                if (transaction.paymentMethod != null) ...[
                  Divider(color: scheme.outline),
                  _row(context, 'Paiement', transaction.paymentMethod!),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              if (!isSavings) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _edit(context),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Modifier'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: scheme.error),
                  onPressed: () => _delete(context, ref),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Supprimer'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurface),
          ),
        ],
      ),
    );
  }
}
