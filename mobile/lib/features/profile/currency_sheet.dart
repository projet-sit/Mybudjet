import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/money.dart';
import '../../providers/currency_provider.dart';

/// Panneau de sélection de la devise (Profil → Devise).
///
/// - 3 devises uniquement : Franc CFA (XOF) par défaut, Euro (EUR), Dollar (USD) ;
/// - affichage uniquement du nom et du symbole de chaque devise ;
/// - les taux sont rafraîchis en arrière-plan, rien n'est affiché à ce sujet ;
/// - au changement : confirmation « Les montants seront convertis au taux du jour ».
class CurrencySheet extends ConsumerWidget {
  const CurrencySheet({super.key});

  Future<void> _pick(BuildContext context, WidgetRef ref, String code) async {
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
      // Taux le plus frais possible juste après le basculement — silencieux.
      unawaited(ref.read(currencyControllerProvider.notifier).refreshUsdRate());
    }
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(currencyControllerProvider);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Devise',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            for (final code in supportedCurrencies)
              _CurrencyTile(
                code: code,
                selected: code == state.code,
                onTap: () => _pick(context, ref, code),
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
