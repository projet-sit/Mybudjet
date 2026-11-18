import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';
import '../../providers/currency_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/profile_photo_provider.dart';
import '../../services/auth_repository.dart';
import '../../models/user.dart';
import '../../core/widgets/app_feedback.dart';
import '../../services/cache_service.dart';
import '../../services/currency_service.dart';
import '../../services/outbox.dart';
import '../../services/transaction_pdf_export_service.dart';

/// « Supprimer tout » (Profil → Zone de danger, et menu ⋯ de la carte budget).
///
/// Déroulement (spec) :
/// 1. dialogue « Télécharger mes données en PDF » / « Supprimer sans télécharger »
///    / « Annuler » — le PDF est généré et partagé, puis on revient au dialogue ;
/// 2. confirmation finale : « Cette action est irréversible. Toutes vos
///    opérations, catégories personnalisées et préférences seront supprimées. » ;
/// 3. suppression effective : serveur (opérations, catégories personnalisées,
///    portefeuilles, épargne, budgets — atomique) + caches locaux + devise
///    remise sur XOF ; l'app repart de l'état initial.
///
/// Le serveur est la source de vérité : le client vide tout localement pour
/// qu'aucune ancienne opération ne puisse ressusciter.
Future<void> showResetAllFlow(BuildContext context, WidgetRef ref) async {
  // Réseau obligatoire : la suppression est une opération serveur.
  if (ref.read(offlineProvider)) {
    _snack(context, 'Connexion requise pour tout supprimer');
    return;
  }

  final wallet = ref.read(walletControllerProvider).value;
  if (wallet == null) {
    _snack(context, 'Aucun portefeuille actif.');
    return;
  }

  // Étape 1 : dialogue de choix — boucle tant que l'utilisateur télécharge le PDF.
  var wantsDelete = false;
  while (context.mounted) {
    final choice = await showDialog<DeleteChoice>(
      context: context,
      builder: (_) => DownloadOrDeleteDialog(
        onDownloadPdf: () async {
          await _exportPdf(context, ref, wallet.id, wallet.name);
        },
      ),
    );
    if (choice == DeleteChoice.deleteWithoutDownload) {
      wantsDelete = true;
      break;
    }
    if (choice == DeleteChoice.downloaded) {
      // Le PDF vient d'être partagé : on reste sur le dialogue.
      continue;
    }
    // Annuler (ou fermeture) : rien n'est supprimé.
    return;
  }
  if (!wantsDelete || !context.mounted) return;

  // Étape 2 : confirmation finale, irréversible.
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => const FinalDeleteConfirmDialog(),
  );
  if (confirmed != true || !context.mounted) return;

  // Étape serveur (atomique).
  final AuthSession session;
  try {
    session = await AuthRepository.instance.resetAccount();
  } catch (_) {
    if (!context.mounted) return;
    _snack(context, 'Suppression impossible. Vérifie ta connexion puis réessaie.');
    return;
  }
  // La session stockée porte le nouveau data_epoch : on l'installe dans le
  // contrôleur pour éviter une détection de changement fantôme.
  ref.read(authControllerProvider.notifier).setSession(session);

  // Étape locale : on vide tout (cache + file d'attente + photo locale),
  // puis on remet la devise sur XOF (les préférences ont été purgées).
  await CacheService.instance.clearAllCaches();
  await CurrencyService.instance.setCurrent('XOF');
  await Outbox.instance.clearAll();
  await ref.read(profilePhotoProvider.notifier).clear();
  ref.invalidate(walletControllerProvider);
  ref.invalidate(dashboardControllerProvider);
  ref.invalidate(transactionsProvider);
  ref.invalidate(budgetsControllerProvider);
  ref.invalidate(statsControllerProvider);
  ref.invalidate(categoriesProvider);
  ref.invalidate(currencyControllerProvider);
  await ref.read(syncInfoProvider.notifier).refresh();
  await ref.read(authControllerProvider.notifier).revalidate();

  if (!context.mounted) return;
  await showSuccessDialog(context);
  if (!context.mounted) return;
  // L'app repart de zéro : création du premier portefeuille (comme après
  // inscription), pas les 3 écrans d'introduction.
  context.go('/wallet-setup');
}

enum DeleteChoice { deleteWithoutDownload, downloaded }

/// Génère et partage le PDF du relevé. En cas d'erreur réseau, le cache local
/// est utilisé en repli (le PDF reste générable hors ligne).
Future<void> _exportPdf(
  BuildContext context,
  WidgetRef ref,
  String walletId,
  String walletName,
) async {
  try {
    final path = await TransactionPdfExportService.export(
      walletId: walletId,
      walletName: walletName,
      displayName: ref.read(authControllerProvider).value?.user.displayName,
    );
    await CacheService.instance.shareFile(path);
  } catch (_) {
    if (context.mounted) {
      showErrorSnackBar(context, 'Export PDF impossible. Vérifie ta connexion puis réessaie.');
    }
  }
}

void _snack(BuildContext context, String message) {
  showErrorSnackBar(context, message);
}

/// Dialogue étape 1 : télécharger le PDF, supprimer sans télécharger, ou annuler.
/// [onDownloadPdf] est appelé pour générer puis partager le PDF ; le dialogue
/// reste ouvert ensuite (l'utilisateur supprime quand il veut).
class DownloadOrDeleteDialog extends StatefulWidget {
  const DownloadOrDeleteDialog({super.key, required this.onDownloadPdf});

  final Future<void> Function() onDownloadPdf;

  @override
  State<DownloadOrDeleteDialog> createState() => _DownloadOrDeleteDialogState();
}

class _DownloadOrDeleteDialogState extends State<DownloadOrDeleteDialog> {
  bool _exporting = false;

  Future<void> _download() async {
    setState(() => _exporting = true);
    try {
      await widget.onDownloadPdf();
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
    // Après partage du PDF, on revient au dialogue : la boucle
    // [showResetAllFlow] rouvre une occurrence de ce dialogue.
    if (mounted) Navigator.of(context).pop(DeleteChoice.downloaded);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Supprimer tout ?'),
      content: const Text(
        'Toutes tes opérations, catégories personnalisées et préférences seront supprimées.',
      ),
      actions: [
        TextButton(
          onPressed: _exporting ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        OutlinedButton.icon(
          onPressed: _exporting ? null : _download,
          icon: _exporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_outlined, size: 18),
          label: const Text('Télécharger mes données en PDF'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error),
          onPressed: _exporting
              ? null
              : () => Navigator.of(context).pop(DeleteChoice.deleteWithoutDownload),
          child: const Text('Supprimer sans télécharger'),
        ),
      ],
    );
  }
}

/// Confirmation finale avant la suppression définitive (irréversible).
class FinalDeleteConfirmDialog extends StatelessWidget {
  const FinalDeleteConfirmDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Supprimer définitivement ?'),
      content: const Text(
        'Cette action est irréversible. Toutes vos opérations, catégories personnalisées et préférences seront supprimées.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Supprimer définitivement'),
        ),
      ],
    );
  }
}
