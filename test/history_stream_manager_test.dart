import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secrandom_lite/services/cloud/cloud_api.dart';
import 'package:secrandom_lite/services/cloud/history_stream_manager.dart';
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
}
