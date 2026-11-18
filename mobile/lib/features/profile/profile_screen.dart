import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/app_feedback.dart';
import '../../providers/app_prefs_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/currency_provider.dart';
import '../../providers/profile_photo_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/cache_service.dart';
import '../../services/outbox.dart';
import '../../services/budget_alerts_service.dart';
import '../../services/transaction_pdf_export_service.dart';
import 'currency_sheet.dart';
import '../reset/reset_flow.dart';
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
        displayName: ref.read(authControllerProvider).value?.user.displayName,
      );
      await CacheService.instance.shareFile(path);
      if (!mounted) return;
      await showSuccessDialog(
        context,
        message: 'Votre relevé des opérations a été généré.',
      );
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'Export PDF impossible. Vérifie ta connexion puis réessaie.');
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showCurrencyPicker() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const CurrencySheet(),
    );
  }

  Future<void> _contactSupport() async {
    // Le numéro n'apparaît nulle part dans l'UI : uniquement dans les constantes.
    try {
      final launched = await launchUrl(
        AppConstants.whatsappContactUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) _snack('Impossible d’ouvrir WhatsApp');
    } catch (_) {
      if (mounted) _snack('Impossible d’ouvrir WhatsApp');
    }
  }

  void _snack(String message) {
    showErrorSnackBar(context, message);
  }

  Future<void> _resetAll() => showResetAllFlow(context, ref);

  /// Sous-titre de la ligne Devise : nom + symbole de la devise active.
  String _currencySubtitle(CurrencyState state) => switch (state.code) {
        'EUR' => 'Euro (€)',
        'USD' => 'Dollar (\$)',
        _ => 'Franc CFA (FCFA)',
      };

  /// Interrupteur « Alertes de budget » : à l'activation, demande la permission
  /// POST_NOTIFICATIONS (Android 13+). En cas de refus, l'interrupteur reste coupé.
  Future<void> _toggleBudgetAlerts(bool value) async {
    if (value) {
      final granted = await BudgetAlertsService.instance.requestPermission();
      if (!mounted) return;
      if (!granted) {
        showWarningSnackBar(context, 'Notifications refusées. Autorise-les dans les réglages Android pour recevoir les alertes de budget.');
        return;
      }
    }
    await ref.read(alertsEnabledProvider.notifier).setEnabled(value);
  }

  Future<void> _pickPhoto(BuildContext context, ImageSource source) async {
    try {
      // Android : la caméra est une permission dangereuse → demande à chaud.
      if (source == ImageSource.camera) {
        final status = await Permission.camera.request();
        if (!status.isGranted) {
          if (!context.mounted) return;
          showErrorSnackBar(context, 'Caméra non autorisée. Autorise-la dans les réglages Android.');
          return;
        }
      }
      await ref.read(profilePhotoProvider.notifier).setFromPick(source);
      if (context.mounted) {
        await showSuccessDialog(
          context,
          message: 'Votre photo de profil a été mise à jour.',
          duration: const Duration(milliseconds: 1200),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      showErrorSnackBar(context, 'Photo impossible. Vérifie les autorisations de la galerie/caméra.');
    }
  }

  Future<void> _removePhoto() async {
    await ref.read(profilePhotoProvider.notifier).clear();
    if (mounted) {
      await showSuccessDialog(
        context,
        message: 'Votre photo de profil a été retirée.',
        duration: const Duration(milliseconds: 1200),
      );
    }
  }

  Future<void> _showPhotoOptions() async {
    final hasPhoto = ref.read(profilePhotoProvider).value != null;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir dans la galerie'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickPhoto(context, ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Prendre une photo'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickPhoto(context, ImageSource.camera);
              },
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Retirer la photo'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _removePhoto();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = ref.watch(authControllerProvider).value?.user;
    final wallet = ref.watch(walletControllerProvider).value;
    final currency = ref.watch(currencyControllerProvider);
    final isDark = (ref.watch(themeControllerProvider).value ?? ThemeMode.light) == ThemeMode.dark;
    final alerts = ref.watch(alertsEnabledProvider).value ?? true;
    final photoPath = ref.watch(profilePhotoProvider).value;
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
            Semantics(
              label: 'Photo de profil – toucher pour changer',
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(34),
                onTap: _showPhotoOptions,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppColors.deepGreenLight, AppColors.deepGreen],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: photoPath != null
                          ? ClipOval(
                              child: Image.file(
                                File(photoPath),
                                width: 68,
                                height: 68,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Text(
                                  initial,
                                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                                ),
                              ),
                            )
                          : Text(
                              initial,
                              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                            ),
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: scheme.surface,
                          border: Border.all(color: scheme.outline),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.photo_camera, size: 13, color: Colors.black87),
                        ),
                      ),
                    ),
                  ],
                ),
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
                      user?.identifier ?? '',
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
                          'Solde : ${formatMoneyCurrent(wallet.balance)}',
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
                        'Épargne ${formatMoneyCurrent(wallet.savingsAmount, withCurrency: false)}',
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
                onChanged: (value) => _toggleBudgetAlerts(value),
                secondary: Icon(Icons.notifications_outlined, color: scheme.primary),
                title: const _TileTitle('Alertes de budget'),
                subtitle: const _TileSubtitle('Notifier à 80 % et 100 % du budget'),
              ),
              Divider(height: 1, color: scheme.outline),
              ListTile(
                leading: Icon(Icons.payments_outlined, color: scheme.primary),
                title: const _TileTitle('Devise'),
                subtitle: _TileSubtitle(_currencySubtitle(currency)),
                trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                onTap: _showCurrencyPicker,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _sectionLabel(context, 'Données'),
          const SizedBox(height: 8),
          _card(
            context,
            children: [
              Divider(height: 1, color: scheme.outline),
              ListTile(
                leading: Icon(Icons.savings_outlined, color: scheme.primary),
                title: const _TileTitle('Mon épargne'),
                subtitle: _TileSubtitle(
                  wallet == null
                      ? 'Crée d’abord ton budget'
                      : 'Mise de côté : ${formatMoneyCurrent(wallet.savingsAmount)}',
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
          const SizedBox(height: 18),
          _sectionLabel(context, 'Assistance'),
          const SizedBox(height: 8),
          _card(
            context,
            children: [
              ListTile(
                leading: Icon(Icons.help_outline, color: scheme.primary),
                title: const _TileTitle('Aide et FAQ'),
                subtitle: const _TileSubtitle('Réponses aux questions fréquentes'),
                trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                onTap: () => context.push('/help'),
              ),
              Divider(height: 1, color: scheme.outline),
              ListTile(
                leading: Icon(Icons.policy_outlined, color: scheme.primary),
                title: const _TileTitle('Politique de confidentialité'),
                subtitle: const _TileSubtitle('Données collectées, stockage et vos droits'),
                trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                onTap: () => context.push('/privacy-policy'),
              ),
              Divider(height: 1, color: scheme.outline),
              ListTile(
                leading: Icon(Icons.chat_outlined, color: scheme.primary),
                title: const _TileTitle('Nous contacter'),
                subtitle: const _TileSubtitle('Poser votre question via WhatsApp'),
                trailing: Icon(Icons.open_in_new_rounded, color: scheme.onSurfaceVariant, size: 18),
                onTap: _contactSupport,
              ),
            ],
          ),
          const SizedBox(height: 22),
          _sectionLabel(context, 'Zone de danger'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.error,
              side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: _resetAll,
            icon: const Icon(Icons.delete_forever_outlined, size: 18),
            label: const Text('Supprimer tout'),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Toutes vos opérations, catégories personnalisées et préférences seront supprimées. Cette action est irréversible.',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 18),
          _sectionLabel(context, 'Compte'),
          const SizedBox(height: 8),
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
                try {
                  await ref.read(authControllerProvider.notifier).logout();
                } catch (_) {
                  // La déconnexion locale prime : on continue vers le login.
                  ref.invalidate(authControllerProvider);
                }
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
            label: const Text('Supprimer mes données'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _deleteAccount() async {
    final pending = await Outbox.instance.count();
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
      showWarningSnackBar(context, 'Connectez-vous à internet pour supprimer votre compte.');
      return;
    }
    if (!mounted) return;    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer définitivement ?'),
        content: const Text(
          'TOUTES tes données seront effacées (compte, portefeuille, opérations, budgets, épargne). '
          'Cette action est définitive et ne peut pas être annulée.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Supprimer définitivement'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(authControllerProvider.notifier).deleteAccount();
        if (!mounted) return;
        await showSuccessDialog(
          context,
          message: 'Votre compte et vos données ont été supprimés.',
        );
        if (mounted) context.go('/login');
      } catch (e) {
        if (!mounted) return;
        showErrorSnackBar(context, AuthController.messageFrom(e));
      }
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
