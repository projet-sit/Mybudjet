import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybudget/models/sync_info.dart';
import 'package:mybudget/providers/sync_provider.dart';

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

  test('syncNoticeProvider : défini à l’échec, effacé au succès/ignorer', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(syncNoticeProvider), isNull);
    container.read(syncNoticeProvider.notifier).setFailed(2, 'Solde disponible insuffisant');
    final notice = container.read(syncNoticeProvider);
    expect(notice, isNotNull);
    expect(notice!.failedCount, 2);
    expect(notice.message, contains('Solde'));
    container.read(syncNoticeProvider.notifier).clear();
    expect(container.read(syncNoticeProvider), isNull);
  });
}
