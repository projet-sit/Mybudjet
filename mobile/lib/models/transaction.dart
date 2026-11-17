class Transaction {
  const Transaction({
    required this.id,
    required this.walletId,
    required this.type,
    required this.amount,
    required this.category,
    this.categoryId,
    this.description,
    required this.date,
    required this.time,
    this.paymentMethod,
  });

  final String id;
  final String walletId;
  final String type; // 'expense' | 'income' | 'savings_deposit' | 'savings_withdrawal'
  final int amount; // entiers uniquement
  final String category;
  /// Id de la catégorie en base (défaut ou personnalisée). Null pour les
  /// anciens enregistrements / la génération locale hors-ligne.
  final String? categoryId;
  final String? description;
  final String date; // YYYY-MM-DD
  final String time; // HH:mm
  final String? paymentMethod;

  bool get isExpense => type == 'expense';
  bool get isIncome => type == 'income';
  bool get isSavingsDeposit => type == 'savings_deposit';
  bool get isSavingsWithdrawal => type == 'savings_withdrawal';
  bool get isSavings => isSavingsDeposit || isSavingsWithdrawal;

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'] as String,
      walletId: json['walletId'] as String,
      type: (json['type'] ?? 'expense') as String,
      amount: asInt(json['amount']),
      category: (json['category'] ?? '') as String,
      categoryId: json['categoryId'] as String?,
      description: json['description'] as String?,
      // Tolère d'anciens caches avec un suffixe d'heure : on garde le jour civil.
      date: ((json['date'] ?? '') as String).trim().length >= 10
          ? ((json['date'] as String).trim().substring(0, 10))
          : ((json['date'] ?? '') as String).trim(),
      time: ((json['time'] ?? '') as String).trim().length >= 5
          ? ((json['time'] as String).trim().substring(0, 5))
          : ((json['time'] ?? '') as String).trim(),
      paymentMethod: json['paymentMethod'] as String?,
    );
  }

  static int asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.parse(value);
    return 0;
  }

  Map<String, dynamic> toRequest() => {
        'type': type,
        'amount': amount,
        'category': category,
        if (categoryId != null) 'categoryId': categoryId,
        if (description != null && description!.isNotEmpty) 'description': description,
        'date': date,
        'time': time,
        if (paymentMethod != null) 'paymentMethod': paymentMethod,
      };

  /// JSON complet (cache local hors-ligne).
  Map<String, dynamic> toJson() => {
        'id': id,
        'walletId': walletId,
        'type': type,
        'amount': amount,
        'category': category,
        if (categoryId != null) 'categoryId': categoryId,
        if (description != null) 'description': description,
        'date': date,
        'time': time,
        if (paymentMethod != null) 'paymentMethod': paymentMethod,
      };

  Transaction copyWith({
    String? id,
    String? walletId,
    String? type,
    int? amount,
    String? category,
    String? categoryId,
    String? description,
    String? date,
    String? time,
    String? paymentMethod,
  }) {
    return Transaction(
      id: id ?? this.id,
      walletId: walletId ?? this.walletId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      categoryId: categoryId ?? this.categoryId,
      description: description ?? this.description,
      date: date ?? this.date,
      time: time ?? this.time,
      paymentMethod: paymentMethod ?? this.paymentMethod,
    );
  }
}

class TransactionPage {
  const TransactionPage({
    required this.transactions,
    required this.total,
    required this.totalExpenses,
    required this.totalIncomes,
    required this.page,
    required this.pages,
  });

  final List<Transaction> transactions;
  final int total;
  final int totalExpenses;
  final int totalIncomes;
  final int page;
  final int pages;

  bool get hasMore => page < pages;

  factory TransactionPage.fromJson(Map<String, dynamic> json) {
    return TransactionPage(
      transactions: (json['transactions'] as List)
          .map((t) => Transaction.fromJson(t as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int? ?? 0,
      totalExpenses: json['totalExpenses'] as int? ?? 0,
      totalIncomes: json['totalIncomes'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      pages: json['pages'] as int? ?? 1,
    );
  }
}
