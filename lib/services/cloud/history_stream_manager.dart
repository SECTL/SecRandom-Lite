import 'dart:convert';

import 'cloud_api.dart';
import 'sync_identity.dart';
import 'sync_state.dart';

/// 单设备单 kind 的流摘要（云端 meta）
class StreamMeta {
  const StreamMeta({
    this.shards = 0,
    this.total = 0,
    this.lastShardCount = 0,
    this.shardCounts = const [],
    this.updatedAt,
  });

  final int shards;
  final int total;
  final int lastShardCount;

  /// 每个分片在 meta 写入时的记录数；旧 meta 没有该字段时为空。
  final List<int> shardCounts;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
    'shards': shards,
    'total': total,
    'last_shard_count': lastShardCount,
    'shard_counts': shardCounts,
    'updated_at': updatedAt?.toIso8601String(),
  };

  factory StreamMeta.fromJson(Map<String, dynamic> json) => StreamMeta(
    shards: json['shards'] as int? ?? 0,
    total: json['total'] as int? ?? 0,
    lastShardCount: json['last_shard_count'] as int? ?? 0,
    shardCounts:
        (json['shard_counts'] as List?)
            ?.map(
              (value) =>
                  value is int ? value : int.tryParse(value.toString()) ?? 0,
            )
            .toList() ??
        const [],
    updatedAt: json['updated_at'] != null
        ? DateTime.tryParse(json['updated_at'] as String)
        : null,
  );
}

/// 分片缺失或分片记录数少于 meta 声明时抛出。
///
/// 读取端必须放弃本次流拉取、不推进游标；否则缺失分片会被当成空片，
/// 记录永久跳过。
class IncompleteStreamException implements Exception {
  IncompleteStreamException(
    this.kind,
    this.deviceId,
    this.shard, {
    this.expected,
    this.actual,
  });

  final String kind;
  final String deviceId;
  final int shard;
  final int? expected;
  final int? actual;

  @override
  String toString() {
    final detail = expected == null
        ? '分片 $shard 不存在'
        : '分片 $shard 只有 ${actual ?? 0} 条，meta 声明 $expected 条';
    return 'IncompleteStreamException: $kind/$deviceId $detail';
  }
}

/// 每设备 append-only 历史流。
///
/// - 本设备只写自己的 key：`srlite.history.v2.<kind>.<deviceId>.<n>`
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
      'srlite.history.v2.$kind.$targetDeviceId.$index';

  String metaKey(String targetDeviceId) =>
      'srlite.history.v2.$kind.$targetDeviceId.meta';

  Future<StreamMeta> loadMeta(String targetDeviceId) async {
    try {
      final value = await _api.getKvValue(metaKey(targetDeviceId));
      if (value is Map<String, dynamic>) return StreamMeta.fromJson(value);
      if (value is Map) {
        return StreamMeta.fromJson(
          value.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    } on CloudApiException catch (e) {
      if (!e.isNotFound) rethrow;
    }
    return const StreamMeta();
  }

  /// 追加记录到本设备自己的流，返回新摘要
  ///
  /// 写入前先按实际分片重建 meta：如果上一次「分片写成功、meta 写失败」，
  /// 这里会看到真实的分片数和记录数，避免把已有分片当成不存在而覆盖。
  Future<StreamMeta> appendOwn(List<Map<String, dynamic>> records) async {
    final stored = await loadMeta(deviceId);
    final scan = await _scanOwnStream(stored);
    var meta = scan.$1;
    final existingUids = scan.$2;

    final pending = <Map<String, dynamic>>[];
    for (final record in records) {
      final uid = kind == 'rollcall'
          ? ensureHistoryUid(record)
          : ensureLotteryUid(record);
      if (existingUids.add(uid)) {
        pending.add(Map<String, dynamic>.from(record));
      }
    }

    if (pending.isEmpty) {
      // 没有新记录时也顺手修复 meta（分片已写、meta 写失败的自愈路径）。
      if (_metaDiffers(stored, meta)) {
        await _saveMeta(meta);
      }
      return meta;
    }

    while (pending.isNotEmpty) {
      if (meta.shards == 0) {
        meta = StreamMeta(
          shards: 1,
          total: meta.total,
          shardCounts: const [0],
          updatedAt: meta.updatedAt,
        );
        await _writeShard(0, []);
        continue;
      }

      final index = meta.shards - 1;
      final existing = await _readShard(index);
      final bytes = _encodedBytes(existing);
      final tailFull =
          existing.length >= shardTarget ||
          (existing.isNotEmpty && bytes >= maxShardBytes);
      if (tailFull) {
        meta = StreamMeta(
          shards: meta.shards + 1,
          total: meta.total,
          lastShardCount: 0,
          shardCounts: [...meta.shardCounts, 0],
          updatedAt: meta.updatedAt,
        );
        await _writeShard(meta.shards - 1, []);
        continue;
      }

      var written = 0;
      var needsNewShard = false;
      while (pending.isNotEmpty && existing.length < shardTarget) {
        final candidateBytes = _encodedBytes([...existing, pending.first]);
        if (existing.isNotEmpty && candidateBytes > maxShardBytes) {
          needsNewShard = true;
          break;
        }
        existing.add(pending.removeAt(0));
        written++;
      }

      if (written == 0 && needsNewShard) {
        // 当前尾片放不下下一条记录但本身未达字节上限：直接开新片，
        // 否则外层循环会一直读到同一个尾片而死循环。
        meta = StreamMeta(
          shards: meta.shards + 1,
          total: meta.total,
          lastShardCount: 0,
          shardCounts: [...meta.shardCounts, 0],
          updatedAt: meta.updatedAt,
        );
        await _writeShard(meta.shards - 1, []);
        continue;
      }

      if (written > 0) {
        await _writeShard(index, existing);
        final counts = List<int>.from(meta.shardCounts);
        while (counts.length <= index) {
          counts.add(0);
        }
        counts[index] = existing.length;
        meta = StreamMeta(
          shards: meta.shards,
          total: meta.total + written,
          lastShardCount: existing.length,
          shardCounts: counts,
          updatedAt: DateTime.now(),
        );
      }
    }

    await _saveMeta(meta);
    return meta;
  }

  /// 从 [cursor] 续读 [targetDeviceId] 的流，返回新记录与推进后的游标
  ///
  /// 分片缺失或分片记录数少于 meta 声明时抛 [IncompleteStreamException]，
  /// 调用方不得推进游标。尾片只消费到 meta 快照时的计数，快照后新增的
  /// 记录留给下一次读取。
  Future<(List<Map<String, dynamic>>, SyncCursor)> readFrom(
    String targetDeviceId,
    SyncCursor cursor,
  ) async {
    final meta = await loadMeta(targetDeviceId);
    if (meta.shards == 0 || cursor.shard >= meta.shards) {
      return (<Map<String, dynamic>>[], cursor);
    }

    final hasCounts = meta.shardCounts.length == meta.shards;
    final result = <Map<String, dynamic>>[];
    var shard = cursor.shard;
    var count = cursor.count;

    while (shard < meta.shards) {
      final records = await _readShard(shard, targetDeviceId);
      final isTail = shard == meta.shards - 1;
      final expected = hasCounts ? meta.shardCounts[shard] : null;

      if (expected != null && records.length < expected) {
        throw IncompleteStreamException(
          kind,
          targetDeviceId,
          shard,
          expected: expected,
          actual: records.length,
        );
      }

      final int limit;
      if (isTail) {
        if (expected != null) {
          limit = expected;
        } else if (meta.lastShardCount > 0) {
          limit = records.length < meta.lastShardCount
              ? records.length
              : meta.lastShardCount;
        } else {
          limit = records.length;
        }
      } else {
        limit = records.length;
      }

      final end = limit < records.length ? limit : records.length;
      for (var i = count; i < end; i++) {
        result.add(records[i]);
      }

      if (isTail) {
        count = end;
        break;
      }
      shard++;
      count = 0;
    }

    return (result, SyncCursor(shard: shard, count: count));
  }

  // ── 内部 ──────────────────────────────────────────────

  /// 扫描本设备实际存在的分片，返回真实 meta 与已有 uid。
  ///
  /// meta 可能落后于分片（分片写成功、meta 写失败），因此不能只信 meta
  /// 的 shards；从 0 开始顺序探测到第一个不存在的分片为止。
  Future<(StreamMeta, Set<String>)> _scanOwnStream(StreamMeta stored) async {
    final counts = <int>[];
    final uids = <String>{};
    var index = 0;
    while (true) {
      final records = await _tryReadShard(index);
      if (records == null) {
        if (index < stored.shards) {
          // meta 声明存在的分片真的丢了：不能安全追加，交给调用方失败重试。
          throw IncompleteStreamException(kind, deviceId, index);
        }
        break;
      }
      counts.add(records.length);
      for (final record in records) {
        final raw = record['uid'];
        if (raw is String && raw.isNotEmpty) uids.add(raw);
      }
      index++;
    }

    final meta = StreamMeta(
      shards: counts.length,
      total: counts.fold<int>(0, (sum, count) => sum + count),
      lastShardCount: counts.isEmpty ? 0 : counts.last,
      shardCounts: counts,
      updatedAt: stored.updatedAt,
    );
    return (meta, uids);
  }

  bool _metaDiffers(StreamMeta a, StreamMeta b) {
    if (a.shards != b.shards ||
        a.total != b.total ||
        a.lastShardCount != b.lastShardCount ||
        a.shardCounts.length != b.shardCounts.length) {
      return true;
    }
    for (var i = 0; i < a.shardCounts.length; i++) {
      if (a.shardCounts[i] != b.shardCounts[i]) return true;
    }
    return false;
  }

  int _encodedBytes(List<Map<String, dynamic>> records) =>
      utf8.encode(jsonEncode(records)).length;

  Future<List<Map<String, dynamic>>?> _tryReadShard(
    int index, [
    String? targetDeviceId,
  ]) async {
    try {
      final value = await _api.getKvValue(
        shardKey(targetDeviceId ?? deviceId, index),
      );
      if (value is List) {
        return value.whereType<Map<String, dynamic>>().toList();
      }
      return <Map<String, dynamic>>[];
    } on CloudApiException catch (e) {
      if (e.isNotFound) return null;
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _readShard(
    int index, [
    String? targetDeviceId,
  ]) async {
    final records = await _tryReadShard(index, targetDeviceId);
    if (records == null) {
      throw IncompleteStreamException(kind, targetDeviceId ?? deviceId, index);
    }
    return records;
  }

  Future<void> _writeShard(int index, List<Map<String, dynamic>> records) =>
      _api.putKv(key: shardKey(deviceId, index), value: records);

  Future<void> _saveMeta(StreamMeta meta) =>
      _api.putKv(key: metaKey(deviceId), value: meta.toJson());
}
