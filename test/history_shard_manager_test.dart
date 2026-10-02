import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secrandom_lite/services/cloud/cloud_api.dart';
import 'package:secrandom_lite/services/cloud/history_shard_manager.dart';

/// 内存版 Cloud API：行为对齐网络端（JSON 深拷贝、404 not_found）
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
  Future<CloudKvEntry> putKv({
    required String key,
    required dynamic value,
    int? ttl,
  }) async {
    store[key] = _deepCopy(value);
    return CloudKvEntry(key: key, value: store[key], size: 0, isJson: true);
  }

  @override
  Future<void> deleteKv(String key) async {
    store.remove(key);
  }

  @override
  Future<void> patchKvField({
    required String key,
    required String field,
    required dynamic value,
  }) async {
    final current = store[key];
    if (current is! Map<String, dynamic>) {
      throw const CloudApiException(statusCode: 404, error: 'not_found');
    }
    current[field] = value;
  }
}

Map<String, dynamic> record(int id) => {'id': '$id', 'name': '学生$id'};

void main() {
  late FakeCloudApi api;
  late HistoryShardManager mgr;

  setUp(() {
    api = FakeCloudApi();
    mgr = HistoryShardManager(api, keyPrefix: 'secrandom.history.rollcall');
  });

  test('空分片读取返回空列表', () async {
    expect(await mgr.readRecent(10), isEmpty);
    expect(await mgr.readAll(), isEmpty);
    expect((await mgr.loadMeta()).totalRecords, 0);
  });

  test('追加写入后可读回，meta 计数正确', () async {
    await mgr.appendRecords([record(1), record(2)]);
    final meta = await mgr.loadMeta();
    expect(meta.shardCount, 1);
    expect(meta.totalRecords, 2);
    final all = await mgr.readAll();
    expect(all.map((e) => e['id']), ['1', '2']);
  });

  test('跨分片追加：450 条分布 3 个分片', () async {
    await mgr.appendRecords([for (var i = 0; i < 450; i++) record(i)]);
    final meta = await mgr.loadMeta();
    expect(meta.shardCount, 3);
    expect(meta.totalRecords, 450);
    expect(await mgr.readAll(), hasLength(450));
  });

  test('readRecent 按最新在前返回', () async {
    await mgr.appendRecords([for (var i = 0; i < 250; i++) record(i)]);
    final recent = await mgr.readRecent(50);
    expect(recent, hasLength(50));
    expect(recent.first['id'], '249');
    expect(recent.last['id'], '200');
  });

  test('pushAll 覆盖既有分片', () async {
    await mgr.appendRecords([for (var i = 0; i < 250; i++) record(i)]);
    await mgr.pushAll([record(999)]);
    final all = await mgr.readAll();
    expect(all, hasLength(1));
    expect(all.single['id'], '999');
    expect((await mgr.loadMeta()).shardCount, 1);
  });

  test('deleteAll 清空分片与 meta', () async {
    await mgr.appendRecords([record(1)]);
    await mgr.deleteAll();
    expect(await mgr.readAll(), isEmpty);
    expect(api.store.containsKey('${mgr.keyPrefix}.meta'), isFalse);
  });
}
