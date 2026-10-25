import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secrandom_lite/models/history_record.dart';
import 'package:secrandom_lite/models/student.dart';
import 'package:secrandom_lite/services/cloud/cloud_api.dart';
import 'package:secrandom_lite/services/cloud/cloud_sync_service.dart';
import 'package:secrandom_lite/services/cloud/sync_identity.dart';
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

  @override
  Future<CloudKvList> listKv({int limit = 100, int offset = 0}) async {
    final keys = store.keys.toList()..sort();
    if (offset >= keys.length) {
      return CloudKvList(entries: const [], total: keys.length, hasMore: false);
    }
    final pageKeys = keys.skip(offset).take(limit).toList();
    return CloudKvList(
      entries: pageKeys
          .map(
            (key) => CloudKvEntry(
              key: key,
              value: _deepCopy(store[key]),
              size: 0,
              isJson: true,
            ),
          )
          .toList(),
      total: keys.length,
      hasMore: offset + pageKeys.length < keys.length,
    );
  }
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
    expect(api.store.containsKey('srlite.history.v2.rollcall.dev-a.0'), isTrue);
    expect(
      api.store.containsKey('srlite.history.v2.rollcall.dev-a.meta'),
      isTrue,
    );
    expect(api.store.containsKey('srlite.sync.v2.registry'), isTrue);
    expect(
      api.store['srlite.stats.v2.rollcall.dev-a'],
      {'张三': 1},
    );
    expect(api.store.keys, everyElement(startsWith('srlite.')));
  });

  test('学生名单写入 srlite.students', () async {
    final api = FakeCloudApi();
    final service = CloudSyncService(api: api, deviceId: 'dev-a');

    await service.pushStudents([
      Student(id: 1, name: '张三', gender: '男', group: '1', exist: true),
    ]);

    expect(api.store['srlite.students'], [
      {
        'id': 1,
        'name': '张三',
        'gender': '男',
        'group': '1',
        'class_name': '1',
        'exist': true,
      },
    ]);
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

  test('拉取缺失 uid 的旧记录时派生稳定 uid', () async {
    final api = FakeCloudApi();
    final oldJson = rollcall('dev-b:1').toJson()..remove('uid');
    final expectedUid = deriveLegacyHistoryUid(HistoryRecord.fromJson(oldJson));
    api.store['srlite.sync.v2.registry'] = {
      'devices': {'dev-b': <String, dynamic>{}},
    };
    api.store['srlite.history.v2.rollcall.dev-b.meta'] = {
      'shards': 1,
      'total': 1,
      'last_shard_count': 1,
    };
    api.store['srlite.history.v2.rollcall.dev-b.0'] = [oldJson];

    final service = CloudSyncService(
      api: api,
      store: MemorySyncLocalStore(),
      deviceId: 'dev-a',
    );
    Map<String, dynamic>? pulled;
    final result = await service.pullAll(
      existingUids: (_) async => <String>{},
      onNewRecord: (_, json) async => pulled = json,
    );

    expect(result!.newRecords, 1);
    expect(pulled!['uid'], expectedUid);

    final snapshot = await service.pullFullSnapshot();
    expect(snapshot!.rollcallRecords.single['uid'], expectedUid);
  });

  test('outbox 按 uid 去重', () async {
    final store = MemorySyncLocalStore();
    final service = CloudSyncService(
      api: FakeCloudApi(),
      store: store,
      deviceId: 'dev-a',
    );
    final record = rollcall('dev-a:1').toJson();

    await service.enqueueRecord('rollcall', record);
    await service.enqueueRecord('rollcall', record);
    await service.enqueueAll('rollcall', [record]);

    expect(store.outbox.rollcall, hasLength(1));
  });

  test('注册表缺失时从历史分片键发现设备并拉取', () async {
    final api = FakeCloudApi();
    api.store['srlite.history.v2.rollcall.dev-b.0'] = [
      rollcall('dev-b:1').toJson(),
    ];
    api.store['srlite.history.v2.rollcall.dev-b.meta'] = {
      'shards': 1,
      'total': 1,
      'last_shard_count': 1,
    };

    final service = CloudSyncService(
      api: api,
      store: MemorySyncLocalStore(),
      deviceId: 'dev-a',
    );
    final seen = <String>{};
    final result = await service.pullAll(
      existingUids: (_) async => <String>{},
      onNewRecord: (_, json) async => seen.add(json['uid'] as String),
    );

    expect(result!.newRecords, 1);
    expect(seen, {'dev-b:1'});
  });

  test('注册表缺失时从统计键发现设备', () async {
    final api = FakeCloudApi();
    api.store['srlite.stats.v2.rollcall.dev-b'] = {'张三': 2};

    final service = CloudSyncService(
      api: api,
      store: MemorySyncLocalStore(),
      deviceId: 'dev-a',
    );

    final stats = await service.fetchRemoteStats('rollcall');
    expect(stats['dev-b'], {'张三': 2});
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
