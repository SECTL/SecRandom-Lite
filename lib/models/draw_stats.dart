/// 抽取聚合统计：每人被抽中次数
///
/// 独立于历史记录存储，用于公平抽取权重计算和统计展示。
/// 与历史分片解耦：公平抽取只读此统计，不依赖历史是否完整下载。
class DrawStats {
  DrawStats([Map<String, int>? counts]) : _counts = Map<String, int>.from(counts ?? {});

  final Map<String, int> _counts;

  /// 获取某人被抽次数
  int countOf(String name) => _counts[name] ?? 0;

  /// 设置某人被抽次数
  void setCount(String name, int count) {
    if (count <= 0) {
      _counts.remove(name);
    } else {
      _counts[name] = count;
    }
  }

  /// 增加某人被抽次数（新增历史记录时调用）
  void increment(String name, [int delta = 1]) {
    _counts[name] = (_counts[name] ?? 0) + delta;
  }

  /// 批量增加（一次抽取可能有多人）
  void incrementAll(Iterable<String> names, [int delta = 1]) {
    for (final name in names) {
      increment(name, delta);
    }
  }

  /// 获取全部统计
  Map<String, int> toMap() => Map<String, int>.from(_counts);

  /// 合并另一份统计，同名取 max（被抽次数只增不减）
  void mergeMax(DrawStats other) {
    for (final entry in other._counts.entries) {
      final existing = _counts[entry.key] ?? 0;
      if (entry.value > existing) {
        _counts[entry.key] = entry.value;
      }
    }
  }

  /// 从历史记录重建统计（回退路径）
  ///
  /// [historyNames] 为历史记录中的 name 字段列表（可能包含逗号分隔的多人）
  static DrawStats fromHistoryNames(Iterable<String> historyNames) {
    final stats = DrawStats();
    final delimiter = RegExp(r'[,，]');
    for (final raw in historyNames) {
      for (final name in raw.split(delimiter).map((e) => e.trim()).where((e) => e.isNotEmpty)) {
        stats.increment(name);
      }
    }
    return stats;
  }

  /// 序列化
  Map<String, dynamic> toJson() => toMap();

  /// 反序列化
  factory DrawStats.fromJson(Map<String, dynamic> json) {
    final counts = <String, int>{};
    json.forEach((key, value) {
      final v = value is int ? value : int.tryParse(value.toString()) ?? 0;
      if (v > 0) counts[key] = v;
    });
    return DrawStats(counts);
  }

  @override
  String toString() => 'DrawStats(${_counts.length} students)';
}
