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

/// 本地同步状态（data/sync_state.json）
class LocalSyncState {
  LocalSyncState({
    Map<String, int>? ownSeq,
    Map<String, DateTime>? clearedAt,
    Map<String, Map<String, SyncCursor>>? pulled,
    Map<String, int>? ownRollcallStats,
    Map<String, int>? ownLotteryStats,
    this.legacyUploaded = false,
  })  : ownSeq = Map<String, int>.from(ownSeq ?? {}),
        clearedAt = Map<String, DateTime>.from(clearedAt ?? {}),
        pulled = {
          for (final e in (pulled ?? {}).entries)
            e.key: Map<String, SyncCursor>.from(e.value)
        },
        ownRollcallStats = Map<String, int>.from(ownRollcallStats ?? {}),
        ownLotteryStats = Map<String, int>.from(ownLotteryStats ?? {});

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
    return LocalSyncState(
      ownSeq: ((json['own_seq'] as Map?) ?? {})
          .map((k, v) => MapEntry(k.toString(), v as int? ?? 0)),
      clearedAt: ((json['cleared_at'] as Map?) ?? {}).map((k, v) => MapEntry(
            k.toString(),
            DateTime.tryParse(v.toString()) ??
                DateTime.fromMillisecondsSinceEpoch(0),
          )),
      pulled: pulled,
      ownRollcallStats: ((json['own_rollcall_stats'] as Map?) ?? {})
          .map((k, v) => MapEntry(k.toString(), v as int? ?? 0)),
      ownLotteryStats: ((json['own_lottery_stats'] as Map?) ?? {})
          .map((k, v) => MapEntry(k.toString(), v as int? ?? 0)),
      legacyUploaded: json['legacy_uploaded'] as bool? ?? false,
    );
  }
}

/// 待上传队列（data/sync_outbox.json），存 toJson 后的原始 map
class SyncOutbox {
  SyncOutbox({
    List<Map<String, dynamic>>? rollcall,
    List<Map<String, dynamic>>? lottery,
  })  : rollcall = List<Map<String, dynamic>>.from(rollcall ?? []),
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

  Map<String, dynamic> toJson() => {
        'rollcall': rollcall,
        'lottery': lottery,
      };

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
