import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;

import '../../models/student.dart';
import '../../utils/logger.dart';
import '../auth/token_manager.dart';
import '../data_service.dart';
import 'cloud_api.dart';
import 'history_stream_manager.dart';
import 'sync_local_store.dart';
import 'sync_state.dart';

/// 同步状态
enum SyncStatus {
  idle,
  syncing,
  success,
  error,
}

/// 同步方向
enum SyncDirection { push, pull, both }

/// 云同步服务
///
/// v2：每设备 append-only 历史流 + uid 并集去重；
/// 统计按设备贡献求和；outbox 负责离线补传。
class CloudSyncService {
  CloudSyncService({
    SectlCloudApi? api,
    SyncLocalStore? store,
    String? deviceId,
  })  : _api = api ?? SectlCloudApi(),
        _store = store,
        _deviceId = deviceId;

  final SectlCloudApi _api;
  final SyncLocalStore? _store;
  String? _deviceId;
  LocalSyncState? _state;
  SyncLocalStore? _localStoreInstance;

  // ── KV key 常量 ──────────────────────────────────────────

  static const String studentsKey = 'secrandom.students';

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

  // ── v2：每设备 append-only 流 ────────────────────────────

  static const String registryKey = 'secrandom.sync.v2.registry';

  Future<SyncLocalStore> _localStore() async =>
      _store ?? (_localStoreInstance ??= DataServiceSyncLocalStore(DataService()));

  Future<String> _resolveDeviceId() async {
    if (_deviceId != null && _deviceId!.isNotEmpty) return _deviceId!;
    _deviceId = await TokenManager().getOrCreateDeviceUuid();
    return _deviceId!;
  }

  Future<LocalSyncState> loadState() async {
    _state ??= await (await _localStore()).loadState();
    return _state!;
  }

  Future<void> saveState() async {
    if (_state != null) await (await _localStore()).saveState(_state!);
  }

  Future<SyncOutbox> loadOutbox() async => (await _localStore()).loadOutbox();

  Future<SyncOutbox> _saveOutbox(SyncOutbox outbox) async {
    await (await _localStore()).saveOutbox(outbox);
    return outbox;
  }

  /// 分配本地序号并持久化
  Future<int> nextSeq(String kind) async {
    final state = await loadState();
    final next = (state.ownSeq[kind] ?? 0) + 1;
    state.ownSeq[kind] = next;
    await saveState();
    return next;
  }

  /// 记录本机清空时间并清空该 kind 的 outbox
  Future<void> markCleared(String kind, DateTime at) async {
    final state = await loadState();
    final existing = state.clearedAt[kind];
    if (existing == null || at.isAfter(existing)) state.clearedAt[kind] = at;
    final outbox = await loadOutbox();
    outbox.forKind(kind).clear();
    await _saveOutbox(outbox);
    await saveState();
  }

  /// 追加待上传记录（离线可调用）
  Future<void> enqueueRecord(String kind, Map<String, dynamic> record) async {
    final outbox = await loadOutbox();
    outbox.forKind(kind).add(record);
    await _saveOutbox(outbox);
  }

  Future<void> enqueueAll(String kind, Iterable<Map<String, dynamic>> records) async {
    final outbox = await loadOutbox();
    outbox.forKind(kind).addAll(records);
    await _saveOutbox(outbox);
  }

  /// 把 outbox 冲洗到自己的流，并更新注册表
  Future<void> flushOutbox() async {
    final deviceId = await _resolveDeviceId();
    final outbox = await loadOutbox();
    if (outbox.isEmpty) return;

    for (final kind in const ['rollcall', 'lottery']) {
      final records = outbox.forKind(kind);
      if (records.isEmpty) continue;
      final manager = HistoryStreamManager(_api, kind: kind, deviceId: deviceId);
      final meta = await manager.appendOwn(List<Map<String, dynamic>>.from(records));
      await _registerStream(deviceId, kind, meta);
      records.clear();
      await _saveOutbox(outbox);
    }
    logger.d('Cloud v2: outbox flushed');
  }

  /// 推送统计贡献 + 冲洗 outbox + 可选学生名单
  Future<bool> pushAll({
    required Map<String, int> ownRollcall,
    required Map<String, int> ownLottery,
    List<Student>? students,
  }) async {
    _status = SyncStatus.syncing;
    _lastError = null;
    try {
      final deviceId = await _resolveDeviceId();
      await flushOutbox();
      await _api.putKv(key: 'secrandom.stats.v2.rollcall.$deviceId', value: ownRollcall);
      await _api.putKv(key: 'secrandom.stats.v2.lottery.$deviceId', value: ownLottery);
      await _updateRegistryEntry(deviceId, (_) {});
      if (students != null && students.isNotEmpty) {
        await pushStudents(students);
      }
      _status = SyncStatus.success;
      _lastSyncAt = DateTime.now();
      return true;
    } catch (e) {
      _status = SyncStatus.error;
      _lastError = e.toString();
      logger.e('Cloud v2 pushAll failed', error: e);
      return false;
    }
  }

  /// 拉取：历史（uid 去重 + clearedAt 过滤）→ 统计贡献 → 学生名单
  Future<PullResult?> pullAll({
    required Future<Set<String>> Function(String kind) existingUids,
    required Future<void> Function(String kind, Map<String, dynamic> json) onNewRecord,
  }) async {
    _status = SyncStatus.syncing;
    _lastError = null;
    try {
      final deviceId = await _resolveDeviceId();
      final state = await loadState();
      final registry = await _loadRegistry();
      final devices = ((registry['devices'] as Map?)?.keys ?? <dynamic>[])
          .map((e) => e.toString())
          .toList();

      final idsByKind = {
        'rollcall': await existingUids('rollcall'),
        'lottery': await existingUids('lottery'),
      };

      var newRecords = 0;
      for (final remoteId in devices) {
        if (remoteId == deviceId) continue;
        for (final kind in const ['rollcall', 'lottery']) {
          final manager = HistoryStreamManager(_api, kind: kind, deviceId: remoteId);
          final cursor = state.pulled[remoteId]?[kind] ?? const SyncCursor();
          final (records, nextCursor) = await manager.readFrom(remoteId, cursor);
          if (records.isEmpty) continue;

          final seen = idsByKind[kind]!;
          final clearedAt = state.clearedAt[kind];
          for (final json in records) {
            final uid = json['uid'] as String?;
            if (uid == null || uid.isEmpty || seen.contains(uid)) continue;
            final time = _recordTime(kind, json);
            if (clearedAt != null && time != null && time.isBefore(clearedAt)) {
              continue;
            }
            await onNewRecord(kind, json);
            seen.add(uid);
            newRecords++;
          }
          (state.pulled[remoteId] ??= {})[kind] = nextCursor;
          await saveState();
        }
      }

      final rollcallContributions = await fetchRemoteStats('rollcall');
      final lotteryContributions = await fetchRemoteStats('lottery');
      final students = await pullStudents();

      _status = SyncStatus.success;
      _lastSyncAt = DateTime.now();
      return PullResult(
        newRecords: newRecords,
        rollcallContributions: rollcallContributions,
        lotteryContributions: lotteryContributions,
        students: students,
      );
    } catch (e) {
      _status = SyncStatus.error;
      _lastError = e.toString();
      logger.e('Cloud v2 pullAll failed', error: e);
      return null;
    }
  }

  /// 全部设备的统计贡献（不含本机）；key: deviceId -> 计数
  Future<Map<String, Map<String, int>>> fetchRemoteStats(String kind) async {
    final deviceId = await _resolveDeviceId();
    final registry = await _loadRegistry();
    final devices = ((registry['devices'] as Map?)?.keys ?? <dynamic>[])
        .map((e) => e.toString())
        .where((id) => id != deviceId);
    final result = <String, Map<String, int>>{};
    for (final remoteId in devices) {
      try {
        final value = await _api.getKvValue('secrandom.stats.v2.$kind.$remoteId');
        if (value is Map) {
          result[remoteId] = value.map(
            (k, v) => MapEntry(
              k.toString(),
              v is int ? v : int.tryParse(v.toString()) ?? 0,
            ),
          );
        }
      } on CloudApiException catch (e) {
        if (!e.isNotFound) rethrow;
      }
    }
    return result;
  }

  DateTime? _recordTime(String kind, Map<String, dynamic> json) {
    if (kind == 'rollcall') {
      return DateTime.tryParse(json['draw_time'] as String? ?? '');
    }
    final raw = json['drawTime'] as String?;
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<Map<String, dynamic>> _loadRegistry() async {
    try {
      final value = await _api.getKvValue(registryKey);
      if (value is Map<String, dynamic>) return value;
      if (value is Map) {
        return value.map((k, v) => MapEntry(k.toString(), v));
      }
    } on CloudApiException catch (e) {
      if (!e.isNotFound) rethrow;
    }
    return {'devices': <String, dynamic>{}};
  }

  Future<void> _registerStream(String deviceId, String kind, StreamMeta meta) =>
      _updateRegistryEntry(deviceId, (entry) {
        final streams = (entry['streams'] as Map?)
                ?.map((k, v) => MapEntry(k.toString(), v)) ??
            <String, dynamic>{};
        streams[kind] = meta.toJson();
        entry['streams'] = streams;
      });

  /// 读改写注册表中自己的条目（良性竞态：丢项下次同步自愈）
  Future<void> _updateRegistryEntry(
    String deviceId,
    void Function(Map<String, dynamic> entry) mutate,
  ) async {
    final registry = await _loadRegistry();
    final devices = (registry['devices'] as Map?)
            ?.map((k, v) => MapEntry(k.toString(), v)) ??
        <String, dynamic>{};
    final existing = devices[deviceId];
    final entry = existing is Map
        ? existing.map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};
    mutate(entry);
    entry['updated_at'] = DateTime.now().toIso8601String();
    entry['name'] ??=
        '设备 ${deviceId.length >= 8 ? deviceId.substring(0, 8) : deviceId}';
    entry['platform'] ??= kIsWeb ? 'web' : defaultTargetPlatform.name;
    devices[deviceId] = entry;
    registry['devices'] = devices;
    await _api.putKv(key: registryKey, value: registry);
  }

  // ── 文件备份（整包快照，非增量通道） ──────────────────────

  static const String backupPrefix = 'secrandom-backup-';

  /// 上传完整快照；先删旧备份控制配额
  Future<bool> uploadBackup(Map<String, dynamic> snapshot) async {
    _status = SyncStatus.syncing;
    _lastError = null;
    try {
      final files = await _api.listFiles();
      for (final f in files) {
        final name = f['filename'] as String? ?? '';
        final id = f['file_id'] as String?;
        if (id != null && name.startsWith(backupPrefix)) {
          await _api.deleteFile(id);
        }
      }
      final filename =
          '$backupPrefix${DateTime.now().millisecondsSinceEpoch}.json';
      await _api.uploadFile(
        bytes: utf8.encode(jsonEncode(snapshot)),
        filename: filename,
      );
      _status = SyncStatus.success;
      _lastSyncAt = DateTime.now();
      return true;
    } catch (e) {
      _status = SyncStatus.error;
      _lastError = e.toString();
      logger.e('Backup upload failed', error: e);
      return false;
    }
  }

  /// 下载最近一次备份并解析；无备份返回 null
  Future<Map<String, dynamic>?> downloadLatestBackup() async {
    try {
      final files = await _api.listFiles();
      final backups = files
          .where(
              (f) => (f['filename'] as String? ?? '').startsWith(backupPrefix))
          .toList()
        ..sort((a, b) => (b['filename'] as String? ?? '')
            .compareTo(a['filename'] as String? ?? ''));
      if (backups.isEmpty) return null;
      final fileId = backups.first['file_id'] as String?;
      if (fileId == null) return null;
      final url = await _api.getFileDownloadUrl(fileId);
      final bytes = await _api.downloadFileBytes(url);
      final decoded = jsonDecode(utf8.decode(bytes));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      _lastError = e.toString();
      logger.e('Backup download failed', error: e);
      return null;
    }
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

  /// 失败后调度重试（指数退避）
  ///
  /// [operation] 为需要重试的推送操作
  void scheduleRetry(Future<bool> Function() operation) {
    if (_retryCount >= _maxRetries) {
      logger.w('Max retries reached ($_maxRetries), giving up');
      // 重置计数：本次失败批次已放弃，后续新的失败仍应有退避预算
      _retryCount = 0;
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
}

/// v2 拉取结果
class PullResult {
  const PullResult({
    required this.newRecords,
    required this.rollcallContributions,
    required this.lotteryContributions,
    required this.students,
  });

  final int newRecords;
  final Map<String, Map<String, int>> rollcallContributions;
  final Map<String, Map<String, int>> lotteryContributions;
  final List<Student> students;
}
