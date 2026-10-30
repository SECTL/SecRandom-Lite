import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secrandom_lite/services/cloud/cloud_api.dart';
import 'package:secrandom_lite/services/cloud/history_stream_manager.dart';
import 'package:secrandom_lite/services/cloud/sync_state.dart';

class FakeCloudApi extends SectlCloudApi {
  final Map<String, dynamic> store = {};

  /// 为 true 时下一次 meta 写入抛错，模拟「分片写成功、meta 写失败」。
  bool failNextMetaWrite = false;

  T _deepCopy<T>(T value) => jsonDecode(jsonEncode(value)) as T;

  @override
  Future<dynamic> getKvValue(String key) async {
    if (!store.containsKey(key)) {
      throw const CloudApiException(statusCode: 404, error: 'not_found');
    }
    return _deepCopy(store[key]);
  }

  @override
  Future<CloudKvEntry> putKv({
    required String key,
    required dynamic value,
    int? ttl,
  }) async {
    if (failNextMetaWrite && key.endsWith('.meta')) {
      failNextMetaWrite = false;
      throw const CloudApiException(
        statusCode: 500,
        error: 'meta_write_failed',
      );
    }
    store[key] = _deepCopy(value);
    return CloudKvEntry(key: key, value: store[key], size: 0, isJson: true);
  }

  @override
  Future<void> deleteKv(String key) async => store.remove(key);
}

Map<String, dynamic> rec(int i) => {'id': i, 'uid': 'dev-a:$i', 'name': '学生$i'};

void main() {
  late FakeCloudApi api;
  late HistoryStreamManager mgr;

  setUp(() {
    api = FakeCloudApi();
    mgr = HistoryStreamManager(api, kind: 'rollcall', deviceId: 'dev-a');
  });

  test('追加后可从未读位置拉回，游标正确', () async {
    await mgr.appendOwn([rec(0), rec(1), rec(2)]);
    final (records, cursor) = await mgr.readFrom('dev-a', const SyncCursor());
    expect(records.map((e) => e['uid']), ['dev-a:0', 'dev-a:1', 'dev-a:2']);
    expect(cursor.shard, 0);
    expect(cursor.count, 3);

    final (again, _) = await mgr.readFrom('dev-a', cursor);
    expect(again, isEmpty);
  });

  test('尾片增长后从旧游标只读新增部分', () async {
    await mgr.appendOwn([rec(0), rec(1)]);
    final (_, cursor) = await mgr.readFrom('dev-a', const SyncCursor());
    await mgr.appendOwn([rec(2)]);
    final (records, next) = await mgr.readFrom('dev-a', cursor);
    expect(records.map((e) => e['uid']), ['dev-a:2']);
    expect(next.count, 3);
  });

  test('追加重试不会重复写入相同 uid', () async {
    await mgr.appendOwn([rec(0)]);
    await mgr.appendOwn([rec(0), rec(1)]);

    final meta = await mgr.loadMeta('dev-a');
    expect(meta.total, 2);
    final (records, _) = await mgr.readFrom('dev-a', const SyncCursor());
    expect(records.map((e) => e['uid']), ['dev-a:0', 'dev-a:1']);
  });

  test('105 条按 100 条/片封片，跨片续读无重复', () async {
    await mgr.appendOwn([for (var i = 0; i < 105; i++) rec(i)]);
    final meta = await mgr.loadMeta('dev-a');
    expect(meta.shards, 2);
    expect(meta.total, 105);

    final (first, cursor) = await mgr.readFrom('dev-a', const SyncCursor());
    expect(first, hasLength(105));
    final (again, _) = await mgr.readFrom('dev-a', cursor);
    expect(again, isEmpty);
  });

  test('大记录触发字节守卫封片', () async {
    final big = <String, dynamic>{
      'id': 0,
      'uid': 'dev-a:0',
      'name': '名' * 20000, // UTF-8 约 60KB
    };
    await mgr.appendOwn([big, rec(1)]);
    final meta = await mgr.loadMeta('dev-a');
    expect(meta.shards, 2, reason: '单条超限允许独占一片，后续记录开新片');
  });

  test('非空尾片放不下下一条大记录时新开分片', () async {
    await mgr.appendOwn([rec(0)]);
    final big = <String, dynamic>{
      'id': 1,
      'uid': 'dev-a:1',
      'name': '名' * 20000, // UTF-8 约 60KB
    };
    await mgr.appendOwn([big]);

    final meta = await mgr.loadMeta('dev-a');
    expect(meta.shards, 2);
    expect(meta.total, 2);
    final (records, _) = await mgr.readFrom('dev-a', const SyncCursor());
    expect(records.map((e) => e['uid']), ['dev-a:0', 'dev-a:1']);
  });

  test('中间分片缺失时抛错且不推进游标，恢复后可完整读取', () async {
    await mgr.appendOwn([for (var i = 0; i < 205; i++) rec(i)]);
    final meta = await mgr.loadMeta('dev-a');
    expect(meta.shards, 3);
    final shardKey = mgr.shardKey('dev-a', 1);
    final saved = api.store.remove(shardKey);
    expect(saved, isNotNull);

    await expectLater(
      mgr.readFrom('dev-a', const SyncCursor()),
      throwsA(isA<IncompleteStreamException>()),
    );

    api.store[shardKey] = saved;
    final (records, cursor) = await mgr.readFrom('dev-a', const SyncCursor());
    expect(records, hasLength(205));
    expect(cursor.shard, 2);
    expect(cursor.count, 5);
  });

  test('旧 meta 没有 shard_counts 时仍能完整读取', () async {
    await mgr.appendOwn([for (var i = 0; i < 105; i++) rec(i)]);
    final metaKey = mgr.metaKey('dev-a');
    final stored = Map<String, dynamic>.from(api.store[metaKey] as Map);
    stored.remove('shard_counts');
    api.store[metaKey] = stored;

    final (records, cursor) = await mgr.readFrom('dev-a', const SyncCursor());
    expect(records, hasLength(105));
    expect(cursor.shard, 1);
    expect(cursor.count, 5);
  });

  test('分片写成功、meta 写失败后重试会重建 meta 且不丢记录', () async {
    await mgr.appendOwn([rec(0)]);
    expect((await mgr.loadMeta('dev-a')).total, 1);

    api.failNextMetaWrite = true;
    await expectLater(
      mgr.appendOwn([for (var i = 1; i < 105; i++) rec(i)]),
      throwsA(isA<CloudApiException>()),
    );

    // 重试同一批记录：分片里已有，不能重复写入；meta 需要自愈。
    final meta = await mgr.appendOwn([for (var i = 1; i < 105; i++) rec(i)]);
    expect(meta.shards, 2);
    expect(meta.total, 105);
    expect(meta.shardCounts, [100, 5]);

    final (records, _) = await mgr.readFrom('dev-a', const SyncCursor());
    expect(records, hasLength(105));
    expect(records.map((e) => e['uid']).toSet(), hasLength(105));
  });

  test('尾片在 meta 快照后增长时只消费到快照计数', () async {
    await mgr.appendOwn([rec(0), rec(1)]);
    final metaKey = mgr.metaKey('dev-a');
    final current = Map<String, dynamic>.from(api.store[metaKey] as Map);
    api.store[metaKey] = {
      ...current,
      'total': 1,
      'last_shard_count': 1,
      'shard_counts': [1],
    };

    final (first, cursor) = await mgr.readFrom('dev-a', const SyncCursor());
    expect(first.map((e) => e['uid']), ['dev-a:0']);
    expect(cursor.count, 1);

    // meta 追上来后，从旧游标继续读快照之后新增的记录。
    api.store[metaKey] = current;
    final (rest, next) = await mgr.readFrom('dev-a', cursor);
    expect(rest.map((e) => e['uid']), ['dev-a:1']);
    expect(next.count, 2);
  });
}
