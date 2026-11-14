enum SyncState { synced, pending, offline }

class SyncInfo {
  const SyncInfo({required this.state, this.pendingCount = 0});

  final SyncState state;
  final int pendingCount;

  bool get isOffline => state == SyncState.offline;
  bool get isPending => state == SyncState.pending;
  bool get isSynced => state == SyncState.synced;
}

extension SyncStateLabel on SyncState {
  String get label {
    switch (this) {
      case SyncState.synced:
        return 'Synchronisé';
      case SyncState.pending:
        return 'En attente de synchronisation';
      case SyncState.offline:
        return 'Hors-ligne';
    }
  }
}
