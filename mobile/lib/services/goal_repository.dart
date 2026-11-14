import 'package:dio/dio.dart';

import '../models/goal.dart';
import '../models/wallet.dart';
import 'api_client.dart';

class GoalRepository {
  GoalRepository._internal();

  static final GoalRepository instance = GoalRepository._internal();

  final Dio _dio = ApiClient.instance.dio;

  Future<List<Goal>> list(String walletId) async {
    final response = await _dio.get('/wallets/$walletId/goals');
    return (response.data['data']['goals'] as List)
        .map((g) => Goal.fromJson(g as Map<String, dynamic>))
        .toList();
  }

  Future<Goal> create(
    String walletId, {
    required String name,
    required int targetAmount,
  }) async {
    final response = await _dio.post('/wallets/$walletId/goals', data: {
      'name': name,
      'targetAmount': targetAmount,
    });
    return Goal.fromJson(response.data['data']['goal'] as Map<String, dynamic>);
  }

  Future<Goal> update(
    String walletId,
    String goalId, {
    required String name,
    required int targetAmount,
  }) async {
    final response = await _dio.patch('/wallets/$walletId/goals/$goalId', data: {
      'name': name,
      'targetAmount': targetAmount,
    });
    return Goal.fromJson(response.data['data']['goal'] as Map<String, dynamic>);
  }

  Future<void> remove(String walletId, String goalId) async {
    await _dio.delete('/wallets/$walletId/goals/$goalId');
  }

  Future<({Goal goal, Wallet wallet})> contribute(
    String walletId,
    String goalId,
    int amount,
  ) async {
    final response = await _dio.post(
      '/wallets/$walletId/goals/$goalId/contribute',
      data: {'amount': amount},
    );
    final data = response.data['data'] as Map<String, dynamic>;
    return (
      goal: Goal.fromJson(data['goal'] as Map<String, dynamic>),
      wallet: Wallet.fromJson(data['wallet'] as Map<String, dynamic>),
    );
  }

  Future<({Goal goal, Wallet wallet})> withdraw(
    String walletId,
    String goalId,
    int amount,
  ) async {
    final response = await _dio.post(
      '/wallets/$walletId/goals/$goalId/withdraw',
      data: {'amount': amount},
    );
    final data = response.data['data'] as Map<String, dynamic>;
    return (
      goal: Goal.fromJson(data['goal'] as Map<String, dynamic>),
      wallet: Wallet.fromJson(data['wallet'] as Map<String, dynamic>),
    );
  }
}
