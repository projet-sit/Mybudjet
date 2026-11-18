import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/app_feedback.dart';
import '../../models/dashboard.dart';
import '../../models/transaction.dart';
import '../../models/wallet.dart';
import '../../providers/shell_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/cache_service.dart';
import '../../services/transaction_pdf_export_service.dart';
import '../../widgets/transaction_tile.dart';
import '../reset/reset_flow.dart';
import '../transactions/transaction_detail_sheet.dart';

/// Accueil (maquette « MyBudget ») : salutation, solde, revenus/dépenses,
/// budget du mois, actions rapides, épargne, dernières opérations.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Bonjour';
    if (hour < 18) return 'Bon après-midi';
    return 'Bonsoir';
  }

  void _openDetail(BuildContext context, Transaction tx) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => TransactionDetailSheet(transaction: tx),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final wallet = ref.read(walletControllerProvider).value;
    if (wallet == null) return;
    try {
      // Export PDF (comme avant), généré à partir du backend réel (repli : cache local).
      final path = await TransactionPdfExportService.export(
        walletId: wallet.id,
        walletName: wallet.name,
        displayName: ref.read(authControllerProvider).value?.user.displayName,
      );
      await CacheService.instance.shareFile(path);
      if (context.mounted) {
        await showSuccessDialog(
          context,
          message: 'Votre relevé des opérations a été généré.',
        );
      }
    } catch (e) {
      if (context.mounted) showErrorSnackBar(context, TransactionsController.messageFrom(e));
    }
  }


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final walletState = ref.watch(walletControllerProvider);
    final dashboardState = ref.watch(dashboardControllerProvider);
    final sync = ref.watch(syncInfoProvider);
    final notice = ref.watch(syncNoticeProvider);
    final offline = sync.isOffline;
    final pending = sync.isPending;
    final wallet = walletState.value;

    if (walletState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(walletControllerProvider.notifier).refresh();
        await ref.read(dashboardControllerProvider.notifier).refresh();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          if (notice != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.sync_problem_rounded, size: 18, color: scheme.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${notice.failedCount} opération${notice.failedCount > 1 ? 's' : ''} non synchronisée${notice.failedCount > 1 ? 's' : ''}. ${notice.message}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.error),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Réessayer',
                    icon: Icon(Icons.refresh_rounded, size: 18, color: scheme.error),
                    onPressed: () async {
                      await ref.read(transactionsProvider.notifier).refreshAll();
                      if (context.mounted &&
                          ref.read(syncNoticeProvider) == null) {
                        await showSuccessDialog(
                          context,
                          message: 'Toutes vos opérations sont synchronisées.',
                          duration: const Duration(milliseconds: 1500),
                        );
                      }
                    },
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Ignorer',
                    icon: Icon(Icons.close_rounded, size: 18, color: scheme.error),
                    onPressed: () => ref.read(syncNoticeProvider.notifier).clear(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (offline || pending) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(
                    offline ? Icons.wifi_off_rounded : Icons.cloud_sync_outlined,
                    size: 18,
                    color: const Color(0xFFD97706),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      offline
                          ? 'Hors ligne — dernières données connues'
                          : '${sync.pendingCount} opération${sync.pendingCount > 1 ? 's' : ''} en attente de synchronisation',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFB45309),
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.refresh_rounded, size: 18, color: Color(0xFFB45309)),
                    onPressed: () async {
                      await ref.read(transactionsProvider.notifier).refreshAll();
                      await ref.read(walletControllerProvider.notifier).refresh();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          if (wallet != null)
            _HeroCard(
              wallet: wallet,
              dashboard: dashboardState.value,
              greeting: _greeting(),
              onAvatarTap: () => ref.read(shellTabProvider.notifier).set(3),
            )
          else if (walletState.hasError)
            _ErrorCard(
              message: 'Pas de connexion — impossible de récupérer tes données. Réessaie quand internet sera disponible.',
              onRetry: () => ref.read(walletControllerProvider.notifier).refresh(),
            )          else
            _NoWalletCard(onCreate: () => context.go('/wallet-setup')),

          if (wallet != null) ...[
            const SizedBox(height: 14),
            if (dashboardState.value != null)
              _BudgetCard(dashboard: dashboardState.value!, wallet: wallet),
            const SizedBox(height: 18),
            Row(
              children: [
                _QuickAction(
                  icon: Icons.bar_chart_rounded,
                  label: 'Stats',
                  onTap: () => context.push('/stats'),
                ),
                _QuickAction(
                  icon: Icons.ios_share_rounded,
                  label: 'Export',
                  onTap: sync.isOffline ? null : () => _export(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SavingsCard(wallet: wallet, onTap: () => context.push('/savings')),
            const SizedBox(height: 18),
            Row(
              children: [
                Text(
                  'Dernières opérations',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: scheme.onSurface),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => ref.read(shellTabProvider.notifier).set(1),
                  child: const Text('Tout voir'),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: scheme.outline),
              ),
              child: dashboardState.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    TransactionsController.messageFrom(error),
                    style: TextStyle(color: scheme.error, fontSize: 12),
                  ),
                ),
                data: (dashboard) {
                  final items = dashboard?.latestTransactions ?? const [];
                  if (items.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Column(
                        children: [
                          Icon(Icons.receipt_long_outlined, size: 36, color: scheme.onSurfaceVariant),
                          const SizedBox(height: 8),
                          Text(
                            'Aucune opération pour le moment',
                            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0) Divider(height: 1, indent: 66, color: scheme.outline),
                        TransactionTile(
                          transaction: items[i],
                          onTap: () => _openDetail(context, items[i]),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.wallet,
    required this.dashboard,
    required this.greeting,
    required this.onAvatarTap,
  });

  final Wallet wallet;
  final DashboardData? dashboard;
  final String greeting;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final initial = wallet.name.trim().isEmpty ? 'M' : wallet.name.trim()[0].toUpperCase();
    final available = (wallet.balance - wallet.savingsAmount).clamp(0, wallet.balance);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.deepGreenLight, AppColors.deepGreen, AppColors.deepGreenDark],
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepGreen.withValues(alpha: 0.25),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greeting,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      wallet.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onAvatarTap,
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Reste', style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatMoneyCurrent(available),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Pill(
                  icon: Icons.arrow_downward_rounded,
                  label: 'Revenus',
                  amount: dashboard?.totalIncomes ?? 0,
                  iconColor: const Color(0xFF34D399),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Pill(
                  icon: Icons.arrow_upward_rounded,
                  label: 'Dépenses',
                  amount: dashboard?.totalExpenses ?? 0,
                  iconColor: const Color(0xFFFDA4AF),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.amount,
    required this.iconColor,
  });

  final IconData icon;
  final String label;
  final int amount;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: iconColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white70, fontSize: 9.5)),
                Text(
                  formatMoneyCurrent(amount, withCurrency: false),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetCard extends ConsumerWidget {
  const _BudgetCard({required this.dashboard, this.wallet});

  final DashboardData dashboard;
  final Wallet? wallet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final savings = wallet?.savingsAmount ?? 0;
    final base = dashboard.initialAmount + dashboard.totalIncomes - savings;
    final computedBase = base < 0 ? 0 : base;
    final percent = computedBase > 0 ? ((dashboard.totalExpenses / computedBase) * 100).round().clamp(0, 100) : 0;
    final remaining = (computedBase - dashboard.totalExpenses).clamp(0, computedBase);
    final progress = computedBase > 0 ? (dashboard.totalExpenses / computedBase).clamp(0.0, 1.0) : 0.0;
    final color = percent >= 80 ? scheme.error : scheme.primary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outline),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: CircularProgressIndicator(
                    value: percent / 100,
                    strokeWidth: 8,
                    strokeCap: StrokeCap.round,
                    backgroundColor: scheme.outline,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                Text(
                  '$percent%',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Budget du mois',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: scheme.onSurface),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Options',
                      iconSize: 20,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 32),
                      icon: Icon(Icons.more_horiz_rounded, color: scheme.onSurfaceVariant, size: 20),
                      onSelected: (value) async {
                        if (value == 'reset') {
                          await showResetAllFlow(context, ref);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'reset',
                          child: Text('Supprimer tout'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatMoneyCurrent(dashboard.totalExpenses)} dépensés sur ${formatMoneyCurrent(computedBase)}',
                  style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 7,
                    backgroundColor: scheme.outline,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Encore ${formatMoneyCurrent(remaining)}',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: scheme.primary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 22, color: scheme.primary),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavingsCard extends StatelessWidget {
  const _SavingsCard({required this.wallet, required this.onTap});

  final Wallet wallet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primary.withValues(alpha: 0.14), scheme.primary.withValues(alpha: 0.05)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.savings_outlined, color: scheme.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mon épargne',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatMoneyCurrent(wallet.savingsAmount),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: scheme.primary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Reste à dépenser : ${formatMoneyCurrent(wallet.available)}',
                    style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    );
  }
}

class _NoWalletCard extends StatelessWidget {
  const _NoWalletCard({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outline),
      ),
      child: Column(
        children: [
          Icon(Icons.wallet_outlined, size: 56, color: scheme.primary),
          const SizedBox(height: 12),
          Text(
            'Commençons par ton budget',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: scheme.onSurface),
          ),
          const SizedBox(height: 6),
          Text(
            "Combien d'argent as-tu actuellement à disposition ?",
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: onCreate, child: const Text('Créer mon portefeuille')),
        ],
      ),
    );
  }
}
