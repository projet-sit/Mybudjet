import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sync_info.dart';
import '../services/sync_queue.dart';

class SyncController extends Notifier<SyncInfo> {
  StreamSubscription<List<ConnectivityResult>>? _sub;

  @override
  SyncInfo build() {
    ref.onDispose(() => _sub?.cancel());
    _init();
    return const SyncInfo(state: SyncState.synced);
  }

  Future<void> _init() async {
    await _refresh();
    _sub = Connectivity().onConnectivityChanged.listen((_) => _refresh());
  }

  Future<void> _refresh() async {
    final results = await Connectivity().checkConnectivity();
    final online = results.any((r) => r != ConnectivityResult.none);
    final pending = await SyncQueue.instance.count();
    final SyncState s;
    if (!online) {
      s = SyncState.offline;
    } else if (pending > 0) {
      s = SyncState.pending;
    } else {
      s = SyncState.synced;
    }
    state = SyncInfo(state: s, pendingCount: pending);
  }

  Future<void> refresh() => _refresh();
}

final syncInfoProvider =
    NotifierProvider<SyncController, SyncInfo>(SyncController.new);
