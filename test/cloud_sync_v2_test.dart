import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secrandom_lite/models/history_record.dart';
import 'package:secrandom_lite/services/cloud/cloud_api.dart';
import 'package:secrandom_lite/services/cloud/cloud_sync_service.dart';
import 'package:secrandom_lite/services/cloud/sync_local_store.dart';
import 'package:secrandom_lite/services/cloud/sync_state.dart';

class FakeCloudApi extends SectlCloudApi {
  final Map<String, dynamic> store = {};

  T _deepCopy<T>(T value) => jsonDecode(jsonEncode(value)) as T;

  @override
  Future<dynamic> getKvValue(String key) async {
    if (!store.containsKey(key)) {
      throw const CloudApiException(statusCode: 404, error: 'not_found');
    }
    return _deepCopy(store[key]);
  }

  @override
  Future<CloudKvEntry> putKv({required String key, required dynamic value, int? ttl}) async {
    store[key] = _deepCopy(value);
    return CloudKvEntry(key: key, value: store[key], size: 0, isJson: true);
  }

  @override
  Future<void> deleteKv(String key) async => store.remove(key);
}

class MemorySyncLocalStore implements SyncLocalStore {
  LocalSyncState state = LocalSyncState();
  SyncOutbox outbox = SyncOutbox();

  @override
  Future<LocalSyncState> loadState() async => state;
  @override
  Future<void> saveState(LocalSyncState s) async => state = s;
  @override
  Future<SyncOutbox> loadOutbox() async => outbox;
  @override
  Future<void> saveOutbox(SyncOutbox o) async => outbox = o;
}

HistoryRecord rollcall(String uid, {String name = '张三', String time = '2026-01-01 08:00:00'}) =>
    HistoryRecord(
      id: 1,
      uid: uid,
      name: name,
      drawMethod: 1,
      drawTime: time,
      drawPeopleNumbers: 1,
      drawGroup: '所有小组',
      drawGender: '所有性别',
      className: '1',
    );

void main() {
  test('离线 outbox 冲洗到自己的流，并写注册表与统计', () async {
    final api = FakeCloudApi();
    final store = MemorySyncLocalStore();
    final service = CloudSyncService(api: api, store: store, deviceId: 'dev-a');

    await service.enqueueRecord('rollcall', rollcall('dev-a:1').toJson());
    final ok = await service.pushAll(
      ownRollcall: {'张三': 1},
      ownLottery: {},
    );

    expect(ok, isTrue);
    expect(store.outbox.isEmpty, isTrue);
    expect(api.store.containsKey('secrandom.history.v2.rollcall.dev-a.0'), isTrue);
    expect(api.store.containsKey('secrandom.sync.v2.registry'), isTrue);
    expect(
      api.store['secrandom.stats.v2.rollcall.dev-a'],
      {'张三': 1},
    );
  });

  test('拉取另一设备的流：uid 去重、游标推进、统计返回', () async {
    final api = FakeCloudApi();
    final storeA = MemorySyncLocalStore();
    final storeB = MemorySyncLocalStore();

    final a = CloudSyncService(api: api, store: storeB, deviceId: 'dev-b');
    await a.enqueueRecord('rollcall', rollcall('dev-b:1').toJson());
    await a.enqueueRecord('rollcall', rollcall('dev-b:2', name: '李四').toJson());
    await a.pushAll(ownRollcall: {'张三': 1, '李四': 1}, ownLottery: {});

    final b = CloudSyncService(api: api, store: storeA, deviceId: 'dev-a');
    final existing = <String, Map<String, dynamic>>{};
    final pulled = await b.pullAll(
      existingUids: (kind) async => existing.keys.toSet(),
      onNewRecord: (kind, json) async {
        existing[json['uid'] as String] = json;
      },
    );

    expect(pulled, isNotNull);
    expect(pulled!.newRecords, 2);
    expect(existing.keys, containsAll(['dev-b:1', 'dev-b:2']));

    // 再拉一次不重复
    final again = await b.pullAll(
      existingUids: (kind) async => existing.keys.toSet(),
      onNewRecord: (kind, json) async {
        existing[json['uid'] as String] = json;
      },
    );
    expect(again!.newRecords, 0);
    expect(storeA.state.pulled['dev-b']!['rollcall']!.count, 2);
  });

  test('双设备并发交错写：双方最终都看到并集', () async {
    final api = FakeCloudApi();
    final storeA = MemorySyncLocalStore();
    final storeB = MemorySyncLocalStore();
    final a = CloudSyncService(api: api, store: storeA, deviceId: 'dev-a');
    final b = CloudSyncService(api: api, store: storeB, deviceId: 'dev-b');

    await a.enqueueRecord('rollcall', rollcall('dev-a:1').toJson());
    await b.enqueueRecord('rollcall', rollcall('dev-b:1').toJson());
    await a.pushAll(ownRollcall: {'张三': 1}, ownLottery: {});
    await b.pushAll(ownRollcall: {'张三': 1}, ownLottery: {});

    final seenByA = <String>{};
    await a.pullAll(
      existingUids: (_) async => seenByA,
      onNewRecord: (_, json) async => seenByA.add(json['uid'] as String),
    );
    final seenByB = <String>{};
    await b.pullAll(
      existingUids: (_) async => seenByB,
      onNewRecord: (_, json) async => seenByB.add(json['uid'] as String),
    );

    expect(seenByA, {'dev-b:1'});
    expect(seenByB, {'dev-a:1'});
  });

  test('clearedAt 过滤更早的远端记录', () async {
    final api = FakeCloudApi();
    final storeB = MemorySyncLocalStore();
    final b = CloudSyncService(api: api, store: storeB, deviceId: 'dev-b');
    await b.enqueueRecord('rollcall',
        rollcall('dev-b:1', time: '2026-01-01 08:00:00').toJson());
    await b.pushAll(ownRollcall: {}, ownLottery: {});

    final storeA = MemorySyncLocalStore();
    storeA.state.clearedAt['rollcall'] = DateTime(2026, 6, 1);
    final a = CloudSyncService(api: api, store: storeA, deviceId: 'dev-a');
    final seen = <String>{};
    final pulled = await a.pullAll(
      existingUids: (_) async => seen,
      onNewRecord: (_, json) async => seen.add(json['uid'] as String),
    );
    expect(pulled!.newRecords, 0);
  });

  test('拉取统计合并：两台设备贡献求和', () async {
    final api = FakeCloudApi();
    final storeA = MemorySyncLocalStore();
    final storeB = MemorySyncLocalStore();
    final a = CloudSyncService(api: api, store: storeA, deviceId: 'dev-a');
    final b = CloudSyncService(api: api, store: storeB, deviceId: 'dev-b');
    await a.pushAll(ownRollcall: {'张三': 3}, ownLottery: {});
    await b.pushAll(ownRollcall: {'张三': 2, '李四': 1}, ownLottery: {});

    final contributions = await a.fetchRemoteStats('rollcall');
    var total = 3;
    for (final map in contributions.values) {
      total += map['张三'] ?? 0;
    }
    expect(total, 5);
    expect(contributions['dev-b']!['李四'], 1);
  });
}
