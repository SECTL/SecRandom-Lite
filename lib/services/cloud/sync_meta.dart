/// 同步元数据
///
/// 记录同步状态、时间戳和数据校验和，用于增量同步和冲突检测。
class SyncMeta {
  SyncMeta({
    this.schemaVersion = 1,
    this.lastPushAt,
    this.lastPullAt,
    this.deviceId,
    this.lastPushDeviceId,
    this.lastPushDeviceName,
    Map<String, String>? dataChecksums,
    Map<String, int>? historyPushedCount,
  })  : dataChecksums = dataChecksums != null
          ? Map<String, String>.from(dataChecksums)
          : <String, String>{},
        historyPushedCount = historyPushedCount != null
          ? Map<String, int>.from(historyPushedCount)
          : <String, int>{};

  final int schemaVersion;
  DateTime? lastPushAt;
  DateTime? lastPullAt;
  String? deviceId;

  /// 最后一次推送数据的设备 ID（用于冲突检测）
  String? lastPushDeviceId;

  /// 最后一次推送数据的设备名称（用于 UI 展示）
  String? lastPushDeviceName;

  /// 各数据类型的 checksum（sha256 hex）
  Map<String, String> dataChecksums;

  /// 各类历史已推送条数（用于增量推送）
  Map<String, int> historyPushedCount;

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'last_push_at': lastPushAt?.toIso8601String(),
        'last_pull_at': lastPullAt?.toIso8601String(),
        'device_id': deviceId,
        'last_push_device_id': lastPushDeviceId,
        'last_push_device_name': lastPushDeviceName,
        'data_checksums': dataChecksums,
        'history_pushed_count': historyPushedCount,
      };

  factory SyncMeta.fromJson(Map<String, dynamic> json) {
    return SyncMeta(
      schemaVersion: json['schema_version'] as int? ?? 1,
      lastPushAt: json['last_push_at'] != null
          ? DateTime.tryParse(json['last_push_at'] as String)
          : null,
      lastPullAt: json['last_pull_at'] != null
          ? DateTime.tryParse(json['last_pull_at'] as String)
          : null,
      deviceId: json['device_id'] as String?,
      lastPushDeviceId: json['last_push_device_id'] as String?,
      lastPushDeviceName: json['last_push_device_name'] as String?,
      dataChecksums: Map<String, String>.from(
        (json['data_checksums'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            ) ??
            {},
      ),
      historyPushedCount: Map<String, int>.from(
        (json['history_pushed_count'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v as int? ?? 0),
            ) ??
            {},
      ),
    );
  }

  static const String kvKey = 'secrandom.sync.meta';
}
