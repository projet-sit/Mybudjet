import 'package:dio/dio.dart';

import '../models/wallet.dart';
import 'api_client.dart';

class WalletRepository {
  WalletRepository._internal();

  static final WalletRepository instance = WalletRepository._internal();

  final Dio _dio = ApiClient.instance.dio;

  /// Liste des portefeuilles de l'utilisateur connecté.
  Future<List<Wallet>> list() async {
    final response = await _dio.get('/wallets');
    final list = (response.data['data']['wallets'] as List)
        .map((w) => Wallet.fromJson(w as Map<String, dynamic>))
        .toList();
    return list;
  }

  /// Premier portefeuille (ou null si l'utilisateur n'en a pas encore).
  Future<Wallet?> first() async {
    final wallets = await list();
    return wallets.isEmpty ? null : wallets.first;
  }

  Future<Wallet> create({
    required String name,
    required int initialAmount,
    required String startDate,
    String currency = 'XOF',
  }) async {
    final response = await _dio.post('/wallets', data: {
      'name': name,
      'initialAmount': initialAmount,
      'startDate': startDate,
      'currency': currency,
    });
    return Wallet.fromJson(response.data['data']['wallet'] as Map<String, dynamic>);
  }

  Future<Wallet> get(String walletId) async {
    final response = await _dio.get('/wallets/$walletId');
    return Wallet.fromJson(response.data['data']['wallet'] as Map<String, dynamic>);
  }

  /// Fixe le montant mis de côté (réserve dans le même compte).
  /// Le backend refuse si le montant dépasse le solde.
  Future<Wallet> setSavings(String walletId, int amount) async {
    final response = await _dio.patch('/wallets/$walletId/savings', data: {
      'amount': amount,
    });
    return Wallet.fromJson(response.data['data']['wallet'] as Map<String, dynamic>);
  }

  Future<Wallet> updateInitialAmount(String walletId, int newAmount) async {
    final response = await _dio.patch('/wallets/$walletId/initial-amount', data: {
      'initialAmount': newAmount,
    });
    return Wallet.fromJson(response.data['data']['wallet'] as Map<String, dynamic>);
  }
}
