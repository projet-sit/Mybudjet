import 'transaction.dart';

class Goal {
  const Goal({
    required this.id,
    required this.walletId,
    required this.name,
    required this.targetAmount,
    required this.savedAmount,
    required this.status,
    this.deadline,
  });

  final String id;
  final String walletId;
  final String name;
  final int targetAmount;
  final int savedAmount;
  final String status; // active | completed
  final String? deadline; // YYYY-MM-DD

  bool get isCompleted => status == 'completed';
  int get remaining => (targetAmount - savedAmount).clamp(0, targetAmount);
  double get progress => targetAmount <= 0 ? 0 : (savedAmount / targetAmount).clamp(0, 1);

  factory Goal.fromJson(Map<String, dynamic> json) {
    return Goal(
      id: json['id'] as String,
      walletId: (json['walletId'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      targetAmount: Transaction.asInt(json['targetAmount']),
      savedAmount: Transaction.asInt(json['savedAmount']),
      status: (json['status'] ?? 'active') as String,
      deadline: json['deadline'] as String?,
    );
  }
}
