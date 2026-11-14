import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/goal.dart';
import '../models/wallet.dart';
import '../services/goal_repository.dart';
import 'transaction_provider.dart';
import 'wallet_provider.dart';

class GoalsController extends AsyncNotifier<List<Goal>> {
  @override
  Future<List<Goal>> build() async {
    final wallet = await ref.watch(walletControllerProvider.future);
    if (wallet == null) return const [];
    return GoalRepository.instance.list(wallet.id);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
  }

  Future<void> create({required String name, required int targetAmount}) async {
    final wallet = _wallet;
    await GoalRepository.instance.create(
      wallet.id,
      name: name,
      targetAmount: targetAmount,
    );
    await _reload(wallet.id);
  }

  Future<void> edit(
    Goal goal, {
    required String name,
    required int targetAmount,
  }) async {
    final wallet = _wallet;
    await GoalRepository.instance.update(
      wallet.id,
      goal.id,
      name: name,
      targetAmount: targetAmount,
    );
    await _reload(wallet.id);
  }

  Future<void> remove(Goal goal) async {
    final wallet = _wallet;
    await GoalRepository.instance.remove(wallet.id, goal.id);
    await _reload(wallet.id);
  }

  Future<void> contribute(Goal goal, int amount) async {
    final wallet = _wallet;
    final result = await GoalRepository.instance.contribute(wallet.id, goal.id, amount);
    _applyWallet(result.wallet);
    await _reload(wallet.id);
  }

  Future<void> withdraw(Goal goal, int amount) async {
    final wallet = _wallet;
    final result = await GoalRepository.instance.withdraw(wallet.id, goal.id, amount);
    _applyWallet(result.wallet);
    await _reload(wallet.id);
  }

  Wallet get _wallet {
    final wallet = ref.read(walletControllerProvider).value;
    if (wallet == null) throw StateError('Aucun portefeuille');
    return wallet;
  }

  void _applyWallet(Wallet wallet) {
    ref.read(walletControllerProvider.notifier).setWallet(wallet);
    ref.invalidate(dashboardControllerProvider);
  }

  Future<void> _reload(String walletId) async {
    state = AsyncData(await GoalRepository.instance.list(walletId));
  }
}

final goalsControllerProvider =
    AsyncNotifierProvider<GoalsController, List<Goal>>(GoalsController.new);
