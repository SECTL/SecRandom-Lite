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
import 'student_sync.dart';
import 'sync_identity.dart';
import 'sync_local_store.dart';
import 'sync_state.dart';

/// 同步状态
enum SyncStatus { idle, syncing, success, error }

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
  }) : _api = api ?? SectlCloudApi(),
       _store = store,
       _deviceId = deviceId;

  final SectlCloudApi _api;
  final SyncLocalStore? _store;
  String? _deviceId;
  LocalSyncState? _state;
  SyncLocalStore? _localStoreInstance;
  Set<String>? _discoveredRemoteDevices;
  DateTime? _discoveredRemoteDevicesAt;
  static const Duration _deviceDiscoveryTtl = Duration(minutes: 10);
  Future<void> _outboxLock = Future<void>.value();

  // ── KV key 常量 ──────────────────────────────────────────

  static const String studentsKey = 'srlite.students';
  static const String studentTombstonesKey = 'srlite.students.tombstones';
  static const String clearKey = 'srlite.clear.v2';

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

  static const String registryKey = 'srlite.sync.v2.registry';

  Future<SyncLocalStore> _localStore() async =>
      _store ??
      (_localStoreInstance ??= DataServiceSyncLocalStore(DataService()));

  Future<String> _resolveDeviceId() async {
    if (_deviceId != null && _deviceId!.isNotEmpty) return _deviceId!;
    _deviceId = await TokenManager().getOrCreateDeviceUuid();
    return _deviceId!;
  }

  /// 本机设备 ID（供 AppProvider 在覆盖/生成 uid 时与服务端保持一致，避免降级到 'unknown'）
  Future<String> resolveDeviceId() => _resolveDeviceId();

  Future<LocalSyncState> loadState() async {
    _state ??= await (await _localStore()).loadState();
    return _state!;
  }

  /// 切换本地工作区时清掉所有按工作区缓存的状态。
  ///
  /// 设备 UUID 不在这里重置：它属于整台设备，不随账号变化。
  void resetWorkspaceState() {
    _state = null;
    _localStoreInstance = null;
    _discoveredRemoteDevices = null;
    _discoveredRemoteDevicesAt = null;
    _status = SyncStatus.idle;
    _lastError = null;
    _retryCount = 0;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  Future<void> saveState() async {
    if (_state != null) await (await _localStore()).saveState(_state!);
  }

  Future<SyncOutbox> loadOutbox() async => (await _localStore()).loadOutbox();

  Future<SyncOutbox> _saveOutbox(SyncOutbox outbox) async {
    await (await _localStore()).saveOutbox(outbox);
    return outbox;
  }

  /// outbox 读改写串行锁。
  ///
  /// 上传期间新入队的记录不能被 flush 结束时的旧快照覆盖，所以读取批次、
  /// 网络追加、按本批 UID 删除必须分三段各自持锁。
  Future<T> _withOutboxLock<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _outboxLock = _outboxLock.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  /// 清空待上传队列（登录时云端覆盖本地后调用：本地待推送记录已被云端取代）
  Future<void> clearOutbox() => _withOutboxLock(() async {
    final outbox = await loadOutbox();
    outbox.rollcall.clear();
    outbox.lottery.clear();
    await _saveOutbox(outbox);
  });

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
    await _withOutboxLock(() async {
      final outbox = await loadOutbox();
      outbox.forKind(kind).clear();
      await _saveOutbox(outbox);
    });
    await saveState();
  }

  /// 追加待上传记录（离线可调用）
  Future<void> enqueueRecord(String kind, Map<String, dynamic> record) =>
      enqueueAll(kind, [record]);

  /// 追加待上传记录；按 uid 去重，避免重复补传。
  Future<void> enqueueAll(
    String kind,
    Iterable<Map<String, dynamic>> records,
  ) => _withOutboxLock(() async {
    final outbox = await loadOutbox();
    final target = outbox.forKind(kind);
    final existing = target
        .map((record) => record['uid'])
        .whereType<String>()
        .where((uid) => uid.isNotEmpty)
        .toSet();
    var changed = false;
    for (final record in records) {
      final rawUid = record['uid'];
      final uid = rawUid is String ? rawUid.trim() : '';
      if (uid.isNotEmpty && !existing.add(uid)) continue;
      target.add(record);
      changed = true;
    }
    if (changed) await _saveOutbox(outbox);
  });

  /// 丢弃 outbox 中已存在于云端的记录（按 uid）。
  Future<void> removeFromOutbox(String kind, Set<String> uids) async {
    if (uids.isEmpty) return;
    await _withOutboxLock(() async {
      final outbox = await loadOutbox();
      final before = outbox.forKind(kind).length;
      outbox.removeUids(kind, uids);
      if (outbox.forKind(kind).length != before) {
        await _saveOutbox(outbox);
      }
    });
  }

  /// 丢弃 outbox 中满足条件的记录（清空某班级/奖池时使用）。
  Future<void> removeFromOutboxWhere(
    String kind,
    bool Function(Map<String, dynamic> record) test,
  ) async {
    await _withOutboxLock(() async {
      final outbox = await loadOutbox();
      final before = outbox.forKind(kind).length;
      outbox.forKind(kind).removeWhere(test);
      if (outbox.forKind(kind).length != before) {
        await _saveOutbox(outbox);
      }
    });
  }

  /// 把 outbox 冲洗到自己的流，并更新注册表。
  ///
  /// 网络追加期间不持锁，结束后重新读取最新 outbox，只删除本批已上传的
  /// UID；期间新入队的记录会保留下来，不会被旧快照覆盖。
  Future<void> flushOutbox() async {
    final deviceId = await _resolveDeviceId();

    final batch = <String, List<Map<String, dynamic>>>{};
    await _withOutboxLock(() async {
      final outbox = await loadOutbox();
      if (outbox.isEmpty) return;
      for (final kind in const ['rollcall', 'lottery']) {
        batch[kind] = List<Map<String, dynamic>>.from(outbox.forKind(kind));
      }
    });
    if (batch.values.every((records) => records.isEmpty)) return;

    final uploadedUids = <String, Set<String>>{};
    for (final kind in const ['rollcall', 'lottery']) {
      final records = batch[kind]!;
      if (records.isEmpty) continue;
      final manager = HistoryStreamManager(
        _api,
        kind: kind,
        deviceId: deviceId,
      );
      final meta = await manager.appendOwn(
        List<Map<String, dynamic>>.from(records),
      );
      await _registerStream(deviceId, kind, meta);
      uploadedUids[kind] = records
          .map((record) => record['uid'])
          .whereType<String>()
          .where((uid) => uid.isNotEmpty)
          .toSet();
    }

    await _withOutboxLock(() async {
      final outbox = await loadOutbox();
      for (final entry in uploadedUids.entries) {
        outbox.removeUids(entry.key, entry.value);
      }
      await _saveOutbox(outbox);
    });
    logger.d('Cloud v2: outbox flushed');
  }

  /// 推送统计贡献 + 冲洗 outbox。
  ///
  /// [students] 仅为兼容旧调用保留；学生名单改由 [syncStudents] 先合并再写，
  /// 避免整包覆盖另一端刚修改的名单。
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
      await _api.putKv(
        key: 'srlite.stats.v2.rollcall.$deviceId',
        value: ownRollcall,
      );
      await _api.putKv(
        key: 'srlite.stats.v2.lottery.$deviceId',
        value: ownLottery,
      );
      await _updateRegistryEntry(deviceId, (_) {});
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
    required Future<void> Function(String kind, Map<String, dynamic> json)
    onNewRecord,
  }) async {
    _status = SyncStatus.syncing;
    _lastError = null;
    try {
      final deviceId = await _resolveDeviceId();
      final state = await loadState();
      final registry = await _loadRegistry();
      final devices = await _resolveRemoteDevices(registry);

      final idsByKind = {
        'rollcall': await existingUids('rollcall'),
        'lottery': await existingUids('lottery'),
      };

      var newRecords = 0;
      final incompleteStreams = <IncompleteStreamException>[];
      for (final remoteId in devices) {
        if (remoteId == deviceId) continue;
        for (final kind in const ['rollcall', 'lottery']) {
          final manager = HistoryStreamManager(
            _api,
            kind: kind,
            deviceId: remoteId,
          );
          final cursor = state.pulled[remoteId]?[kind] ?? const SyncCursor();
          final (List<Map<String, dynamic>>, SyncCursor) read;
          try {
            read = await manager.readFrom(remoteId, cursor);
          } on IncompleteStreamException catch (e) {
            // 分片缺失时不推进游标，避免把缺失分片当成空片永久跳过。
            logger.w('Cloud v2 pull 跳过不完整流: $e');
            incompleteStreams.add(e);
            continue;
          }
          final records = read.$1;
          final nextCursor = read.$2;
          if (records.isEmpty) continue;

          final seen = idsByKind[kind]!;
          final clearedAt = state.clearedAt[kind];
          for (final json in records) {
            final uid = kind == 'rollcall'
                ? ensureHistoryUid(json)
                : ensureLotteryUid(json);
            if (seen.contains(uid)) continue;
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
      final cloudStudents = await fetchStudents();
      final clearState = await fetchClearState();

      _status = SyncStatus.success;
      _lastSyncAt = DateTime.now();
      return PullResult(
        newRecords: newRecords,
        rollcallContributions: rollcallContributions,
        lotteryContributions: lotteryContributions,
        students: cloudStudents.students,
        studentTombstones: cloudStudents.tombstones,
        clearState: clearState,
        incompleteStreams: incompleteStreams,
      );
    } catch (e) {
      _status = SyncStatus.error;
      _lastError = e.toString();
      logger.e('Cloud v2 pullAll failed', error: e);
      return null;
    }
  }

  /// 云端是否存在任何同步数据（学生名单 / 任一设备历史流 total>0 / 任一统计贡献非空）
  ///
  /// 供登录初始同步决策：返回 false 表示云端"没有任何数据"，此时应上传本地；
  /// 返回 true 表示云端已有数据，应以云端严格覆盖本地。
  Future<bool> cloudHasAnyData() async {
    // 学生名单或墓碑非空即视为有数据
    final cloudStudents = await fetchStudents();
    if (cloudStudents.students.isNotEmpty ||
        cloudStudents.tombstones.isNotEmpty) {
      return true;
    }
    // 只有清空文档也算有数据：它能删掉另一台设备的旧记录，不能当云端为空。
    if (!(await fetchClearState()).isEmpty) return true;

    final registry = await _loadRegistry();
    final devices = await _resolveRemoteDevices(
      registry,
      refreshDiscovery: true,
    );

    for (final remoteId in devices) {
      // 任一设备任一 kind 的历史流 total>0
      for (final kind in const ['rollcall', 'lottery']) {
        final manager = HistoryStreamManager(
          _api,
          kind: kind,
          deviceId: remoteId,
        );
        final meta = await manager.loadMeta(remoteId);
        if (meta.total > 0) return true;
      }
      // 任一设备统计贡献非空
      if ((await _statsContribution('rollcall', remoteId)).isNotEmpty) {
        return true;
      }
      if ((await _statsContribution('lottery', remoteId)).isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  /// 读取单设备单 kind 的统计贡献（不存在返回空 map）
  Future<Map<String, int>> _statsContribution(
    String kind,
    String deviceId,
  ) async {
    try {
      final value = await _api.getKvValue('srlite.stats.v2.$kind.$deviceId');
      if (value is Map) {
        return value.map(
          (k, v) => MapEntry(
            k.toString(),
            v is int ? v : int.tryParse(v.toString()) ?? 0,
          ),
        );
      }
    } on CloudApiException catch (e) {
      if (!e.isNotFound) rethrow;
    }
    return {};
  }

  /// 全量拉取云端快照（含所有设备的历史、统计与学生名单），用于严格覆盖本地。
  ///
  /// 与 [pullAll] 的增量游标不同，本方法从每个设备流的起点完整读取并按 uid
  /// 去重，返回的记录即"云端的完整状态"。
  Future<CloudFullSnapshot?> pullFullSnapshot() async {
    _status = SyncStatus.syncing;
    _lastError = null;
    try {
      final registry = await _loadRegistry();
      final devices = await _resolveRemoteDevices(
        registry,
        refreshDiscovery: true,
      );

      final rollcallByUid = <String, Map<String, dynamic>>{};
      final lotteryByUid = <String, Map<String, dynamic>>{};
      final rollcallContributions = <String, Map<String, int>>{};
      final lotteryContributions = <String, Map<String, int>>{};

      for (final remoteId in devices) {
        for (final kind in const ['rollcall', 'lottery']) {
          final manager = HistoryStreamManager(
            _api,
            kind: kind,
            deviceId: remoteId,
          );
          // 完整性校验：读到的记录数必须与 meta.total 一致，否则说明分片
          // 静默缺失（not-found 被当空）。严格覆盖宁可放弃本次同步，也不能
          // 用不完整快照覆盖本地造成数据丢失。
          final meta = await manager.loadMeta(remoteId);
          final (records, _) = await manager.readFrom(
            remoteId,
            const SyncCursor(),
          );
          if (records.length != meta.total) {
            throw IncompleteStreamException(
              kind,
              remoteId,
              meta.shards - 1,
              expected: meta.total,
              actual: records.length,
            );
          }
          final target = kind == 'rollcall' ? rollcallByUid : lotteryByUid;
          for (final json in records) {
            final uid = kind == 'rollcall'
                ? ensureHistoryUid(json)
                : ensureLotteryUid(json);
            target[uid] = json;
          }
        }
        rollcallContributions[remoteId] = await _statsContribution(
          'rollcall',
          remoteId,
        );
        lotteryContributions[remoteId] = await _statsContribution(
          'lottery',
          remoteId,
        );
      }

      final cloudStudents = await fetchStudents();
      final clearState = await fetchClearState();

      _status = SyncStatus.success;
      _lastSyncAt = DateTime.now();
      return CloudFullSnapshot(
        rollcallRecords: rollcallByUid.values.toList(),
        lotteryRecords: lotteryByUid.values.toList(),
        rollcallContributions: rollcallContributions,
        lotteryContributions: lotteryContributions,
        students: cloudStudents.students,
        studentTombstones: cloudStudents.tombstones,
        clearState: clearState,
      );
    } catch (e) {
      _status = SyncStatus.error;
      _lastError = e.toString();
      logger.e('Cloud v2 pullFullSnapshot failed', error: e);
      return null;
    }
  }

  /// 全部设备的统计贡献（不含本机）；key: deviceId -> 计数
  Future<Map<String, Map<String, int>>> fetchRemoteStats(String kind) async {
    final deviceId = await _resolveDeviceId();
    final registry = await _loadRegistry();
    final devices = (await _resolveRemoteDevices(
      registry,
    )).where((id) => id != deviceId);
    final result = <String, Map<String, int>>{};
    for (final remoteId in devices) {
      try {
        final value = await _api.getKvValue('srlite.stats.v2.$kind.$remoteId');
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

  Future<List<String>> _resolveRemoteDevices(
    Map<String, dynamic> registry, {
    bool refreshDiscovery = false,
  }) async {
    final devices = <String>{
      ...((registry['devices'] as Map?)?.keys ?? <dynamic>[]).map(
        (key) => key.toString(),
      ),
    };
    devices.addAll(await _discoverRemoteDevices(refresh: refreshDiscovery));
    return devices.toList();
  }

  /// 从历史分片 / 统计键反推设备 ID，补足注册表并发读改写可能丢掉的设备项。
  Future<Set<String>> _discoverRemoteDevices({bool refresh = false}) async {
    final cached = _discoveredRemoteDevices;
    final cachedAt = _discoveredRemoteDevicesAt;
    if (!refresh &&
        cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _deviceDiscoveryTtl) {
      return cached;
    }

    try {
      final devices = <String>{};
      var offset = 0;
      while (true) {
        final page = await _api.listKv(limit: 100, offset: offset);
        for (final entry in page.entries) {
          final key = entry.key;
          final isHistory = key.startsWith('srlite.history.v2.');
          final isStats = key.startsWith('srlite.stats.v2.');
          if (!isHistory && !isStats) continue;
          final parts = key.split('.');
          if (isHistory) {
            if (parts.length < 6) continue;
            if (parts[3] != 'rollcall' && parts[3] != 'lottery') continue;
            final deviceId = parts[4];
            if (deviceId.isNotEmpty) devices.add(deviceId);
          } else {
            if (parts.length < 5) continue;
            if (parts[3] != 'rollcall' && parts[3] != 'lottery') continue;
            final deviceId = parts[4];
            if (deviceId.isNotEmpty) devices.add(deviceId);
          }
        }
        if (!page.hasMore || page.entries.isEmpty) break;
        offset += page.entries.length;
      }
      _discoveredRemoteDevices = devices;
      _discoveredRemoteDevicesAt = DateTime.now();
      return devices;
    } catch (e) {
      logger.w('远端设备发现失败，回退注册表', error: e);
      return cached ?? const <String>{};
    }
  }

  Future<void> _registerStream(String deviceId, String kind, StreamMeta meta) =>
      _updateRegistryEntry(deviceId, (entry) {
        final streams =
            (entry['streams'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v),
            ) ??
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
    final devices =
        (registry['devices'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v),
        ) ??
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
      final backups =
          files
              .where(
                (f) =>
                    (f['filename'] as String? ?? '').startsWith(backupPrefix),
              )
              .toList()
            ..sort(
              (a, b) => (b['filename'] as String? ?? '').compareTo(
                a['filename'] as String? ?? '',
              ),
            );
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

  /// 推送学生名单（旧接口，整包覆盖；新代码请用 [syncStudents]）
  Future<void> pushStudents(List<Student> students) async {
    final data = students.map((s) => s.toJson()).toList();
    await _api.putKv(key: studentsKey, value: data);
    logger.d('Pushed students: ${students.length}');
  }

  /// 拉取学生名单（不含墓碑；需要完整状态请用 [fetchStudents]）
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

  /// 拉取云端学生名单与墓碑。
  Future<CloudStudents> fetchStudents() async {
    final students = await pullStudents();
    final tombstones = <String, StudentTombstone>{};
    try {
      final value = await _api.getKvValue(studentTombstonesKey);
      if (value is Map) {
        for (final entry in value.entries) {
          final raw = entry.value;
          if (raw is! Map) continue;
          tombstones[entry.key.toString()] = StudentTombstone.fromJson(
            raw.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
      }
    } on CloudApiException catch (e) {
      if (!e.isNotFound) rethrow;
    }
    return CloudStudents(students: students, tombstones: tombstones);
  }

  /// 先读云端 → 合并 → 按需写回学生名单与墓碑。
  ///
  /// 这是「先合并再写」的推送，不会整包覆盖另一端刚修改的名单。
  Future<StudentMergeResult> syncStudents({
    required List<Student> local,
    required Map<String, StudentTombstone> localTombstones,
    required String deviceId,
    required int clock,
  }) async {
    final cloud = await fetchStudents();
    var result = mergeStudents(
      local: local,
      localTombstones: localTombstones,
      cloud: cloud.students,
      cloudTombstones: cloud.tombstones,
      deviceId: deviceId,
      studentClock: clock,
    );
    result = _applyTombstoneBudget(result);

    if (result.needsPush) {
      await _api.putKv(
        key: studentsKey,
        value: result.students.map((student) => student.toJson()).toList(),
      );
      await _api.putKv(
        key: studentTombstonesKey,
        value: result.tombstones.map(
          (uid, tombstone) => MapEntry(uid, tombstone.toJson()),
        ),
      );
    }
    return result;
  }

  /// 墓碑超过 32 KiB 时丢弃 365 天前的旧墓碑，避免单个 KV 无限增长。
  StudentMergeResult _applyTombstoneBudget(StudentMergeResult result) {
    final encoded = utf8
        .encode(
          jsonEncode(
            result.tombstones.map(
              (uid, tombstone) => MapEntry(uid, tombstone.toJson()),
            ),
          ),
        )
        .length;
    if (encoded <= 32 * 1024) return result;

    final cutoff = DateTime.now().subtract(const Duration(days: 365));
    final pruned = Map<String, StudentTombstone>.from(result.tombstones)
      ..removeWhere((_, tombstone) => tombstone.at.isBefore(cutoff));
    if (pruned.length == result.tombstones.length) return result;

    return StudentMergeResult(
      students: result.students,
      tombstones: pruned,
      studentClock: result.studentClock,
      changed: true,
      needsPush: true,
    );
  }

  // ── 清空文档 ──────────────────────────────────────────────

  /// 拉取云端清空文档。
  Future<CloudClearState> fetchClearState() async {
    try {
      final value = await _api.getKvValue(clearKey);
      if (value is Map) {
        return CloudClearState.fromJson(
          value.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    } on CloudApiException catch (e) {
      if (!e.isNotFound) rethrow;
    }
    return const CloudClearState();
  }

  /// 合并本地与云端清空文档，并在云端落后时写回。
  Future<CloudClearState> syncClears(CloudClearState local) async {
    final cloud = await fetchClearState();
    final merged = mergeClearStates(local, cloud);
    if (!merged.semanticallyEquals(cloud)) {
      await _api.putKv(key: clearKey, value: merged.toJson());
    }
    return merged;
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
    final delayMs = (_baseRetryDelay.inMilliseconds * pow(2, _retryCount))
        .round();
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

/// 云端学生名单 + 墓碑。
class CloudStudents {
  const CloudStudents({required this.students, required this.tombstones});

  final List<Student> students;
  final Map<String, StudentTombstone> tombstones;
}

/// v2 拉取结果
class PullResult {
  const PullResult({
    required this.newRecords,
    required this.rollcallContributions,
    required this.lotteryContributions,
    required this.students,
    this.studentTombstones = const {},
    this.clearState = const CloudClearState(),
    this.incompleteStreams = const [],
  });

  final int newRecords;
  final Map<String, Map<String, int>> rollcallContributions;
  final Map<String, Map<String, int>> lotteryContributions;
  final List<Student> students;
  final Map<String, StudentTombstone> studentTombstones;
  final CloudClearState clearState;

  /// 本次因分片缺失而跳过的流；对应游标没有被推进，下次可重试。
  final List<IncompleteStreamException> incompleteStreams;
}

/// 云端完整快照：登录时云端有数据，用它严格覆盖本地
class CloudFullSnapshot {
  const CloudFullSnapshot({
    required this.rollcallRecords,
    required this.lotteryRecords,
    required this.rollcallContributions,
    required this.lotteryContributions,
    required this.students,
    this.studentTombstones = const {},
    this.clearState = const CloudClearState(),
  });

  /// 所有设备点名历史并集（按 uid 去重）
  final List<Map<String, dynamic>> rollcallRecords;

  /// 所有设备抽奖历史并集（按 uid 去重）
  final List<Map<String, dynamic>> lotteryRecords;

  /// 全部设备的点名统计贡献；key: deviceId -> 计数
  final Map<String, Map<String, int>> rollcallContributions;

  /// 全部设备的抽奖统计贡献；key: deviceId -> 计数
  final Map<String, Map<String, int>> lotteryContributions;

  /// 学生名单
  final List<Student> students;

  /// 学生删除墓碑
  final Map<String, StudentTombstone> studentTombstones;

  /// 云端清空文档
  final CloudClearState clearState;
}
