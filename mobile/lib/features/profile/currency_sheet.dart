import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/money.dart';
import '../../providers/currency_provider.dart';
import '../../services/currency_service.dart';

/// Panneau de sélection de la devise (Profil → Devise).
///
/// - 3 devises uniquement : Franc CFA (XOF) par défaut, Euro (EUR), Dollar (USD) ;
/// - la date de dernière mise à jour du taux USD est affichée (taux réel ou
///   taux de secours en dur hors ligne) ;
/// - au changement : confirmation « Les montants seront convertis au taux du jour ».
class CurrencySheet extends ConsumerStatefulWidget {
  const CurrencySheet({super.key});

  @override
  ConsumerState<CurrencySheet> createState() => _CurrencySheetState();
}

class _CurrencySheetState extends ConsumerState<CurrencySheet> {
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    // Rafraîchissement discret du taux à l'ouverture (best effort).
    Future.microtask(_refreshUsdRate);
  }

  Future<void> _refreshUsdRate() async {
    if (!mounted) return;
    setState(() => _refreshing = true);
    await ref.read(currencyControllerProvider.notifier).refreshUsdRate();
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _pick(String code) async {
    final current = ref.read(currencyControllerProvider).code;
    if (code == current) {
      Navigator.of(context).pop();
      return;
    }
    // Confirmation courte au changement de devise.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Changer de devise'),
        content: const Text('Les montants seront convertis au taux du jour'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Changer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(currencyControllerProvider.notifier).setCurrency(code);
    if (code == 'USD') {
      // Taux le plus frais possible juste après le basculement.
      await ref.read(currencyControllerProvider.notifier).refreshUsdRate();
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(currencyControllerProvider);
    final eurXof = CurrencyService.xofPerUnit('EUR');
    final usdXof = CurrencyService.xofPerUnit('USD');

    String usdUpdateLine() {
      final at = state.usdUpdatedAt;
      if (state.usdIsFallback && at == null) {
        return 'Taux USD de secours (hors ligne) — taux du jour non récupéré';
      }
      if (at == null) {
        return 'Taux USD de secours (hors ligne)';
      }
      final date = '${at.day.toString().padLeft(2, '0')}/${at.month.toString().padLeft(2, '0')}/${at.year}';
      return state.usdIsFallback
          ? 'Taux USD de secours — dernière mise à jour : $date'
          : 'Taux USD mis à jour le $date';
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Devise',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const Spacer(),
                if (_refreshing)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    tooltip: 'Actualiser le taux USD',
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    onPressed: _refreshUsdRate,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Les montants sont stockés en XOF et convertis à l’affichage.',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            for (final code in supportedCurrencies)
              _CurrencyTile(
                code: code,
                selected: code == state.code,
                onTap: () => _pick(code),
              ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: scheme.outline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '1 EUR = ${eurXof.toStringAsFixed(3)} XOF (parité fixe officielle)',
                    style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '1 USD ≈ ${usdXof.toStringAsFixed(2)} XOF — ${usdUpdateLine()}',
                    style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrencyTile extends StatelessWidget {
  const _CurrencyTile({required this.code, required this.selected, required this.onTap});

  final String code;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? scheme.primary.withValues(alpha: 0.08) : scheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? scheme.primary : scheme.outline),
            ),
            child: Row(
              children: [
                Text(
                  currencySymbol(code),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    currencyLabels[code] ?? code,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                if (selected) Icon(Icons.check_circle, color: scheme.primary, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
