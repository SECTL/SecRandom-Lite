import '../../utils/logger.dart';
import 'cloud_api.dart';

/// 分片元数据
class ShardMeta {
  ShardMeta({required this.shardCount, required this.lastShardCount});

  /// 分片总数（编号 0 .. shardCount-1）
  int shardCount;

  /// 最后一个分片中的记录数
  int lastShardCount;

  int get totalRecords => shardCount == 0
      ? 0
      : (shardCount - 1) * HistoryShardManager.shardSize + lastShardCount;

  Map<String, dynamic> toJson() => {
        'shard_count': shardCount,
        'last_shard_count': lastShardCount,
      };

  factory ShardMeta.fromJson(Map<String, dynamic> json) {
    return ShardMeta(
      shardCount: json['shard_count'] as int? ?? 0,
      lastShardCount: json['last_shard_count'] as int? ?? 0,
    );
  }
}

/// 历史分片管理器
///
/// 将历史记录按每 [shardSize] 条一组存入独立 KV 分片。
/// - 分片编号递增不复用，避免多设备读写错位
/// - meta 记录分片数与最后分片记录数
/// - 支持追加写入、全量推送、懒加载读取
class HistoryShardManager {
  HistoryShardManager(this._api, {required this.keyPrefix});

  final SectlCloudApi _api;
  final String keyPrefix;

  /// 每分片最大记录数
  static const int shardSize = 200;

  String _shardKey(int index) => '$keyPrefix.$index';
  String get _metaKey => '$keyPrefix.meta';

  // ── 云端 meta ──────────────────────────────────────────────

  Future<ShardMeta> loadMeta() async {
    try {
      final value = await _api.getKvValue(_metaKey);
      if (value is Map<String, dynamic>) {
        return ShardMeta.fromJson(value);
      }
    } on CloudApiException catch (e) {
      if (!e.isNotFound) rethrow;
    }
    return ShardMeta(shardCount: 0, lastShardCount: 0);
  }

  Future<void> saveMeta(ShardMeta meta) async {
    await _api.putKv(key: _metaKey, value: meta.toJson());
  }

  // ── 追加写入 ──────────────────────────────────────────────

  /// 将一批新记录追加到云端分片
  ///
  /// [records] 为待追加的记录（toJson 后的 Map 列表）
  /// 返回更新后的 meta
  Future<ShardMeta> appendRecords(List<Map<String, dynamic>> records) async {
    if (records.isEmpty) return loadMeta();

    var meta = await loadMeta();
    var remaining = List<Map<String, dynamic>>.from(records);

    while (remaining.isNotEmpty) {
      final shardIndex = meta.shardCount == 0 ? 0 : meta.shardCount - 1;
      final currentCount = meta.shardCount == 0 ? 0 : meta.lastShardCount;
      final capacity = shardSize - currentCount;

      if (capacity <= 0) {
        // 当前分片已满，新开分片
        meta.shardCount += 1;
        meta.lastShardCount = 0;
        continue;
      }

      final take = remaining.length < capacity ? remaining.length : capacity;
      final chunk = remaining.sublist(0, take);
      remaining = remaining.sublist(take);

      // 读取现有分片内容，追加后写回
      final existing = await _readShard(shardIndex);
      existing.addAll(chunk);
      await _writeShard(shardIndex, existing);

      meta.lastShardCount = existing.length;
      if (meta.shardCount == 0) meta.shardCount = 1;
    }

    await saveMeta(meta);
    logger.d('History shard append: $keyPrefix, total=${meta.totalRecords}, shards=${meta.shardCount}');
    return meta;
  }

  // ── 读取 ──────────────────────────────────────────────────

  /// 读取指定分片的记录列表
  Future<List<Map<String, dynamic>>> readShard(int index) => _readShard(index);

  /// 懒加载：读取最后一个分片（最常访问）
  Future<List<Map<String, dynamic>>> readLastShard() async {
    final meta = await loadMeta();
    if (meta.shardCount == 0) return [];
    return _readShard(meta.shardCount - 1);
  }

  /// 按时间倒序懒加载：从最后分片往前取，累计 [limit] 条
  Future<List<Map<String, dynamic>>> readRecent(int limit) async {
    final meta = await loadMeta();
    if (meta.shardCount == 0) return [];

    final result = <Map<String, dynamic>>[];
    for (var i = meta.shardCount - 1; i >= 0 && result.length < limit; i--) {
      final shard = await _readShard(i);
      // 分片内按存储顺序，倒序取
      for (var j = shard.length - 1; j >= 0 && result.length < limit; j--) {
        result.add(shard[j]);
      }
    }
    return result;
  }

  /// 读取全部分片记录（合并，用于全量拉取）
  Future<List<Map<String, dynamic>>> readAll() async {
    final meta = await loadMeta();
    final result = <Map<String, dynamic>>[];
    for (var i = 0; i < meta.shardCount; i++) {
      final shard = await _readShard(i);
      result.addAll(shard);
    }
    return result;
  }

  // ── 删除 ──────────────────────────────────────────────────

  /// 删除所有分片和 meta（清空云端历史）
  Future<void> deleteAll() async {
    final meta = await loadMeta();
    for (var i = 0; i < meta.shardCount; i++) {
      try {
        await _api.deleteKv(_shardKey(i));
      } on CloudApiException catch (e) {
        if (!e.isNotFound) rethrow;
      }
    }
    try {
      await _api.deleteKv(_metaKey);
    } on CloudApiException catch (e) {
      if (!e.isNotFound) rethrow;
    }
    logger.d('History shard delete all: $keyPrefix');
  }

  // ── 全量推送（初始同步 / 冲突覆盖） ───────────────────────────

  /// 将完整历史列表全量推送到云端（覆盖现有分片）
  Future<ShardMeta> pushAll(List<Map<String, dynamic>> records) async {
    await deleteAll();

    var meta = ShardMeta(shardCount: 0, lastShardCount: 0);
    var offset = 0;

    while (offset < records.length) {
      final end = (offset + shardSize).clamp(0, records.length);
      final chunk = records.sublist(offset, end);
      await _writeShard(meta.shardCount, chunk);
      meta.shardCount += 1;
      meta.lastShardCount = chunk.length;
      offset = end;
    }

    if (meta.shardCount > 0) {
      await saveMeta(meta);
    }
    logger.d('History shard pushAll: $keyPrefix, ${records.length} records, ${meta.shardCount} shards');
    return meta;
  }

  // ── 内部方法 ──────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _readShard(int index) async {
    try {
      final value = await _api.getKvValue(_shardKey(index));
      if (value is List) {
        return value.whereType<Map<String, dynamic>>().toList();
      }
      return [];
    } on CloudApiException catch (e) {
      if (e.isNotFound) return [];
      rethrow;
    }
  }

  Future<void> _writeShard(int index, List<Map<String, dynamic>> records) async {
    await _api.putKv(key: _shardKey(index), value: records);
  }
}
