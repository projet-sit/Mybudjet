import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../models/categories.dart';
import '../../models/dashboard.dart';
import '../../providers/app_prefs_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/wallet_provider.dart';

/// Budgets (maquette « MyBudget ») : progression par catégorie,
/// ajustement ±5000 FCFA, alertes 50/80/100 %.
class BudgetsScreen extends ConsumerStatefulWidget {
  const BudgetsScreen({super.key});

  @override
  ConsumerState<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends ConsumerState<BudgetsScreen> {
  final _alerted = <String, int>{};

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final budgetsState = ref.watch(budgetsControllerProvider);
    final wallet = ref.watch(walletControllerProvider).value;

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Budgets',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: scheme.onSurface),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    tooltip: 'Nouveau budget',
                    onPressed: wallet == null ? null : _createBudgetDialog,
                    icon: Icon(Icons.add_rounded, color: scheme.primary),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Garde le contrôle de tes dépenses par catégorie.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: budgetsState.when(
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
                        onPressed: () => ref.read(budgetsControllerProvider.notifier).refresh(),
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (budgets) {
                _checkAlerts(budgets);
                if (budgets.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_outlined, size: 52, color: scheme.primary),
                          const SizedBox(height: 12),
                          Text(
                            'Aucun budget défini',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Touche le bouton + en haut pour créer ton premier budget.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () => ref.read(budgetsControllerProvider.notifier).refresh(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    children: [
                      for (final b in budgets) _budgetCard(b),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _checkAlerts(List<Budget> budgets) {
    if (!(ref.read(alertsEnabledProvider).value ?? true)) return;
    for (final b in budgets) {
      final previous = _alerted[b.id] ?? 0;
      if (b.alertLevel > previous && b.alertLevel >= 50) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(BudgetsController.alertMessage(b))),
          );
        });
      }
      _alerted[b.id] = b.alertLevel;
    }
  }

  Widget _budgetCard(Budget b) {
    final scheme = Theme.of(context).colorScheme;
    final percent = b.percent.clamp(0, 100);
    final color = b.percent >= 100
        ? scheme.error
        : b.percent >= 80
            ? AppColors.warning
            : scheme.primary;

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.verified_outlined, color: scheme.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.category,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: scheme.onSurface),
                    ),
                    Text(
                      '${formatXof(b.spent, withCurrency: false)} / ${formatXof(b.limitAmount, withCurrency: false)} FCFA',
                      style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Text(
                '$percent%',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color),
              ),
              PopupMenuButton<String>(
                iconSize: 20,
                icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
                onSelected: (value) async {
                  if (value == 'edit') {
                    _editBudgetDialog(b);
                  } else if (value == 'delete') {
                    await _confirmDelete(b);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Modifier la limite')),
                  PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 8,
              backgroundColor: scheme.outline,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Reste ${formatXof(b.remaining)}',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ),
              _adjustButton('−5 000', () => _adjust(b, -5000)),
              const SizedBox(width: 6),
              _adjustButton('+5 000', () => _adjust(b, 5000)),
            ],
          ),
          if (b.alertLevel >= 80) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 15, color: color),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    b.alertLevel >= 100
                        ? 'Budget dépassé'
                        : 'Attention : ${b.alertLevel}% du budget utilisé',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _adjustButton(String label, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.primary),
          ),
        ),
      ),
    );
  }

  Future<void> _adjust(Budget b, int delta) async {
    final next = (b.limitAmount + delta).clamp(1000, 100000000);
    try {
      await ref.read(budgetsControllerProvider.notifier).updateLimit(b.id, next);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(TransactionsController.messageFrom(e))),
      );
    }
  }

  Future<void> _confirmDelete(Budget b) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Supprimer le budget ${b.category} ?'),
        content: const Text('Tu pourras le recréer à tout moment.'),
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
    if (confirmed == true) {
      await ref.read(budgetsControllerProvider.notifier).remove(b.id);
    }
  }

  Future<void> _createBudgetDialog() async {
    final existing = ref.read(budgetsControllerProvider).value ?? const <Budget>[];
    final used = existing.map((b) => b.category).toSet();
    final available = [
      for (final (name, _) in ExpenseCategories.list)
        if (!used.contains(name)) name,
    ];
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Un budget existe déjà pour chaque catégorie.')),
      );
      return;
    }

    final result = await showDialog<({String category, int amount})>(
      context: context,
      builder: (dialogContext) {
        var category = available.first;
        final amountController = TextEditingController();
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('Créer un budget'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: category,
                  items: [
                    for (final name in available) DropdownMenuItem(value: name, child: Text(name)),
                  ],
                  onChanged: (value) => setDialogState(() => category = value ?? category),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(hintText: 'Limite (ex : 30000)'),
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
                  final amount = int.tryParse(amountController.text.replaceAll(' ', ''));
                  if (amount == null || amount <= 0) return;
                  Navigator.pop(dialogContext, (category: category, amount: amount));
                },
                child: const Text('Créer'),
              ),
            ],
          ),
        );
      },
    );
    if (result != null) {
      await ref
          .read(budgetsControllerProvider.notifier)
          .create(category: result.category, limitAmount: result.amount);
    }
  }

  Future<void> _editBudgetDialog(Budget b) async {
    final controller = TextEditingController(text: '${b.limitAmount}');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Budget ${b.category}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(hintText: 'Nouvelle limite'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (confirmed == true) {
      final amount = int.tryParse(controller.text.replaceAll(' ', ''));
      if (amount != null && amount > 0) {
        await ref.read(budgetsControllerProvider.notifier).updateLimit(b.id, amount);
      }
    }
  }
}
