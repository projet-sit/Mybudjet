class Wallet {
  const Wallet({
    required this.id,
    required this.userId,
    required this.name,
    required this.initialAmount,
    required this.startDate,
    required this.currency,
    required this.balance,
    this.savingsAmount = 0,
  });

  final String id;
  final String userId;
  final String name;
  final int initialAmount; // entiers uniquement — jamais de double
  final String startDate; // YYYY-MM-DD
  final String currency;
  final int balance;
  final int savingsAmount; // réserve interne au même compte

  /// Argent réellement utilisable : solde − épargne (jamais négatif).
  int get available => (balance - savingsAmount).clamp(0, balance).toInt();

  bool get hasSavings => savingsAmount > 0;

  factory Wallet.fromJson(Map<String, dynamic> json) {
    return Wallet(
      id: json['id'] as String,
      userId: json['userId'] as String,
      name: (json['name'] ?? '') as String,
      initialAmount: asInt(json['initialAmount']),
      startDate: (json['startDate'] ?? '') as String,
      currency: (json['currency'] ?? 'XOF') as String,
      balance: asInt(json['balance']),
      savingsAmount: asInt(json['savingsAmount']),
    );
  }

  /// Les montants arrivent en entiers JSON ; garde-fou contre tout double.
  static int asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.parse(value);
    return 0;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'name': name,
        'initialAmount': initialAmount,
        'startDate': startDate,
        'currency': currency,
        'balance': balance,
        'savingsAmount': savingsAmount,
      };
}
