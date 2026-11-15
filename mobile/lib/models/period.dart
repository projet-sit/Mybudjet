import 'wallet.dart';

class PeriodSummary {
  const PeriodSummary({
    required this.id,
    required this.walletId,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.totals,
    this.walletAtClose,
    this.closedAt,
  });

  final String id;
  final String walletId;
  final String startDate; // YYYY-MM-DD
  final String endDate; // YYYY-MM-DD
  final String status; // active | archived
  final PeriodSummaryTotals totals;
  final PeriodSnapshotWallet? walletAtClose;
  final DateTime? closedAt;

  bool get isActive => status == 'active';

  factory PeriodSummary.fromJson(Map<String, dynamic> json) {
    return PeriodSummary(
      id: json['id'] as String,
      walletId: (json['walletId'] ?? '') as String,
      startDate: (json['startDate'] ?? '') as String,
      endDate: (json['endDate'] ?? '') as String,
      status: (json['status'] ?? 'archived') as String,
      totals: PeriodSummaryTotals.fromJson(
        Map<String, dynamic>.from(json['totals'] as Map? ?? const {}),
      ),
      walletAtClose: json['walletAtClose'] is Map
          ? PeriodSnapshotWallet.fromJson(Map<String, dynamic>.from(json['walletAtClose'] as Map))
          : null,
      closedAt: json['closedAt'] != null ? DateTime.tryParse(json['closedAt'] as String) : null,
    );
  }
}

class PeriodSummaryTotals {
  const PeriodSummaryTotals({
    this.expenses = 0,
    this.incomes = 0,
    this.saved = 0,
    this.transactions = 0,
  });

  final int expenses;
  final int incomes;
  final int saved;
  final int transactions;

  factory PeriodSummaryTotals.fromJson(Map<String, dynamic> json) => PeriodSummaryTotals(
        expenses: Wallet.asInt(json['expenses']),
        incomes: Wallet.asInt(json['incomes']),
        saved: Wallet.asInt(json['saved']),
        transactions: Wallet.asInt(json['transactions']),
      );
}

class PeriodSnapshotWallet {
  const PeriodSnapshotWallet({
    required this.initialAmount,
    required this.balance,
    required this.savingsAmount,
    required this.startDate,
  });

  final int initialAmount;
  final int balance;
  final int savingsAmount;
  final String startDate;

  factory PeriodSnapshotWallet.fromJson(Map<String, dynamic> json) => PeriodSnapshotWallet(
        initialAmount: Wallet.asInt(json['initialAmount']),
        balance: Wallet.asInt(json['balance']),
        savingsAmount: Wallet.asInt(json['savingsAmount']),
        startDate: (json['startDate'] ?? '') as String,
      );
}

class BudgetPeriod {
  const BudgetPeriod({
    required this.id,
    required this.walletId,
    required this.startDate,
    required this.endDate,
    required this.status,
  });

  final String id;
  final String walletId;
  final String startDate; // YYYY-MM-DD
  final String endDate; // YYYY-MM-DD
  final String status; // active | archived

  bool get isActive => status == 'active';

  DateTime get start => DateTime.parse(startDate);
  DateTime get end => DateTime.parse(endDate);

  factory BudgetPeriod.fromJson(Map<String, dynamic> json) {
    return BudgetPeriod(
      id: json['id'] as String,
      walletId: (json['walletId'] ?? '') as String,
      startDate: (json['startDate'] ?? '') as String,
      endDate: (json['endDate'] ?? '') as String,
      status: (json['status'] ?? 'active') as String,
    );
  }
}

class PeriodInfo {
  const PeriodInfo({
    required this.period,
    required this.needsNewPeriod,
    required this.daysLeft,
  });

  final BudgetPeriod period;
  final bool needsNewPeriod;
  final int daysLeft;

  factory PeriodInfo.fromJson(Map<String, dynamic> json) {
    return PeriodInfo(
      period: BudgetPeriod.fromJson(json['period'] as Map<String, dynamic>),
      needsNewPeriod: json['needsNewPeriod'] == true,
      daysLeft: (json['daysLeft'] as num?)?.toInt() ?? 0,
    );
  }
}

class PeriodTransition {
  const PeriodTransition({
    required this.period,
    required this.wallet,
    required this.previousPeriodId,
    required this.mode,
    required this.undoExpiresAt,
  });

  final BudgetPeriod period;
  final Wallet wallet;
  final String? previousPeriodId;
  final String mode;
  final String? undoExpiresAt;

  factory PeriodTransition.fromJson(Map<String, dynamic> json) {
    return PeriodTransition(
      period: BudgetPeriod.fromJson(json['period'] as Map<String, dynamic>),
      wallet: Wallet.fromJson(json['wallet'] as Map<String, dynamic>),
      previousPeriodId: json['previousPeriodId'] as String?,
      mode: (json['mode'] ?? 'reset') as String,
      undoExpiresAt: json['undoExpiresAt'] as String?,
    );
  }
}
