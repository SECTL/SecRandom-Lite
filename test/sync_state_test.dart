import 'package:flutter_test/flutter_test.dart';
import 'package:secrandom_lite/services/cloud/sync_state.dart';

void main() {
  test('LocalSyncState 往返序列化', () {
    final state = LocalSyncState();
    state.ownSeq['rollcall'] = 12;
    state.clearedAt['lottery'] = DateTime(2026, 1, 2, 3, 4, 5);
    state.pulled['dev-b'] = {'rollcall': const SyncCursor(shard: 1, count: 80)};
    state.ownRollcallStats['张三'] = 3;
    state.legacyUploaded = true;

    final restored = LocalSyncState.fromJson(state.toJson());
    expect(restored.ownSeq['rollcall'], 12);
    expect(restored.clearedAt['lottery'], DateTime(2026, 1, 2, 3, 4, 5));
    expect(restored.pulled['dev-b']!['rollcall']!.shard, 1);
    expect(restored.pulled['dev-b']!['rollcall']!.count, 80);
    expect(restored.ownRollcallStats['张三'], 3);
    expect(restored.legacyUploaded, isTrue);
  });

  test('SyncOutbox 增删与按 kind 读取', () {
    final outbox = SyncOutbox();
    outbox.rollcall.add({'uid': 'dev-1:1'});
    outbox.rollcall.add({'uid': 'dev-1:2'});
    outbox.lottery.add({'uid': 'dev-1:1'});

    expect(outbox.isEmpty, isFalse);
    expect(outbox.forKind('rollcall'), hasLength(2));

    outbox.removeUids('rollcall', {'dev-1:1'});
    expect(outbox.forKind('rollcall').single['uid'], 'dev-1:2');

    final restored = SyncOutbox.fromJson(outbox.toJson());
    expect(restored.forKind('rollcall'), hasLength(1));
    expect(restored.forKind('lottery'), hasLength(1));
  });
}
