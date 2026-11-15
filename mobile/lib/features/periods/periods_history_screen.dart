import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/money.dart';
import '../../models/period.dart';
import '../../providers/periods_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/period_repository.dart';
import '../../widgets/transaction_tile.dart';

/// Historique des périodes : active + archivées (remises à zéro, fins de mois).
/// Chaque période archivée affiche ses totaux et peut être restaurée
/// (uniquement si la période en cours est vide — sinon le serveur refuse).
class PeriodsHistoryScreen extends ConsumerWidget {
  const PeriodsHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(periodsHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Historique des périodes')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(periodsHistoryProvider.notifier).refresh(),
        child: state.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Impossible de charger les périodes. Vérifie ta connexion.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.error),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => ref.read(periodsHistoryProvider.notifier).refresh(),
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            ),
          ),
          data: (periods) {
            if (periods.isEmpty) {
              return const Center(child: Text('Aucune période pour le moment.'));
            }
            final archived = periods.where((p) => !p.isActive).toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(
                  'Les périodes archivées gardent tous leurs chiffres. '
                  'La période en cours ne peut pas être restaurée.',
                  style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                for (final period in periods) ...[
                  _PeriodCard(period: period),
                  const SizedBox(height: 12),
                ],
                if (archived.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Aucune période archivée pour le moment. Une remise à zéro ou la fin d’un mois créera une archive ici.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PeriodCard extends ConsumerWidget {
  const _PeriodCard({required this.period});

  final PeriodSummary period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final start = DateFormatUtil.parseLocal(period.startDate);
    final monthLabel = start != null
        ? DateFormat('MMMM yyyy', 'fr_FR').format(start)
        : period.startDate;
    final isActive = period.isActive;
    final walletAtClose = period.walletAtClose;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isActive ? scheme.primary : scheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isActive ? scheme.primary.withValues(alpha: 0.12) : scheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isActive ? Icons.play_circle_outline : Icons.archive_outlined,
                  size: 20,
                  color: isActive ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      monthLabel,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(
                      isActive
                          ? 'Période en cours'
                          : 'Archivée',
                      style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Active',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _stat(scheme, 'Dépenses', period.totals.expenses, scheme.error),
              ),
              Expanded(
                child: _stat(scheme, 'Revenus', period.totals.incomes, AppColors.incomeGreen),
              ),
              Expanded(
                child: _stat(scheme, 'Épargne', period.totals.saved, savingsNeutral),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${period.totals.transactions} opération${period.totals.transactions > 1 ? 's' : ''}',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          if (walletAtClose != null) ...[
            const SizedBox(height: 6),
            Text(
              'Solde à l’archivage : ${formatXof(walletAtClose.balance)} · Épargne ${formatXof(walletAtClose.savingsAmount, withCurrency: false)}',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
          if (!isActive) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _restore(context, ref, period),
                icon: const Icon(Icons.restore, size: 18),
                label: const Text('Restaurer cette période'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(ColorScheme scheme, String label, int amount, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(
          formatXof(amount, withCurrency: false),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: accent),
        ),
      ],
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref, PeriodSummary period) async {
    final monthLabel = DateFormat('MMMM yyyy', 'fr_FR').format(
      DateFormatUtil.parseLocal(period.startDate) ?? DateTime.now(),
    );
    // Confirmation 1 : explication claire
    final step1 = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Restaurer $monthLabel ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Voilà ce qui se passera :'),
            const SizedBox(height: 8),
            const _Bullet('La période en cours sera archivée (rien n’est supprimé)'),
            _Bullet('La période de $monthLabel redevient la période active'),
            _Bullet('Ton solde et ton épargne reprennent les valeurs d’$monthLabel'),
            const SizedBox(height: 10),
            Text(
              'La période en cours doit être vide (aucune opération). Sinon, le serveur refuse.',
              style: TextStyle(fontSize: 12, color: Theme.of(dialogContext).colorScheme.error),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
    if (step1 != true || !context.mounted) return;

    // Confirmation 2 : bouton rouge
    final step2 = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Dernière confirmation'),
        content: Text(
          'Restaurer $monthLabel à la place de la période en cours ? Cette action est définitive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restaurer'),
          ),
        ],
      ),
    );
    if (step2 != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final wallet = ref.read(walletControllerProvider).value;
    if (wallet == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Aucun portefeuille actif.')));
      return;
    }
    try {
      final result = await PeriodRepository.instance.restore(wallet.id, period.id);
      ref.read(walletControllerProvider.notifier).setWallet(result.wallet);
      ref.invalidate(transactionsProvider);
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(budgetsControllerProvider);
      ref.invalidate(statsControllerProvider);
      await ref.read(periodsHistoryProvider.notifier).refresh();
      messenger.showSnackBar(SnackBar(content: Text('$monthLabel restaurée')));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(WalletController.messageFrom(e))),
      );
    }
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  '),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
