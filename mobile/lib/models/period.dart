import 'wallet.dart';

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
