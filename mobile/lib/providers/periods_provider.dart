import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/period.dart';
import '../services/period_repository.dart';
import 'wallet_provider.dart';

/// Périodes (active + archivées) — alimente l'écran « Historique des périodes ».
class PeriodsHistoryController extends AsyncNotifier<List<PeriodSummary>> {
  @override
  Future<List<PeriodSummary>> build() async {
    final wallet = await ref.watch(walletControllerProvider.future);
    if (wallet == null) return const [];
    return PeriodRepository.instance.list(wallet.id);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async => build());
  }
}

final periodsHistoryProvider =
    AsyncNotifierProvider<PeriodsHistoryController, List<PeriodSummary>>(PeriodsHistoryController.new);
