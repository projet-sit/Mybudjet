import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../providers/app_prefs_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/cache_service.dart';
import '../../services/sync_queue.dart';
import '../../services/transaction_pdf_export_service.dart';
/// Profil (maquette « MyBudget ») : compte, portefeuille, préférences,
/// export PDF, déconnexion.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _exporting = false;

  Future<void> _exportPdf() async {
    final wallet = ref.read(walletControllerProvider).value;
    if (wallet == null) return;
    setState(() => _exporting = true);
    try {
      final path = await TransactionPdfExportService.export(
        walletId: wallet.id,
        walletName: wallet.name,
        initialAmount: wallet.initialAmount,
        displayName: ref.read(authControllerProvider).value?.user.displayName,
      );
      await CacheService.instance.shareFile(path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Export PDF impossible. Vérifie ta connexion puis réessaie.')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = ref.watch(authControllerProvider).value?.user;
    final wallet = ref.watch(walletControllerProvider).value;
    final isDark = (ref.watch(themeControllerProvider).value ?? ThemeMode.light) == ThemeMode.dark;
    final alerts = ref.watch(alertsEnabledProvider).value ?? true;
    final initial = (user?.displayName.trim().isNotEmpty ?? false)
        ? user!.displayName.trim()[0].toUpperCase()
        : 'M';

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Text(
            'Profil',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: scheme.onSurface),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.deepGreenLight, AppColors.deepGreen],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initial,
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.displayName ?? 'Utilisateur MYBUDGET',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(
                      user?.email ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (wallet != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.deepGreenLight, AppColors.deepGreen, AppColors.deepGreenDark],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          wallet.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Solde : ${formatXof(wallet.balance)}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (wallet.hasSavings)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Épargne ${formatXof(wallet.savingsAmount, withCurrency: false)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 22),
          _sectionLabel(context, 'Préférences'),
          const SizedBox(height: 8),
          _card(
            context,
            children: [
              SwitchListTile.adaptive(
                value: isDark,
                onChanged: (value) => ref.read(themeControllerProvider.notifier).setDark(value),
                secondary: Icon(Icons.dark_mode_outlined, color: scheme.primary),
                title: const _TileTitle('Mode sombre'),
                subtitle: const _TileSubtitle('Confort visuel le soir'),
              ),
              Divider(height: 1, color: scheme.outline),
              SwitchListTile.adaptive(
                value: alerts,
                onChanged: (value) => ref.read(alertsEnabledProvider.notifier).setEnabled(value),
                secondary: Icon(Icons.notifications_outlined, color: scheme.primary),
                title: const _TileTitle('Alertes de budget'),
                subtitle: const _TileSubtitle('Prévenir à 50 %, 80 % et 100 %'),
              ),
              Divider(height: 1, color: scheme.outline),
              ListTile(
                leading: Icon(Icons.payments_outlined, color: scheme.primary),
                title: const _TileTitle('Devise'),
                subtitle: const _TileSubtitle('FCFA (XOF)'),
                trailing: Text(
                  'XOF',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _sectionLabel(context, 'Données'),
          const SizedBox(height: 8),
          _card(
            context,
            children: [
              ListTile(
                leading: Icon(Icons.savings_outlined, color: scheme.primary),
                title: const _TileTitle('Mon épargne'),
                subtitle: _TileSubtitle(
                  wallet == null
                      ? 'Crée d’abord ton budget'
                      : 'Mise de côté : ${formatXof(wallet.savingsAmount)}',
                ),
                enabled: wallet != null,
                trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                onTap: wallet == null ? null : () => context.push('/savings'),
              ),
              Divider(height: 1, color: scheme.outline),
              ListTile(
                leading: Icon(Icons.picture_as_pdf_outlined, color: scheme.primary),
                title: const _TileTitle('Exporter mes transactions'),
                subtitle: const _TileSubtitle('PDF — historique complet'),
                enabled: wallet != null,
                trailing: _exporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                onTap: wallet == null ? null : _exportPdf,
              ),
            ],
          ),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.error,
              side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Se déconnecter ?'),
                  content: const Text('Tes données resteront enregistrées sur le serveur.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Annuler'),
                    ),
                    FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Déconnexion'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await ref.read(authControllerProvider.notifier).logout();
              }
            },
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Se déconnecter'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.error,
              side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: _deleteAccount,
            icon: const Icon(Icons.delete_forever, size: 18),
            label: const Text('Supprimer mon compte et mes données'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _deleteAccount() async {
    final pending = await SyncQueue.instance.count();
    if (!mounted) return;
    if (pending > 0) {      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Opérations en attente'),
          content: const Text(
            'Des opérations ne sont pas encore synchronisées. Connectez-vous à internet avant de continuer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Continuer quand même'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }
    final results = await Connectivity().checkConnectivity();
    final offline = results.every((r) => r == ConnectivityResult.none);
    if (offline) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connectez-vous à internet pour supprimer votre compte.'),
        ),
      );
      return;
    }
    if (!mounted) return;    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer mon compte ?'),
        content: const Text(
          'Cette action est définitive. Vos données seront supprimées.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authControllerProvider.notifier).deleteAccount();
    }
  }
  Widget _sectionLabel(BuildContext context, String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _card(BuildContext context, {required List<Widget> children}) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _TileTitle extends StatelessWidget {
  const _TileTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700));
  }
}

class _TileSubtitle extends StatelessWidget {
  const _TileSubtitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}
