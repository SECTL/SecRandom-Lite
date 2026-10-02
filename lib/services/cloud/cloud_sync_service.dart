import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../models/draw_stats.dart';
import '../../models/history_record.dart';
import '../../models/lottery_record.dart';
import '../../models/student.dart';
import '../../utils/logger.dart';
import 'cloud_api.dart';
import 'history_shard_manager.dart';
import 'sync_meta.dart';

/// 同步状态
enum SyncStatus {
  idle,
  syncing,
  success,
  error,
}

/// 同步方向
enum SyncDirection { push, pull, both }

/// 同步冲突检测结果
class SyncConflict {
  const SyncConflict({
    required this.remoteDeviceName,
    required this.remotePushTime,
    required this.hasLocalChanges,
    required this.hasRemoteChanges,
  });

  final String remoteDeviceName;
  final DateTime? remotePushTime;
  final bool hasLocalChanges;
  final bool hasRemoteChanges;

  bool get isMultiDevice => remoteDeviceName.isNotEmpty && !hasLocalChanges || hasRemoteChanges;
}

/// 云同步服务
///
/// 负责协调聚合统计、学生名单、历史分片的云端同步。
/// 核心原则：本地是 Source of Truth，云是镜像。
class CloudSyncService {
  CloudSyncService({SectlCloudApi? api})
      : _api = api ?? SectlCloudApi() {
    _rollcallShardMgr = HistoryShardManager(_api, keyPrefix: 'secrandom.history.rollcall');
    _lotteryShardMgr = HistoryShardManager(_api, keyPrefix: 'secrandom.history.lottery');
  }

  final SectlCloudApi _api;
  late final HistoryShardManager _rollcallShardMgr;
  late final HistoryShardManager _lotteryShardMgr;

  // ── KV key 常量 ──────────────────────────────────────────

  static const String studentsKey = 'secrandom.students';
  static const String statsRollcallKey = 'secrandom.stats.rollcall';
  static const String statsLotteryKey = 'secrandom.stats.lottery';

  // ── 状态 ──────────────────────────────────────────────────

  SyncStatus _status = SyncStatus.idle;
  String? _lastError;
  DateTime? _lastSyncAt;

  // 重试队列
  int _retryCount = 0;
  Timer? _retryTimer;
  static const int _maxRetries = 8;
  static const Duration _baseRetryDelay = Duration(seconds: 2);

  SyncStatus get status => _status;
  String? get lastError => _lastError;
  DateTime? get lastSyncAt => _lastSyncAt;
  int get retryCount => _retryCount;
  bool get hasPendingRetry => _retryTimer != null;

  // ── 聚合统计同步 ──────────────────────────────────────────

  /// 推送点名聚合统计
  Future<void> pushRollcallStats(DrawStats stats) async {
    await _api.putKv(key: statsRollcallKey, value: stats.toJson());
    logger.d('Pushed rollcall stats: ${stats.toMap().length} students');
  }

  /// 拉取点名聚合统计
  Future<DrawStats> pullRollcallStats() async {
    try {
      final value = await _api.getKvValue(statsRollcallKey);
      if (value is Map<String, dynamic>) {
        return DrawStats.fromJson(value);
      }
    } on CloudApiException catch (e) {
      if (!e.isNotFound) rethrow;
    }
    return DrawStats();
  }

  /// 推送抽奖聚合统计
  Future<void> pushLotteryStats(DrawStats stats) async {
    await _api.putKv(key: statsLotteryKey, value: stats.toJson());
    logger.d('Pushed lottery stats: ${stats.toMap().length} students');
  }

  /// 拉取抽奖聚合统计
  Future<DrawStats> pullLotteryStats() async {
    try {
      final value = await _api.getKvValue(statsLotteryKey);
      if (value is Map<String, dynamic>) {
        return DrawStats.fromJson(value);
      }
    } on CloudApiException catch (e) {
      if (!e.isNotFound) rethrow;
    }
    return DrawStats();
  }

  // ── 增量更新（PATCH field-level） ──────────────────────────

  /// 增量更新单个学生的点名计数
  ///
  /// 使用 PATCH 只传输变化的字段，适合频繁小更新。
  Future<void> patchRollcallCount(String studentName, int count) async {
    await _api.patchKvField(
      key: statsRollcallKey,
      field: studentName,
      value: count,
    );
    logger.d('Patch rollcall count: $studentName = $count');
  }

  /// 批量增量更新点名计数
  Future<void> patchRollcallCounts(Map<String, int> counts) async {
    for (final entry in counts.entries) {
      await _api.patchKvField(
        key: statsRollcallKey,
        field: entry.key,
        value: entry.value,
      );
    }
    logger.d('Patch rollcall counts: ${counts.length} students');
  }

  /// 增量更新单个学生的抽奖计数
  Future<void> patchLotteryCount(String studentName, int count) async {
    await _api.patchKvField(
      key: statsLotteryKey,
      field: studentName,
      value: count,
    );
    logger.d('Patch lottery count: $studentName = $count');
  }

  // ── 学生名单同步 ──────────────────────────────────────────

  /// 推送学生名单
  Future<void> pushStudents(List<Student> students) async {
    final data = students.map((s) => s.toJson()).toList();
    await _api.putKv(key: studentsKey, value: data);
    logger.d('Pushed students: ${students.length}');
  }

  /// 拉取学生名单
  Future<List<Student>> pullStudents() async {
    try {
      final value = await _api.getKvValue(studentsKey);
      if (value is List) {
        return value
            .whereType<Map<String, dynamic>>()
            .map((e) => Student.fromJson(e))
            .toList();
      }
    } on CloudApiException catch (e) {
      if (!e.isNotFound) rethrow;
    }
    return [];
  }

  // ── 历史分片同步 ──────────────────────────────────────────

  /// 追加点名历史记录到云端分片
  Future<void> appendRollcallHistory(List<HistoryRecord> records) async {
    if (records.isEmpty) return;
    final maps = records.map((r) => r.toJson()).toList();
    await _rollcallShardMgr.appendRecords(maps);
  }

  /// 追加抽奖历史记录到云端分片
  Future<void> appendLotteryHistory(List<LotteryRecord> records) async {
    if (records.isEmpty) return;
    final maps = records.map((r) => r.toJson()).toList();
    await _lotteryShardMgr.appendRecords(maps);
  }

  /// 全量推送点名历史（覆盖）
  Future<void> pushAllRollcallHistory(List<HistoryRecord> records) async {
    final maps = records.map((r) => r.toJson()).toList();
    await _rollcallShardMgr.pushAll(maps);
  }

  /// 全量推送抽奖历史（覆盖）
  Future<void> pushAllLotteryHistory(List<LotteryRecord> records) async {
    final maps = records.map((r) => r.toJson()).toList();
    await _lotteryShardMgr.pushAll(maps);
  }

  /// 懒加载点名历史（最近 N 条）
  Future<List<HistoryRecord>> loadRecentRollcallHistory(int limit) async {
    final maps = await _rollcallShardMgr.readRecent(limit);
    return maps.map((e) => HistoryRecord.fromJson(e)).toList();
  }

  /// 全量拉取点名历史
  Future<List<HistoryRecord>> pullAllRollcallHistory() async {
    final maps = await _rollcallShardMgr.readAll();
    return maps.map((e) => HistoryRecord.fromJson(e)).toList();
  }

  /// 全量拉取抽奖历史
  Future<List<LotteryRecord>> pullAllLotteryHistory() async {
    final maps = await _lotteryShardMgr.readAll();
    return maps.map((e) => LotteryRecord.fromJson(e)).toList();
  }

  /// 清空云端点名历史
  Future<void> clearRollcallHistory() => _rollcallShardMgr.deleteAll();

  /// 清空云端抽奖历史
  Future<void> clearLotteryHistory() => _lotteryShardMgr.deleteAll();

  // ── 同步元数据 ──────────────────────────────────────────

  Future<SyncMeta> loadSyncMeta() async {
    try {
      final value = await _api.getKvValue(SyncMeta.kvKey);
      if (value is Map<String, dynamic>) {
        return SyncMeta.fromJson(value);
      }
    } on CloudApiException catch (e) {
      if (!e.isNotFound) rethrow;
    }
    return SyncMeta();
  }

  Future<void> saveSyncMeta(SyncMeta meta) async {
    await _api.putKv(key: SyncMeta.kvKey, value: meta.toJson());
  }

  // ── 完整同步流程 ──────────────────────────────────────────

  /// 推送全部核心数据（聚合统计 + 学生名单）
  ///
  /// 通过 checksum 检测变化，无变化则跳过对应推送。
  /// 返回是否成功（无变化也算成功）
  Future<bool> pushCore({
    required DrawStats rollcallStats,
    required DrawStats lotteryStats,
    required List<Student> students,
  }) async {
    _status = SyncStatus.syncing;
    _lastError = null;

    try {
      final meta = await loadSyncMeta();

      final rollcallJson = rollcallStats.toJson();
      final lotteryJson = lotteryStats.toJson();
      final studentsJson = students.map((s) => s.toJson()).toList();

      final rollcallHash = checksum(rollcallJson);
      final lotteryHash = checksum(lotteryJson);
      final studentsHash = checksum(studentsJson);

      final rollcallChanged = meta.dataChecksums['stats_rollcall'] != rollcallHash;
      final lotteryChanged = meta.dataChecksums['stats_lottery'] != lotteryHash;
      final studentsChanged = meta.dataChecksums['students'] != studentsHash;

      if (!rollcallChanged && !lotteryChanged && !studentsChanged) {
        logger.d('Push core: no changes detected, skipping');
        _status = SyncStatus.success;
        _lastSyncAt = DateTime.now();
        return true;
      }

      if (rollcallChanged) await pushRollcallStats(rollcallStats);
      if (lotteryChanged) await pushLotteryStats(lotteryStats);
      if (studentsChanged) await pushStudents(students);

      final now = DateTime.now();
      meta.lastPushAt = now;
      meta.lastPushDeviceId = meta.deviceId;
      meta.lastPushDeviceName = meta.deviceId != null ? '设备 ${meta.deviceId!.substring(0, 8)}' : '未知设备';
      meta.dataChecksums['stats_rollcall'] = rollcallHash;
      meta.dataChecksums['stats_lottery'] = lotteryHash;
      meta.dataChecksums['students'] = studentsHash;
      await saveSyncMeta(meta);

      _status = SyncStatus.success;
      _lastSyncAt = DateTime.now();
      logger.d('Push core completed');
      return true;
    } catch (e) {
      _status = SyncStatus.error;
      _lastError = e.toString();
      logger.e('Push core failed', error: e);
      return false;
    }
  }

  /// 失败后调度重试（指数退避）
  ///
  /// [operation] 为需要重试的推送操作
  void scheduleRetry(Future<bool> Function() operation) {
    if (_retryCount >= _maxRetries) {
      logger.w('Max retries reached ($_maxRetries), giving up');
      return;
    }

    _retryTimer?.cancel();
    final delayMs = (_baseRetryDelay.inMilliseconds * pow(2, _retryCount)).round();
    final delay = Duration(milliseconds: delayMs.clamp(1000, 60000));
    _retryCount++;

    logger.d('Scheduling retry #$_retryCount in ${delay.inSeconds}s');
    _retryTimer = Timer(delay, () async {
      _retryTimer = null;
      final ok = await operation();
      if (ok) {
        _retryCount = 0;
      } else {
        scheduleRetry(operation);
      }
    });
  }

  /// 取消所有待执行的重试
  void cancelRetries() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryCount = 0;
  }

  /// 拉取全部核心数据
  ///
  /// 返回拉取到的数据和冲突检测结果，失败返回 null
  Future<(CoreSyncData, SyncConflict?)?> pullCore() async {
    _status = SyncStatus.syncing;
    _lastError = null;

    try {
      final meta = await loadSyncMeta();

      // 冲突检测：云端是否由其他设备推送
      SyncConflict? conflict;
      final currentDeviceId = meta.deviceId;
      final remoteDeviceId = meta.lastPushDeviceId;
      if (remoteDeviceId != null && remoteDeviceId != currentDeviceId) {
        conflict = SyncConflict(
          remoteDeviceName: meta.lastPushDeviceName ?? '未知设备',
          remotePushTime: meta.lastPushAt,
          hasLocalChanges: false, // 简化：由调用方判断
          hasRemoteChanges: true,
        );
      }

      final rollcallStats = await pullRollcallStats();
      final lotteryStats = await pullLotteryStats();
      final students = await pullStudents();

      meta.lastPullAt = DateTime.now();
      await saveSyncMeta(meta);

      _status = SyncStatus.success;
      _lastSyncAt = DateTime.now();
      logger.d('Pull core completed: ${students.length} students');
      return (
        CoreSyncData(
          rollcallStats: rollcallStats,
          lotteryStats: lotteryStats,
          students: students,
        ),
        conflict,
      );
    } catch (e) {
      _status = SyncStatus.error;
      _lastError = e.toString();
      logger.e('Pull core failed', error: e);
      return null;
    }
  }

  /// 合并策略：聚合统计取 max（被抽次数只增不减）
  DrawStats mergeStats(DrawStats local, DrawStats remote) {
    final merged = DrawStats(local.toMap());
    merged.mergeMax(remote);
    return merged;
  }

  // ── 工具 ──────────────────────────────────────────────────

  /// 计算数据 checksum
  static String checksum(dynamic data) {
    final jsonStr = jsonEncode(data);
    return sha256.convert(utf8.encode(jsonStr)).toString();
  }
}

/// 核心同步数据包
class CoreSyncData {
  const CoreSyncData({
    required this.rollcallStats,
    required this.lotteryStats,
    required this.students,
  });

  final DrawStats rollcallStats;
  final DrawStats lotteryStats;
  final List<Student> students;
}
