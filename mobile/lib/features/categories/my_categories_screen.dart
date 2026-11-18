import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/category_names.dart';
import '../../core/widgets/app_feedback.dart';
import '../../models/category.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/category_provider.dart';
import '../../services/category_repository.dart';

/// Profil → Mes catégories : renommer ou supprimer une catégorie personnalisée.
/// Les catégories par défaut ne peuvent pas être modifiées ni supprimées.
/// Suppression : les opérations passent en « Autres » (jamais perdues) ;
/// un budget lié est supprimé après confirmation.
class MyCategoriesScreen extends ConsumerStatefulWidget {
  const MyCategoriesScreen({super.key});

  @override
  ConsumerState<MyCategoriesScreen> createState() => _MyCategoriesScreenState();
}

class _MyCategoriesScreenState extends ConsumerState<MyCategoriesScreen> {
  bool _busy = false;

  Future<void> _reload() async {
    await ref.read(categoriesProvider.notifier).refresh();
    ref.invalidate(transactionsProvider);
  }

  Future<void> _renameDialog(Category category) async {
    final controller = TextEditingController(text: category.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renommer la catégorie'),
        content: TextField(
          controller: controller,
          maxLength: 30,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Nouveau nom',
            counterText: '',
          ),
          onSubmitted: (_) => Navigator.pop(ctx, controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;

    final check = validateCategoryName(result);
    if (!check.ok) {
      _snack(check.error ?? 'Nom invalide');
      return;
    }

    setState(() => _busy = true);
    try {
      final res = await CategoryRepository.instance.rename(category.id, check.value);
      if (!mounted) return;
      if (res.existed) {
        showInfoSnackBar(context, 'Cette catégorie existe déjà, elle est sélectionnée');
      } else {
        await showSuccessDialog(
          context,
          title: 'Catégorie renommée !',
          message: 'Votre catégorie a été renommée avec succès.',
        );
      }
      await _reload();
    } catch (e) {
      if (mounted) showErrorSnackBar(context, TransactionsController.messageFrom(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteFlow(Category category) async {

    // Première tentative (sans confirmation de suppression de budget).
    setState(() => _busy = true);
    try {
      await CategoryRepository.instance.delete(category.id);
      if (!mounted) return;
      await showSuccessDialog(
        context,
        title: 'Catégorie supprimée !',
        message: 'Les opérations passent en « Autres » et ne sont pas perdues.',
      );
      await _reload();
      return;
    } on BudgetLinkedException catch (linked) {
      if (!mounted) return;
      final names = linked.budgets.map((b) => b.name).join(', ');
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Budget lié : $names'),
          content: Text(
            'Un budget est lié à « ${category.name} ». '
            'Si tu supprimes la catégorie, ce budget sera supprimé aussi.\n\n'
            'Les opérations passent en « Autres » et ne sont pas perdues. Continuer ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer quand même'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    } catch (e) {
      if (mounted) showErrorSnackBar(context, TransactionsController.messageFrom(e));
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    setState(() => _busy = true);
    try {
      await CategoryRepository.instance.delete(category.id, confirmBudgets: true);
      if (!mounted) return;
      await showSuccessDialog(
        context,
        title: 'Catégorie supprimée !',
        message: 'La catégorie et son budget ont été supprimés.',
      );
      await _reload();
    } catch (e) {
      if (mounted) showErrorSnackBar(context, TransactionsController.messageFrom(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete(Category category) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Supprimer « ${category.name} » ?'),
        content: const Text(
          'Les opérations de cette catégorie passent en « Autres » (jamais perdues). '
          'Si un budget y est lié, il sera supprimé après confirmation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok == true) await _deleteFlow(category);
  }

  void _snack(String message) {
    if (!mounted) return;
    showErrorSnackBar(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final all = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes catégories'),
      ),
      body: all.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Impossible de charger les catégories.'),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _reload,
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
        data: (categories) {
          final expense = categories.where((c) => c.type == 'expense').toList();
          final income = categories.where((c) => c.type == 'income').toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Text(
                'Les catégories par défaut ne peuvent pas être modifiées. '
                'Tes catégories personnalisées se renomment ou se suppriment ici.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              _SectionLabel('Dépenses'),
              const SizedBox(height: 6),
              for (final category in expense)
                _CategoryTile(
                  category: category,
                  onRename: category.isDefault || _busy ? null : () => _renameDialog(category),
                  onDelete: category.isDefault || _busy ? null : () => _confirmDelete(category),
                ),
              const SizedBox(height: 16),
              _SectionLabel('Revenus'),
              const SizedBox(height: 6),
              for (final category in income)
                _CategoryTile(
                  category: category,
                  onRename: category.isDefault || _busy ? null : () => _renameDialog(category),
                  onDelete: category.isDefault || _busy ? null : () => _confirmDelete(category),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.onRename,
    required this.onDelete,
  });

  final Category category;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outline),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: Icon(
            category.isDefault ? _defaultIcon(category.name) : Icons.label_outline,
            size: 18,
            color: scheme.primary,
          ),
        ),
        title: Text(category.name),
        subtitle: Text(category.isDefault ? 'Par défaut' : 'Personnalisée'),
        trailing: category.isDefault
            ? Icon(Icons.lock_outline, size: 16, color: scheme.onSurfaceVariant)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Renommer',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: onRename,
                  ),
                  IconButton(
                    tooltip: 'Supprimer',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onDelete,
                  ),
                ],
              ),
      ),
    );
  }

  IconData _defaultIcon(String name) {
    switch (name) {
      case 'Alimentation':
        return Icons.restaurant;
      case 'Transport':
        return Icons.directions_car;
      case 'Logement':
        return Icons.home;
      case 'Santé':
        return Icons.favorite_border;
      case 'Études':
        return Icons.school;
      case 'Communication':
        return Icons.chat_bubble_outline;
      case 'Loisirs':
        return Icons.sports_esports;
      case 'Shopping':
        return Icons.shopping_bag_outlined;
      case 'Abonnements':
        return Icons.subscriptions;
      case 'Famille':
        return Icons.family_restroom;
      case 'Salaire':
        return Icons.payments_outlined;
      case 'Business':
        return Icons.business_center_outlined;
      case 'Cadeau':
        return Icons.card_giftcard;
      case 'Bourse':
        return Icons.school;
      default:
        return Icons.more_horiz;
    }
  }
}
