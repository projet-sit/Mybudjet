import 'package:flutter/material.dart';

import '../core/search/highlight.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/date_format.dart';
import '../core/utils/money.dart';
import '../models/transaction.dart';

/// Couleur neutre pour les opérations d'épargne (ni rouge dépense, ni vert revenu).
const Color savingsNeutral = Color(0xFF64748B);

/// Icône par catégorie (dépenses + revenus + épargne).
IconData categoryIcon(String category, bool isExpense) {
  if (category == 'Épargne') return Icons.savings_outlined;
  if (!isExpense) {
    switch (category) {
      case 'Salaire':
        return Icons.work;
      case 'Business':
        return Icons.storefront;
      case 'Cadeau':
        return Icons.redeem;
      case 'Bourse':
        return Icons.school;
      default:
        return Icons.attach_money;
    }
  }
  switch (category) {
    case 'Alimentation':
      return Icons.restaurant;
    case 'Transport':
      return Icons.directions_car;
    case 'Logement':
      return Icons.home;
    case 'Santé':
      return Icons.favorite;
    case 'Études':
      return Icons.school;
    case 'Communication':
      return Icons.chat_bubble;
    case 'Loisirs':
      return Icons.sports_esports;
    case 'Shopping':
      return Icons.shopping_bag;
    case 'Abonnements':
      return Icons.subscriptions;
    case 'Famille':
      return Icons.family_restroom;
    default:
      return Icons.more_horiz;
  }
}

/// « Aujourd'hui », « Hier » ou date française.
String relativeDateLabel(String isoDate) => DateFormatUtil.relativeDayLabel(isoDate);

/// Libellé type d'une opération (pour la recherche et les détails).
String transactionTypeLabel(Transaction tx) {
  if (tx.isExpense) return 'Dépense';
  if (tx.isIncome) return 'Revenu';
  return 'Épargne';
}

/// Titre affiché : note si elle existe, sinon catégorie.
String transactionTitle(Transaction tx) {
  final note = tx.description?.trim() ?? '';
  return note.isNotEmpty ? note : tx.category;
}

/// Sous-titre : « catégorie · date » — ou seulement la date si le titre EST déjà la catégorie.
String transactionSubtitle(Transaction tx) {
  final date = DateFormatUtil.formatDateTime(tx.date, tx.time);
  final note = tx.description?.trim() ?? '';
  if (note.isNotEmpty && tx.category.trim().isNotEmpty) {
    return '${tx.category} · $date';
  }
  return date;
}

/// Ligne de transaction (maquette : icône douce, nom, catégorie · date, montant).
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.transaction,
    this.onTap,
    this.highlight,
  });

  final Transaction transaction;
  final VoidCallback? onTap;

  /// Texte à surligner dans le titre et le sous-titre (recherche).
  final String? highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isExpense = transaction.isExpense;
    final isSavings = transaction.isSavings;
    final title = transactionTitle(transaction);
    final subtitle = transactionSubtitle(transaction);

    final accent = isExpense
        ? scheme.error
        : isSavings
            ? savingsNeutral
            : AppColors.incomeGreen;
    final sign = isSavings ? '' : (isExpense ? '−' : '+');
    final iconBg = isSavings
        ? savingsNeutral.withValues(alpha: 0.12)
        : scheme.primary.withValues(alpha: 0.12);
    final iconColor = isSavings ? savingsNeutral : scheme.primary;
    final query = highlight?.trim() ?? '';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                categoryIcon(transaction.category, isExpense),
                size: 20,
                color: iconColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: query.isEmpty
                          ? [TextSpan(text: title)]
                          : highlightMatches(
                              title,
                              query,
                              highlightStyle: TextStyle(
                                backgroundColor: scheme.primary.withValues(alpha: 0.28),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      children: query.isEmpty
                          ? [TextSpan(text: subtitle)]
                          : highlightMatches(
                              subtitle,
                              query,
                              highlightStyle: TextStyle(
                                backgroundColor: scheme.primary.withValues(alpha: 0.28),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$sign${formatMoneyCurrent(transaction.amount, withCurrency: false)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
