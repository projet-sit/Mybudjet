import 'package:flutter_test/flutter_test.dart';
import 'package:mybudget/models/sync_info.dart';

void main() {
  test('SyncState labels are user-friendly', () {
    expect(SyncState.synced.label, 'Synchronisé');
    expect(SyncState.pending.label, 'En attente de synchronisation');
    expect(SyncState.offline.label, 'Hors-ligne');
  });

  test('SyncInfo defaults', () {
    const info = SyncInfo(state: SyncState.synced);
    expect(info.pendingCount, 0);
    expect(info.isSynced, isTrue);
  });
}
