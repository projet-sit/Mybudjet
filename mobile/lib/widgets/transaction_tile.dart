import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/money.dart';
import '../models/transaction.dart';

/// Icône par catégorie (dépenses + revenus).
IconData categoryIcon(String category, bool isExpense) {
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
String relativeDateLabel(String isoDate) {
  final now = DateTime.now();
  final parsed = DateTime.tryParse(isoDate);
  if (parsed != null) {
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(parsed.year, parsed.month, parsed.day);
    final diff = today.difference(date).inDays;
    if (diff == 0) return "Aujourd'hui";
    if (diff == 1) return 'Hier';
  }
  return formatDateFr(isoDate);
}

/// Ligne de transaction (maquette : icône douce, nom, catégorie · date, montant).
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.transaction,
    this.onTap,
  });

  final Transaction transaction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isExpense = transaction.isExpense;
    final title = (transaction.description?.trim().isNotEmpty ?? false)
        ? transaction.description!.trim()
        : transaction.category;

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
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                categoryIcon(transaction.category, isExpense),
                size: 20,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${transaction.category} · ${formatDateTimeFr(transaction.date, transaction.time)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${isExpense ? '−' : '+'}${formatXof(transaction.amount, withCurrency: false)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: isExpense ? scheme.error : AppColors.incomeGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
