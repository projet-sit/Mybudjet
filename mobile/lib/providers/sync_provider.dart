import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sync_info.dart';
import '../services/outbox.dart';

/// État de synchronisation dérivé de signaux réels :
/// - la connectivité réseau (connectivity_plus), jamais un booléen collé ;
/// - le nombre d'opérations réellement en attente (outbox).
///
/// Un échec ou un timeout du BACKEND n'est JAMAIS présenté comme « hors ligne ».
class SyncController extends Notifier<SyncInfo> {
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _debounce;
  bool _started = false;

  @override
  SyncInfo build() {
    ref.onDispose(() {
      _sub?.cancel();
      _debounce?.cancel();
    });
    _ensureStarted();
    return const SyncInfo(state: SyncState.synced);
  }

  void _ensureStarted() {
    if (_started) return;
    _started = true;
    _init();
  }

  Future<void> _init() async {
    await refresh();
    _sub = Connectivity().onConnectivityChanged.listen((_) {
      // Retour du réseau : recalcul immédiat (et discret).
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), refresh);
    });
  }

  Future<void> refresh() async {
    bool online = true;
    try {
      final results = await Connectivity().checkConnectivity();
      online = results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      // En cas de doute (exception plateforme), on considère le réseau présent :
      // un backend en erreur individualisée n'est pas « hors ligne ».
      online = true;
    }
    final pending = await Outbox.instance.count();
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
}

final syncInfoProvider =
    NotifierProvider<SyncController, SyncInfo>(SyncController.new);

/// Vrai UNIQUEMENT lors d'une absence réelle de réseau ou d'opérations en attente.
/// JAMAIS positionné sur une erreur/un timeout backend.
final offlineProvider = Provider<bool>((ref) {
  final info = ref.watch(syncInfoProvider);
  return info.state == SyncState.offline || info.state == SyncState.pending;
});

/// Avis de synchronisation : opérations abandonnées après échec définitif.
/// Affiché dans le bandeau d'accueil pour que l'utilisateur soit informé.
class SyncNotice {
  const SyncNotice({required this.failedCount, required this.message});

  final int failedCount;
  final String message;
}

class SyncNoticeController extends Notifier<SyncNotice?> {
  @override
  SyncNotice? build() => null;

  void setFailed(int failedCount, String message) {
    if (failedCount <= 0) return;
    state = SyncNotice(failedCount: failedCount, message: message);
  }

  void clear() {
    if (state != null) state = null;
  }
}

final syncNoticeProvider =
    NotifierProvider<SyncNoticeController, SyncNotice?>(SyncNoticeController.new);
