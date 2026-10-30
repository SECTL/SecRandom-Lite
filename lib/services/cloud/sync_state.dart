/// 某远程设备某 kind 的拉取游标：
/// shard 内已消费 count 条；尾片增长时从 count 继续读。
class SyncCursor {
  const SyncCursor({this.shard = 0, this.count = 0});

  final int shard;
  final int count;

  Map<String, dynamic> toJson() => {'shard': shard, 'count': count};

  factory SyncCursor.fromJson(Map<String, dynamic> json) => SyncCursor(
    shard: json['shard'] as int? ?? 0,
    count: json['count'] as int? ?? 0,
  );
}

/// 学生墓碑：uid -> 删除修订。
class StudentTombstone {
  const StudentTombstone({
    required this.rev,
    required this.by,
    required this.at,
  });

  final int rev;
  final String by;
  final DateTime at;

  Map<String, dynamic> toJson() => {
    'rev': rev,
    'by': by,
    'at': at.toIso8601String(),
  };

  factory StudentTombstone.fromJson(Map<String, dynamic> json) =>
      StudentTombstone(
        rev: json['rev'] is int
            ? json['rev'] as int
            : int.tryParse(json['rev']?.toString() ?? '') ?? 0,
        by: json['by']?.toString() ?? '',
        at:
            DateTime.tryParse(json['at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// 云端清空文档（`srlite.clear.v2`）。
///
/// 全局清空与按班级/奖池清空分别记录时间；合并时同一范围取较晚时间。
class CloudClearState {
  const CloudClearState({
    this.rollcallAll,
    this.lotteryAll,
    this.rollcallClasses = const {},
    this.lotteryPools = const {},
  });

  final DateTime? rollcallAll;
  final DateTime? lotteryAll;
  final Map<String, DateTime> rollcallClasses;
  final Map<String, DateTime> lotteryPools;

  bool get isEmpty =>
      rollcallAll == null &&
      lotteryAll == null &&
      rollcallClasses.isEmpty &&
      lotteryPools.isEmpty;

  /// 点名某班级实际生效的清空时间（全局与班级取较晚者）。
  DateTime? rollcallClearedAt(String className) =>
      _later(rollcallAll, rollcallClasses[className]);

  /// 抽奖某奖池实际生效的清空时间（全局与奖池取较晚者）。
  DateTime? lotteryClearedAt(String poolName) =>
      _later(lotteryAll, lotteryPools[poolName]);

  Map<String, dynamic> toJson() => {
    'rollcall': {
      if (rollcallAll != null) 'all': rollcallAll!.toIso8601String(),
      'classes': rollcallClasses.map(
        (name, at) => MapEntry(name, at.toIso8601String()),
      ),
    },
    'lottery': {
      if (lotteryAll != null) 'all': lotteryAll!.toIso8601String(),
      'pools': lotteryPools.map(
        (pool, at) => MapEntry(pool, at.toIso8601String()),
      ),
    },
  };

  factory CloudClearState.fromJson(Map<String, dynamic> json) {
    final rollcall = json['rollcall'];
    final lottery = json['lottery'];
    return CloudClearState(
      rollcallAll: _parseTime(rollcall is Map ? rollcall['all'] : null),
      lotteryAll: _parseTime(lottery is Map ? lottery['all'] : null),
      rollcallClasses: _parseTimeMap(
        rollcall is Map ? rollcall['classes'] : null,
      ),
      lotteryPools: _parseTimeMap(lottery is Map ? lottery['pools'] : null),
    );
  }

  factory CloudClearState.fromLocalState(LocalSyncState state) =>
      CloudClearState(
        rollcallAll: state.clearedAt['rollcall'],
        lotteryAll: state.clearedAt['lottery'],
        rollcallClasses: Map<String, DateTime>.from(
          state.clearedClasses['rollcall'] ?? const {},
        ),
        lotteryPools: Map<String, DateTime>.from(state.clearedPools),
      );

  /// 把合并后的清空文档写回本地同步状态。
  void applyTo(LocalSyncState state) {
    _putOrRemove(state.clearedAt, 'rollcall', rollcallAll);
    _putOrRemove(state.clearedAt, 'lottery', lotteryAll);
    state.clearedClasses['rollcall'] = Map<String, DateTime>.from(
      rollcallClasses,
    );
    state.clearedPools
      ..clear()
      ..addAll(lotteryPools);
  }

  bool semanticallyEquals(CloudClearState other) =>
      rollcallAll == other.rollcallAll &&
      lotteryAll == other.lotteryAll &&
      _timeMapsEqual(rollcallClasses, other.rollcallClasses) &&
      _timeMapsEqual(lotteryPools, other.lotteryPools);

  static DateTime? _parseTime(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static Map<String, DateTime> _parseTimeMap(Object? value) {
    if (value is! Map) return const {};
    final result = <String, DateTime>{};
    for (final entry in value.entries) {
      final at = _parseTime(entry.value);
      if (at != null) result[entry.key.toString()] = at;
    }
    return result;
  }

  static void _putOrRemove(
    Map<String, DateTime> map,
    String key,
    DateTime? value,
  ) {
    if (value == null) {
      map.remove(key);
    } else {
      map[key] = value;
    }
  }

  static bool _timeMapsEqual(Map<String, DateTime> a, Map<String, DateTime> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}

DateTime? _later(DateTime? a, DateTime? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.isAfter(b) ? a : b;
}

Map<String, DateTime> _laterMap(
  Map<String, DateTime> a,
  Map<String, DateTime> b,
) {
  final result = <String, DateTime>{...a};
  for (final entry in b.entries) {
    final current = result[entry.key];
    if (current == null || entry.value.isAfter(current)) {
      result[entry.key] = entry.value;
    }
  }
  return result;
}

/// 合并两份清空文档：同一范围取较晚时间。
CloudClearState mergeClearStates(CloudClearState a, CloudClearState b) =>
    CloudClearState(
      rollcallAll: _later(a.rollcallAll, b.rollcallAll),
      lotteryAll: _later(a.lotteryAll, b.lotteryAll),
      rollcallClasses: _laterMap(a.rollcallClasses, b.rollcallClasses),
      lotteryPools: _laterMap(a.lotteryPools, b.lotteryPools),
    );

/// 本地同步状态（data/sync_state.json）
class LocalSyncState {
  LocalSyncState({
    Map<String, int>? ownSeq,
    Map<String, DateTime>? clearedAt,
    Map<String, Map<String, SyncCursor>>? pulled,
    Map<String, int>? ownRollcallStats,
    Map<String, int>? ownLotteryStats,
    this.legacyUploaded = false,
    this.baselineInitialized = false,
    this.studentClock = 0,
    this.studentSeq = 0,
    this.studentsDirty = false,
    Map<String, StudentTombstone>? studentTombstones,
    this.clearsDirty = false,
    Map<String, Map<String, DateTime>>? clearedClasses,
    Map<String, DateTime>? clearedPools,
  }) : ownSeq = Map<String, int>.from(ownSeq ?? {}),
       clearedAt = Map<String, DateTime>.from(clearedAt ?? {}),
       pulled = {
         for (final e in (pulled ?? {}).entries)
           e.key: Map<String, SyncCursor>.from(e.value),
       },
       ownRollcallStats = Map<String, int>.from(ownRollcallStats ?? {}),
       ownLotteryStats = Map<String, int>.from(ownLotteryStats ?? {}),
       studentTombstones = Map<String, StudentTombstone>.from(
         studentTombstones ?? {},
       ),
       clearedClasses = {
         for (final e in (clearedClasses ?? {}).entries)
           e.key: Map<String, DateTime>.from(e.value),
       },
       clearedPools = Map<String, DateTime>.from(clearedPools ?? {});

  /// kind -> 已分配的最大本地序号
  final Map<String, int> ownSeq;

  /// kind -> 本机清空时间（拉取时过滤更早记录）
  final Map<String, DateTime> clearedAt;

  /// 远程 deviceId -> kind -> 游标
  final Map<String, Map<String, SyncCursor>> pulled;

  /// 本机统计贡献
  final Map<String, int> ownRollcallStats;
  final Map<String, int> ownLotteryStats;

  /// 旧记录是否已一次性补传
  bool legacyUploaded;

  /// 本地是否已经完成过一次登录初始同步（云端基线或双向并集）
  bool baselineInitialized;

  /// 学生 Lamport 修订计数器
  int studentClock;

  /// 本机学生 uid 序号
  int studentSeq;

  /// 学生名单是否有尚未同步的本地修改
  bool studentsDirty;

  /// uid -> 删除墓碑
  final Map<String, StudentTombstone> studentTombstones;

  /// 清空文档是否有尚未同步的本地修改
  bool clearsDirty;

  /// kind -> className -> 清空时间
  final Map<String, Map<String, DateTime>> clearedClasses;

  /// 抽奖奖池 -> 清空时间
  final Map<String, DateTime> clearedPools;

  Map<String, dynamic> toJson() => {
    'own_seq': ownSeq,
    'cleared_at': clearedAt.map((k, v) => MapEntry(k, v.toIso8601String())),
    'pulled': pulled.map(
      (device, kinds) =>
          MapEntry(device, kinds.map((k, c) => MapEntry(k, c.toJson()))),
    ),
    'own_rollcall_stats': ownRollcallStats,
    'own_lottery_stats': ownLotteryStats,
    'legacy_uploaded': legacyUploaded,
    'baseline_initialized': baselineInitialized,
    'student_clock': studentClock,
    'student_seq': studentSeq,
    'students_dirty': studentsDirty,
    'student_tombstones': studentTombstones.map(
      (uid, tombstone) => MapEntry(uid, tombstone.toJson()),
    ),
    'clears_dirty': clearsDirty,
    'cleared_classes': clearedClasses.map(
      (kind, classes) => MapEntry(
        kind,
        classes.map((name, at) => MapEntry(name, at.toIso8601String())),
      ),
    ),
    'cleared_pools': clearedPools.map(
      (pool, at) => MapEntry(pool, at.toIso8601String()),
    ),
  };

  factory LocalSyncState.fromJson(Map<String, dynamic> json) {
    final pulled = <String, Map<String, SyncCursor>>{};
    (json['pulled'] as Map?)?.forEach((device, kinds) {
      final map = <String, SyncCursor>{};
      (kinds as Map?)?.forEach((kind, cursor) {
        if (cursor is Map) {
          map[kind.toString()] = SyncCursor.fromJson(
            cursor.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
      });
      pulled[device.toString()] = map;
    });

    final tombstones = <String, StudentTombstone>{};
    (json['student_tombstones'] as Map?)?.forEach((uid, raw) {
      if (raw is Map) {
        tombstones[uid.toString()] = StudentTombstone.fromJson(
          raw.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    });

    final clearedClasses = <String, Map<String, DateTime>>{};
    (json['cleared_classes'] as Map?)?.forEach((kind, classes) {
      if (classes is Map) {
        clearedClasses[kind.toString()] = {
          for (final entry in classes.entries)
            entry.key.toString():
                DateTime.tryParse(entry.value.toString()) ??
                DateTime.fromMillisecondsSinceEpoch(0),
        };
      }
    });

    return LocalSyncState(
      ownSeq: ((json['own_seq'] as Map?) ?? {}).map(
        (k, v) => MapEntry(k.toString(), v as int? ?? 0),
      ),
      clearedAt: ((json['cleared_at'] as Map?) ?? {}).map(
        (k, v) => MapEntry(
          k.toString(),
          DateTime.tryParse(v.toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0),
        ),
      ),
      pulled: pulled,
      ownRollcallStats: ((json['own_rollcall_stats'] as Map?) ?? {}).map(
        (k, v) => MapEntry(k.toString(), v as int? ?? 0),
      ),
      ownLotteryStats: ((json['own_lottery_stats'] as Map?) ?? {}).map(
        (k, v) => MapEntry(k.toString(), v as int? ?? 0),
      ),
      legacyUploaded: json['legacy_uploaded'] as bool? ?? false,
      baselineInitialized: json['baseline_initialized'] as bool? ?? false,
      studentClock: json['student_clock'] as int? ?? 0,
      studentSeq: json['student_seq'] as int? ?? 0,
      studentsDirty: json['students_dirty'] as bool? ?? false,
      studentTombstones: tombstones,
      clearsDirty: json['clears_dirty'] as bool? ?? false,
      clearedClasses: clearedClasses,
      clearedPools: ((json['cleared_pools'] as Map?) ?? {}).map(
        (k, v) => MapEntry(
          k.toString(),
          DateTime.tryParse(v.toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0),
        ),
      ),
    );
  }
}

/// 待上传队列（data/sync_outbox.json），存 toJson 后的原始 map
class SyncOutbox {
  SyncOutbox({
    List<Map<String, dynamic>>? rollcall,
    List<Map<String, dynamic>>? lottery,
  }) : rollcall = List<Map<String, dynamic>>.from(rollcall ?? []),
       lottery = List<Map<String, dynamic>>.from(lottery ?? []);

  final List<Map<String, dynamic>> rollcall;
  final List<Map<String, dynamic>> lottery;

  bool get isEmpty => rollcall.isEmpty && lottery.isEmpty;
  int get length => rollcall.length + lottery.length;

  List<Map<String, dynamic>> forKind(String kind) =>
      kind == 'rollcall' ? rollcall : lottery;

  void removeUids(String kind, Set<String> uids) {
    forKind(kind).removeWhere((r) => uids.contains(r['uid']));
  }

  Map<String, dynamic> toJson() => {'rollcall': rollcall, 'lottery': lottery};

  factory SyncOutbox.fromJson(Map<String, dynamic> json) => SyncOutbox(
    rollcall: ((json['rollcall'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList(),
    lottery: ((json['lottery'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList(),
  );
}
