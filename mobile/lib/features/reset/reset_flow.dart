import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/profile_photo_provider.dart';
import '../../services/auth_repository.dart';
import '../../models/user.dart';
import '../../services/cache_service.dart';
import '../../services/outbox.dart';

/// Réinitialisation complète du compte ("comme neuf").
/// Utilisée depuis Profil (section Réinitialisation) et depuis le menu ⋯
/// de la carte budget de l'Accueil — même flux, une seule logique.
///
/// Le serveur supprime TOUT dans une seule transaction (atomique) et renvoie
/// l'état initial. Le client vide alors tout le cache local + la file à
/// synchroniser : aucune ancienne opération ne peut ressusciter de données.
Future<void> showResetAllFlow(BuildContext context, WidgetRef ref) async {
  // Réseau obligatoire : la réinitialisation est une opération serveur.
  if (ref.read(offlineProvider)) {
    _snack(context, 'Connexion requise pour réinitialiser');
    return;
  }

  final wallet = ref.read(walletControllerProvider).value;
  if (wallet == null) {
    _snack(context, 'Aucun portefeuille actif.');
    return;
  }

  final confirmed = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      fullscreenDialog: true,
      builder: (_) => const ResetScreen(),
    ),
  );
  if (confirmed != true || !context.mounted) return;

  // Étape serveur (atomique).
  final AuthSession session;
  try {
    session = await AuthRepository.instance.resetAccount();
  } catch (_) {
    if (!context.mounted) return;
    _snack(context, 'Réinitialisation impossible. Vérifie ta connexion puis réessaie.');
    return;
  }
  // La session stockée porte le nouveau data_epoch : on l'installe dans le
  // contrôleur pour éviter une détection de changement fantôme.
  ref.read(authControllerProvider.notifier).setSession(session);

  // Étape locale : on vide tout (cache + file d'attente + photo locale), puis on revalide.
  await CacheService.instance.clearAllCaches();
  await Outbox.instance.clearAll();
  await ref.read(profilePhotoProvider.notifier).clear();
  ref.invalidate(walletControllerProvider);
  ref.invalidate(dashboardControllerProvider);
  ref.invalidate(transactionsProvider);
  ref.invalidate(budgetsControllerProvider);
  ref.invalidate(statsControllerProvider);
  ref.invalidate(categoriesProvider);
  await ref.read(syncInfoProvider.notifier).refresh();
  await ref.read(authControllerProvider.notifier).revalidate();

  if (!context.mounted) return;
  // Le compte repart de zéro : création du premier portefeuille (après inscription),
  // pas les 3 écrans d'introduction.
  context.go('/wallet-setup');
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Écran de confirmation avec liste précise de ce qui sera supprimé,
/// proposition de télécharger une copie CSV avant, et confirmation forte
/// (le bouton n'est actif que si l'utilisateur tape « REINITIALISER »).
class ResetScreen extends ConsumerStatefulWidget {
  const ResetScreen({super.key});

  @override
  ConsumerState<ResetScreen> createState() => _ResetScreenState();
}

class _ResetScreenState extends ConsumerState<ResetScreen> {
  final _controller = TextEditingController();
  bool _exporting = false;
  bool _resetting = false;

  bool get _canReset => _controller.text.trim() == 'REINITIALISER';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _downloadCsv() async {
    final wallet = ref.read(walletControllerProvider).value;
    if (wallet == null) return;
    setState(() => _exporting = true);
    try {
      final path = await CacheService.instance.exportCsv(wallet.id);
      await CacheService.instance.shareFile(path);
    } catch (_) {
      if (mounted) {
        _snack('Export impossible. Vérifie ta connexion puis réessaie.');
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const items = <(String, IconData)>[
      ('Ton compte (téléphone, e-mail et mot de passe) est conservé', Icons.lock_outline),
      ('Tes portefeuilles — plus aucun solde', Icons.account_balance_wallet_outlined),
      ('Toutes tes opérations (dépenses, revenus)', Icons.swap_horiz),
      ('Ton épargne et son historique', Icons.savings_outlined),
      ('Tes budgets par catégorie', Icons.pie_chart_outline),
      ('Tes objectifs d’épargne', Icons.flag_outlined),
      ('Tes périodes archivées et leurs récapitulatifs', Icons.history),
      ('Tes catégories personnalisées (les défauts reviennent)', Icons.label_outline),
      ('Le cache local et les opérations en attente', Icons.cloud_off_outlined),
    ];

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: const Text('Réinitialiser tout'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Icon(Icons.warning_amber_rounded, size: 44, color: scheme.error),
            const SizedBox(height: 8),
            Text(
              'Tout sera supprimé définitivement',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Ton compte reste actif, comme un compte qui vient d’être créé. '
              'Cette action est irréversible.',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            for (final (text, icon) in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 18, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(text, style: TextStyle(fontSize: 13, color: scheme.onSurface)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _exporting ? null : _downloadCsv,
              icon: _exporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
              label: const Text('Télécharger une copie (CSV) avant'),
            ),
            const SizedBox(height: 16),
            Text(
              'Pour confirmer, tape REINITIALISER :',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurface),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _controller,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'REINITIALISER',
                border: const OutlineInputBorder(),
                suffixIcon: _canReset
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  disabledBackgroundColor: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                ),
                onPressed: (_canReset && !_resetting)
                    ? () {
                        setState(() => _resetting = true);
                        Navigator.of(context).pop(true);
                      }
                    : null,
                child: _resetting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Réinitialiser tout',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                      ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
