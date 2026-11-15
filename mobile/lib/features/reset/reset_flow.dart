import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/period.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/api_client.dart';
import '../../services/outbox.dart';
import '../../services/period_repository.dart';
import '../../services/wallet_repository.dart';
import '../../providers/sync_provider.dart';

/// Double confirmation de remise à zéro — utilisée depuis Profil et depuis
/// le menu (⋯) de la carte budget de l'Accueil.
///
/// Étapes :
/// 1. dialogue listant précisément ce qui sera remis à zéro (+ case épargne) ;
/// 2. dialogue de confirmation définitive ;
/// 3. remise à zéro (archive d'abord, la période part dans l'historique) ;
/// 4. annulation possible pendant 10 secondes.
Future<void> showResetAllFlow(BuildContext context, WidgetRef ref) async {
  final wallet = ref.read(walletControllerProvider).value;
  if (wallet == null) {
    _snack(context, 'Aucun portefeuille actif.');
    return;
  }

  // Détecte la version du serveur : l'ancienne ne connaît pas /periods et son
  // /reset DÉTRUIT TOUT (pas d'archivage ni annulation). On propose alors un
  // effacement définitif explicite.
  final messenger = ScaffoldMessenger.of(context);
  var legacyServer = false;
  try {
    await ApiClient.instance.dio.head(
      '/wallets/${wallet.id}/periods',
      options: Options(
        receiveTimeout: const Duration(seconds: 20),
        connectTimeout: const Duration(seconds: 20),
      ),
    );
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) legacyServer = true;
    // Autre erreur réseau : l'application continuera hors-ligne (en file d'attente).
  } on TimeoutException {
    messenger.showSnackBar(const SnackBar(content: Text('Serveur lent — réessaie dans un instant.')));
    return;
  }

  if (legacyServer) {
    if (!context.mounted) return;
    await _legacyServerReset(context, ref, wallet.id);
    return;
  }

  // ---------- Confirmation 1 : ce qui sera remis à zéro ----------
  if (!context.mounted) return;
  var includeSavings = false;
  final step1 = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Réinitialiser tout à 0 ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Voilà ce qui se passera :'),
            const SizedBox(height: 10),
            const _Bullet('Tes opérations seront ARCHIVÉES dans l’historique (rien n’est supprimé)'),
            const _Bullet('Le budget du mois repart de zéro (dépenses et revenus archivés)'),
            const _Bullet('Ton solde actuel sera remis à zéro'),
            const _Bullet('Tes budgets et objectifs sont conservés, mais leurs compteurs repartent à zéro'),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: includeSavings,
              onChanged: (v) => setDialogState(() => includeSavings = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text('Remettre aussi l’épargne à 0'),
              subtitle: const Text('Sinon, ton épargne est conservée'),
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
    ),
  );
  if (step1 != true || !context.mounted) return;

  // ---------- Confirmation 2 : définitive ----------
  final step2 = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Dernière confirmation'),
      content: Text(
        includeSavings
            ? 'Ton solde ET ton épargne vont être remis à zéro. Cette action n’efface pas l’historique : la période en cours sera archivée.'
            : 'Ton solde va être remis à zéro. Ton épargne est conservée. La période en cours sera archivée (historique conservé).',
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
          child: const Text('Tout remettre à 0'),
        ),
      ],
    ),
  );
  if (step2 != true || !context.mounted) return;

  // ---------- Exécution ----------
  try {
    final result = await PeriodRepository.instance.reset(wallet.id, includeSavings: includeSavings);
    await _applyServerReset(ref, result);
    if (!context.mounted) return;
    _snack(context, includeSavings ? 'Portefeuille et épargne remis à zéro' : 'Portefeuille remis à zéro (épargne conservée)');
    _offerUndo(context, ref, wallet.id, result.period.id);
  } on DioException catch (e) {
    if (_isNetworkish(e)) {
      // Hors-ligne : l'opération attendra le retour du réseau, l'écran est déjà à jour.
      await Outbox.instance.createResetBackup(wallet.id);
      await Outbox.instance.applyResetLocally(wallet.id, includeSavings: includeSavings);
      await Outbox.instance.enqueueReset(wallet.id, includeSavings: includeSavings);
      _invalidateAll(ref);
      await ref.read(syncInfoProvider.notifier).refresh();
      if (!context.mounted) return;
      _snack(context, 'Remise à zéro enregistrée — elle sera synchronisée au retour du réseau');
      _offerUndoLocal(context, ref, wallet.id);
      return;
    }
    final data = e.response?.data;
    final message = (data is Map && data['error'] is Map && (data['error'] as Map)['message'] is String)
        ? (data['error'] as Map)['message'] as String
        : 'Synchronisation indisponible — réessayez';
    if (!context.mounted) return;
    _snack(context, message);
  }
}

bool _isNetworkish(DioException e) {
  final status = e.response?.statusCode;
  if (status == null) return true;
  return status >= 500;
}

/// Après une remise à zéro confirmée par le serveur : la période archivée
/// reste dans l'historique, on recharge tout proprement.
Future<void> _applyServerReset(WidgetRef ref, PeriodTransition result) async {
  ref.read(walletControllerProvider.notifier).setWallet(result.wallet);
  _invalidateAll(ref);
  await ref.read(syncInfoProvider.notifier).refresh();
}

void _invalidateAll(WidgetRef ref) {
  ref.invalidate(transactionsProvider);
  ref.invalidate(dashboardControllerProvider);
  ref.invalidate(budgetsControllerProvider);
  ref.invalidate(statsControllerProvider);
}

void _offerUndo(BuildContext context, WidgetRef ref, String walletId, String? newPeriodId) {
  if (newPeriodId == null) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(
      content: const Text('Période archivée — annulation possible pendant 10 secondes'),
      duration: const Duration(seconds: 10),
      action: SnackBarAction(
        label: 'Annuler',
        onPressed: () async {
          try {
            // Le backend attend l'identifiant de la NOUVELLE période active créée par le reset.
            final result = await PeriodRepository.instance.undo(walletId, newPeriodId);
            ref.read(walletControllerProvider.notifier).setWallet(result.wallet);
            _invalidateAll(ref);
            messenger.showSnackBar(const SnackBar(content: Text('Remise à zéro annulée')));
          } catch (_) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Annulation impossible (délai dépassé)')),
            );
          }
        },
      ),
    ),
  );
}

void _offerUndoLocal(BuildContext context, WidgetRef ref, String walletId) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(
      content: const Text('Remise à zéro enregistrée — annulation possible pendant 10 secondes'),
      duration: const Duration(seconds: 10),
      action: SnackBarAction(
        label: 'Annuler',
        onPressed: () async {
          try {
            final restored = await Outbox.instance.restoreResetBackup(walletId);
            if (restored) {
              _invalidateAll(ref);
              await ref.read(syncInfoProvider.notifier).refresh();
              messenger.showSnackBar(const SnackBar(content: Text('Remise à zéro annulée')));
            } else {
              messenger.showSnackBar(
                const SnackBar(content: Text('Annulation impossible (délai dépassé)')),
              );
            }
          } catch (_) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Annulation impossible (délai dépassé)')),
            );
          }
        },
      ),
    ),
  );
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
/// Mode « serveur obsolète » : effacement total et DÉFINITIF, sans archivage.
/// Affiché en clair pour la sécurité des données : l'utilisateur sait ce qu'il perd.
Future<void> _legacyServerReset(BuildContext context, WidgetRef ref, String walletId) async {
  final messenger = ScaffoldMessenger.of(context);

  final step1 = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Tout effacer définitivement ?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text('Cette version du serveur est ancienne. La remise à zéro efface DÉFINITIVEMENT :'),
          SizedBox(height: 8),
          _Bullet('toutes tes opérations (historique inclus)'),
          _Bullet('tous tes budgets et tes objectifs'),
          _Bullet('ton épargne'),
          _Bullet('le montant initial et son historique'),
          SizedBox(height: 8),
          Text(
            'Aucune restauration possible.',
            style: TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.w700),
          ),
        ],
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
          child: const Text('Tout effacer'),
        ),
      ],
    ),
  );
  if (step1 != true || !context.mounted) return;

  final step2 = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Dernière confirmation'),
      content: const Text(
        'Cela effacera DÉFINITIVEMENT ton budget, tes opérations et ton épargne. Aucune annulation possible.',
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
          child: const Text('Tout effacer définitivement'),
        ),
      ],
    ),
  );
  if (step2 != true || !context.mounted) return;

  try {
    final wallet = await WalletRepository.instance.hardReset(walletId);
    if (wallet == null) {
      messenger.showSnackBar(const SnackBar(content: Text('La remise à zéro a échoué. Réessaie.')));
      return;
    }
    ref.read(walletControllerProvider.notifier).setWallet(wallet);
    _invalidateAll(ref);
    await ref.read(syncInfoProvider.notifier).refresh();
    messenger.showSnackBar(const SnackBar(content: Text('Portefeuille effacé définitivement')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(WalletController.messageFrom(e))));
  }
}
