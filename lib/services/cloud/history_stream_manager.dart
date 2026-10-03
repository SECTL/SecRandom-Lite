import 'dart:convert';

import 'cloud_api.dart';
import 'sync_state.dart';

/// 单设备单 kind 的流摘要（云端 meta）
class StreamMeta {
  const StreamMeta({
    this.shards = 0,
    this.total = 0,
    this.lastShardCount = 0,
    this.updatedAt,
  });

  final int shards;
  final int total;
  final int lastShardCount;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
        'shards': shards,
        'total': total,
        'last_shard_count': lastShardCount,
        'updated_at': updatedAt?.toIso8601String(),
      };

  factory StreamMeta.fromJson(Map<String, dynamic> json) => StreamMeta(
        shards: json['shards'] as int? ?? 0,
        total: json['total'] as int? ?? 0,
        lastShardCount: json['last_shard_count'] as int? ?? 0,
        updatedAt: json['updated_at'] != null
            ? DateTime.tryParse(json['updated_at'] as String)
            : null,
      );
}

/// 每设备 append-only 历史流。
///
/// - 本设备只写自己的 key：`secrandom.history.v2.<kind>.<deviceId>.<n>`
/// - 摘要只写自己的 meta key，推送时不依赖共享注册表
/// - 读取端按 (shard, count) 游标续读，尾片增长不丢
class HistoryStreamManager {
  HistoryStreamManager(this._api, {required this.kind, required this.deviceId});

  static const int shardTarget = 100;
  static const int maxShardBytes = 48 * 1024;

  final SectlCloudApi _api;
  final String kind;
  final String deviceId;

  String shardKey(String targetDeviceId, int index) =>
      'secrandom.history.v2.$kind.$targetDeviceId.$index';

  String metaKey(String targetDeviceId) =>
      'secrandom.history.v2.$kind.$targetDeviceId.meta';

  Future<StreamMeta> loadMeta(String targetDeviceId) async {
    try {
      final value = await _api.getKvValue(metaKey(targetDeviceId));
      if (value is Map<String, dynamic>) return StreamMeta.fromJson(value);
      if (value is Map) {
        return StreamMeta.fromJson(value.map((k, v) => MapEntry(k.toString(), v)));
      }
    } on CloudApiException catch (e) {
      if (!e.isNotFound) rethrow;
    }
    return const StreamMeta();
  }

  /// 追加记录到本设备自己的流，返回新摘要
  Future<StreamMeta> appendOwn(List<Map<String, dynamic>> records) async {
    if (records.isEmpty) return loadMeta(deviceId);

    var meta = await loadMeta(deviceId);
    final pending = List<Map<String, dynamic>>.from(records);

    while (pending.isNotEmpty) {
      if (meta.shards == 0) {
        meta = StreamMeta(shards: 1, total: meta.total, updatedAt: meta.updatedAt);
        await _writeShard(0, []);
        continue;
      }

      final index = meta.shards - 1;
      final existing = await _readShard(index);
      final bytes = _encodedBytes(existing);
      final tailFull = existing.length >= shardTarget ||
          (existing.isNotEmpty && bytes >= maxShardBytes);
      if (tailFull) {
        meta = StreamMeta(
          shards: meta.shards + 1,
          total: meta.total,
          lastShardCount: 0,
          updatedAt: meta.updatedAt,
        );
        await _writeShard(meta.shards - 1, []);
        continue;
      }

      var written = 0;
      while (pending.isNotEmpty && existing.length < shardTarget) {
        final candidateBytes = _encodedBytes([...existing, pending.first]);
        if (existing.isNotEmpty && candidateBytes > maxShardBytes) break;
        existing.add(pending.removeAt(0));
        written++;
      }

      if (written > 0) {
        await _writeShard(index, existing);
        meta = StreamMeta(
          shards: meta.shards,
          total: meta.total + written,
          lastShardCount: existing.length,
          updatedAt: DateTime.now(),
        );
      }
    }

    await _saveMeta(meta);
    return meta;
  }

  /// 从 [cursor] 续读 [targetDeviceId] 的流，返回新记录与推进后的游标
  Future<(List<Map<String, dynamic>>, SyncCursor)> readFrom(
    String targetDeviceId,
    SyncCursor cursor,
  ) async {
    final meta = await loadMeta(targetDeviceId);
    if (meta.shards == 0 || cursor.shard >= meta.shards) {
      return (<Map<String, dynamic>>[], cursor);
    }

    final result = <Map<String, dynamic>>[];
    var shard = cursor.shard;
    var count = cursor.count;

    while (shard < meta.shards) {
      final records = await _readShard(shard, targetDeviceId);
      for (var i = count; i < records.length; i++) {
        result.add(records[i]);
      }
      if (shard == meta.shards - 1) {
        count = records.length;
        break;
      }
      shard++;
      count = 0;
    }

    return (result, SyncCursor(shard: shard, count: count));
  }

  // ── 内部 ──────────────────────────────────────────────

  int _encodedBytes(List<Map<String, dynamic>> records) =>
      utf8.encode(jsonEncode(records)).length;

  Future<List<Map<String, dynamic>>> _readShard(int index,
      [String? targetDeviceId]) async {
    try {
      final value =
          await _api.getKvValue(shardKey(targetDeviceId ?? deviceId, index));
      if (value is List) return value.whereType<Map<String, dynamic>>().toList();
      return [];
    } on CloudApiException catch (e) {
      if (e.isNotFound) return [];
      rethrow;
    }
  }

  Future<void> _writeShard(int index, List<Map<String, dynamic>> records) =>
      _api.putKv(key: shardKey(deviceId, index), value: records);

  Future<void> _saveMeta(StreamMeta meta) =>
      _api.putKv(key: metaKey(deviceId), value: meta.toJson());
}
