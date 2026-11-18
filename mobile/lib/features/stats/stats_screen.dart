import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/money.dart';
import '../../models/dashboard.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/wallet_provider.dart';

/// Statistiques (maquette « MyBudget ») : période, totaux, histogramme,
/// répartition par catégorie, épargne du mois.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  static const _periods = [('Semaine', 'week'), ('Mois', 'month'), ('Année', 'year')];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(statsControllerProvider);
    final wallet = ref.watch(walletControllerProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Statistiques')),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(TransactionsController.messageFrom(error), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.read(statsControllerProvider.notifier).setPeriod(
                        ref.read(statsControllerProvider.notifier).period,
                      ),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
        data: (stats) {
          if (stats == null) {
            return const Center(child: Text('Aucune donnée'));
          }
          final buckets = _buckets(stats);
          final maxBucket = buckets.fold<int>(1, (m, b) => b.value > m ? b.value : m);

          return RefreshIndicator(
            onRefresh: () async {
              await ref
                  .read(statsControllerProvider.notifier)
                  .setPeriod(ref.read(statsControllerProvider.notifier).period);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Row(
                  children: [
                    for (final (label, value) in _periods)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _chip(
                          context,
                          label,
                          stats.period == value,
                          () => ref.read(statsControllerProvider.notifier).setPeriod(value),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _summary(
                        context,
                        'Dépenses',
                        stats.periodExpenses,
                        scheme.error,
                        Icons.arrow_upward_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _summary(
                        context,
                        'Revenus',
                        stats.periodIncomes,
                        AppColors.incomeGreen,
                        Icons.arrow_downward_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_rounded, size: 16, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Moyenne : ${formatMoneyCurrent(stats.averageDaily)} / jour',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.primary),
                        ),
                      ),
                      if (stats.previousPeriodExpenses > 0)
                        Text(
                          stats.periodExpenses <= stats.previousPeriodExpenses ? '↓ mieux' : '↑ plus',
                          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _sectionTitle(context, 'Évolution'),
                const SizedBox(height: 10),
                Container(
                  height: 190,
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: scheme.outline),
                  ),
                  child: buckets.isEmpty
                      ? Center(
                          child: Text(
                            'Pas encore de dépenses sur la période',
                            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                          ),
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (final bucket in buckets)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 3),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        bucket.value == 0
                                            ? ''
                                            : formatMoneyCurrent(bucket.value, withCurrency: false),
                                        maxLines: 1,
                                        overflow: TextOverflow.clip,
                                        style: TextStyle(
                                          fontSize: 8,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        height: 110 * (bucket.value / maxBucket) + 4,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.bottomCenter,
                                            end: Alignment.topCenter,
                                            colors: [
                                              scheme.primary,
                                              scheme.primary.withValues(alpha: 0.5),
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        bucket.label,
                                        style: TextStyle(
                                          fontSize: 8.5,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 20),
                _sectionTitle(context, 'Par catégorie'),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: scheme.outline),
                  ),
                  child: stats.byCategory.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Aucune dépense catégorisée',
                            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                          ),
                        )
                      : Column(
                          children: [
                            for (var i = 0; i < stats.byCategory.take(6).length; i++) ...[
                              if (i > 0) const SizedBox(height: 14),
                              _categoryRow(context, stats.byCategory[i]),
                            ],
                          ],
                        ),
                ),
                const SizedBox(height: 20),
                _sectionTitle(context, 'Épargne'),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        scheme.primary.withValues(alpha: 0.14),
                        scheme.primary.withValues(alpha: 0.05),
                      ],
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
                              'Mis de côté',
                              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                            ),
                            Text(
                              formatMoneyCurrent(wallet?.savingsAmount ?? 0),
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: scheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Reste à dépenser',
                            style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                          ),
                          Text(
                            formatMoneyCurrent(wallet?.available ?? 0),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<({String label, int value})> _buckets(StatsData stats) {
    final points = stats.dailySeries;
    if (points.isEmpty) return [];
    final count = points.length <= 7 ? points.length : 6;
    final size = (points.length / count).ceil();
    final result = <({String label, int value})>[];
    for (var i = 0; i < points.length; i += size) {
      final end = (i + size).clamp(0, points.length);
      final chunk = points.sublist(i, end);
      final total = chunk.fold<int>(0, (sum, p) => sum + p.expenses);
      final date = chunk.first.date;
      final parsed = DateTime.tryParse(date);
      final label = parsed != null ? DateFormatUtil.formatDayMonth(parsed.toLocal()) : date;
      result.add((label: label, value: total));
    }
    return result;
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }

  Widget _chip(BuildContext context, String label, bool selected, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : scheme.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? scheme.primary : scheme.outline),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _summary(BuildContext context, String label, int amount, Color color, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatMoneyCurrent(amount),
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryRow(BuildContext context, CategoryShare share) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                share.category,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurface),
              ),
            ),
            Text(
              '${formatMoneyCurrent(share.total, withCurrency: false)} · ${share.percent}%',
              style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: (share.percent.clamp(0, 100)) / 100,
            minHeight: 7,
            backgroundColor: scheme.outline,
            valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
          ),
        ),
      ],
    );
  }
}
