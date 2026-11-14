import 'transaction.dart';

class DashboardData {
  const DashboardData({
    required this.walletId,
    required this.walletName,
    required this.currency,
    required this.initialAmount,
    required this.balance,
    required this.totalExpenses,
    required this.totalIncomes,
    required this.transactionsCount,
    required this.percentUsed,
    required this.weeklySeries,
    required this.latestTransactions,
  });

  final String walletId;
  final String walletName;
  final String currency;
  final int initialAmount;
  final int balance;
  final int totalExpenses;
  final int totalIncomes;
  final int transactionsCount;
  final int percentUsed;
  final List<DailyPoint> weeklySeries;
  final List<Transaction> latestTransactions;

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    final wallet = json['wallet'] as Map<String, dynamic>;
    final totals = json['totals'] as Map<String, dynamic>;
    return DashboardData(
      walletId: wallet['id'] as String,
      walletName: (wallet['name'] ?? '') as String,
      currency: (wallet['currency'] ?? 'XOF') as String,
      initialAmount: _asInt(wallet['initialAmount']),
      balance: _asInt(wallet['balance']),
      totalExpenses: _asInt(totals['expenses']),
      totalIncomes: _asInt(totals['incomes']),
      transactionsCount: _asInt(totals['transactions']),
      percentUsed: _asInt(totals['percentUsed']),
      weeklySeries: (json['weeklySeries'] as List)
          .map((p) => DailyPoint.fromJson(p as Map<String, dynamic>))
          .toList(),
      latestTransactions: (json['latestTransactions'] as List)
          .map((t) => Transaction.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.parse(value);
    return 0;
  }
}

class DailyPoint {
  const DailyPoint({required this.date, required this.expenses});

  final String date; // YYYY-MM-DD
  final int expenses;

  factory DailyPoint.fromJson(Map<String, dynamic> json) {
    return DailyPoint(
      date: json['date'] as String,
      expenses: Transaction.asInt(json['expenses']),
    );
  }
}

class StatsData {
  const StatsData({
    required this.period,
    required this.dateFrom,
    required this.dateTo,
    required this.periodExpenses,
    required this.periodIncomes,
    required this.previousPeriodExpenses,
    required this.averageDaily,
    required this.dailySeries,
    required this.byCategory,
  });

  final String period;
  final String dateFrom;
  final String dateTo;
  final int periodExpenses;
  final int periodIncomes;
  final int previousPeriodExpenses;
  final int averageDaily;
  final List<DailyPoint> dailySeries;
  final List<CategoryShare> byCategory;

  factory StatsData.fromJson(Map<String, dynamic> json) {
    final totals = json['totals'] as Map<String, dynamic>;
    return StatsData(
      period: (json['period'] ?? 'month') as String,
      dateFrom: (json['dateFrom'] ?? '') as String,
      dateTo: (json['dateTo'] ?? '') as String,
      periodExpenses: Transaction.asInt(totals['periodExpenses']),
      periodIncomes: Transaction.asInt(totals['periodIncomes']),
      previousPeriodExpenses: Transaction.asInt(totals['previousPeriodExpenses']),
      averageDaily: Transaction.asInt(totals['averageDaily']),
      dailySeries: (json['dailySeries'] as List)
          .map((p) => DailyPoint.fromJson(p as Map<String, dynamic>))
          .toList(),
      byCategory: (json['byCategory'] as List)
          .map((c) => CategoryShare.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}

class CategoryShare {
  const CategoryShare({
    required this.category,
    required this.total,
    required this.count,
    required this.percent,
  });

  final String category;
  final int total;
  final int count;
  final int percent;

  factory CategoryShare.fromJson(Map<String, dynamic> json) {
    return CategoryShare(
      category: (json['category'] ?? '') as String,
      total: Transaction.asInt(json['total']),
      count: Transaction.asInt(json['count']),
      percent: Transaction.asInt(json['percent']),
    );
  }
}

class Budget {
  const Budget({
    required this.id,
    required this.walletId,
    required this.category,
    required this.limitAmount,
    this.spent = 0,
    this.percent = 0,
    this.alertLevel = 0,
  });

  final String id;
  final String walletId;
  final String category;
  final int limitAmount;
  final int spent;
  final int percent;
  final int alertLevel; // 0 | 50 | 80 | 100

  int get remaining => (limitAmount - spent).clamp(0, limitAmount);

  factory Budget.fromJson(Map<String, dynamic> json) {
    return Budget(
      id: json['id'] as String,
      walletId: json['walletId'] as String,
      category: (json['category'] ?? '') as String,
      limitAmount: Transaction.asInt(json['limitAmount']),
      spent: Transaction.asInt(json['spent']),
      percent: Transaction.asInt(json['percent']),
      alertLevel: Transaction.asInt(json['alertLevel']),
    );
  }
}
