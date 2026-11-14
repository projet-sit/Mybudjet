import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/period.dart';
import '../services/period_repository.dart';
import 'transaction_provider.dart';
import 'wallet_provider.dart';

/// Période budgétaire active (le mois courant).
class PeriodController extends AsyncNotifier<PeriodInfo?> {
  @override
  FutureOr<PeriodInfo?> build() async {
    final wallet = await ref.watch(walletControllerProvider.future);
    if (wallet == null) return null;
    return PeriodRepository.instance.get(wallet.id);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async => await build());
  }

  Future<PeriodTransition> next(String mode) async {
    final wallet = ref.read(walletControllerProvider).value;
    if (wallet == null) throw StateError('Aucun portefeuille');

    final result = await PeriodRepository.instance.next(wallet.id, mode: mode);
    ref.read(walletControllerProvider.notifier).setWallet(result.wallet);
    ref.invalidate(transactionsProvider);
    ref.invalidate(dashboardControllerProvider);
    ref.invalidate(budgetsControllerProvider);
    state = AsyncData(await PeriodRepository.instance.get(wallet.id));
    return result;
  }

  Future<PeriodTransition> undo(String periodId) async {
    final wallet = ref.read(walletControllerProvider).value;
    if (wallet == null) throw StateError('Aucun portefeuille');

    final result = await PeriodRepository.instance.undo(wallet.id, periodId);
    ref.read(walletControllerProvider.notifier).setWallet(result.wallet);
    ref.invalidate(transactionsProvider);
    ref.invalidate(dashboardControllerProvider);
    ref.invalidate(budgetsControllerProvider);
    state = AsyncData(await PeriodRepository.instance.get(wallet.id));
    return result;
  }
}

final periodControllerProvider =
    AsyncNotifierProvider<PeriodController, PeriodInfo?>(PeriodController.new);
