import 'dart:math';

import '../models/draw_stats.dart';
import '../models/history_record.dart';
import '../models/student.dart';

class FairDrawSettings {
  static const FairDrawSettings defaults = FairDrawSettings(
    baseWeight: 1.0,
    minWeight: 0.5,
    maxWeight: 5.0,
    frequencyFunction: 1,
    frequencyWeight: 1.0,
    groupWeight: 0.8,
    genderWeight: 0.8,
    timeWeight: 0.5,
    enableAvgGapProtection: false,
    gapThreshold: 1,
    minPoolSize: 5,
  );

  final double baseWeight;
  final double minWeight;
  final double maxWeight;
  final int frequencyFunction;
  final double frequencyWeight;
  final double groupWeight;
  final double genderWeight;
  final double timeWeight;
  final bool enableAvgGapProtection;
  final int gapThreshold;
  final int minPoolSize;

  const FairDrawSettings({
    required this.baseWeight,
    required this.minWeight,
    required this.maxWeight,
    required this.frequencyFunction,
    required this.frequencyWeight,
    required this.groupWeight,
    required this.genderWeight,
    required this.timeWeight,
    required this.enableAvgGapProtection,
    required this.gapThreshold,
    required this.minPoolSize,
  });
}

class FairWeightService {
  static final RegExp _nameDelimiter = RegExp(r'[,，]');

  Map<String, int> buildDrawCounts(
    List<Student> students,
    List<HistoryRecord> history,
  ) {
    final Map<String, int> counts = {
      for (final student in students) student.name: 0,
    };

    for (final record in history) {
      final names = record.name
          .split(_nameDelimiter)
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty);
      for (final name in names) {
        if (counts.containsKey(name)) {
          counts[name] = (counts[name] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  /// 从聚合统计构建抽取次数（不依赖历史记录完整性）
  Map<String, int> buildDrawCountsFromStats(
    List<Student> students,
    DrawStats stats,
  ) {
    return {
      for (final student in students) student.name: stats.countOf(student.name),
    };
  }

  Map<String, double> computeCurrentWeights({
    required List<Student> students,
    List<HistoryRecord>? history,
    DrawStats? stats,
    FairDrawSettings settings = FairDrawSettings.defaults,
  }) {
    if (students.isEmpty) {
      return {};
    }

    final counts = stats != null
        ? buildDrawCountsFromStats(students, stats)
        : buildDrawCounts(students, history ?? []);
    final maxTotalCount = counts.values.isEmpty ? 0 : counts.values.reduce(max);
    final Map<String, double> weights = {};

    for (final student in students) {
      final totalCount = counts[student.name] ?? 0;
      final frequencyFactor = _calculateFrequencyFactor(
        functionType: settings.frequencyFunction,
        totalCount: totalCount,
        maxTotalCount: maxTotalCount,
      );

      double totalWeight =
          settings.baseWeight + (frequencyFactor * settings.frequencyWeight);
      totalWeight = totalWeight.clamp(settings.minWeight, settings.maxWeight);

      weights[student.name] = _roundTo2(totalWeight);
    }
    return weights;
  }

  List<Student> applyAvgGapProtection({
    required List<Student> candidates,
    required Map<String, int> studentCounts,
    required int drawCount,
    FairDrawSettings settings = FairDrawSettings.defaults,
  }) {
    if (candidates.isEmpty || !settings.enableAvgGapProtection) {
      return List<Student>.from(candidates);
    }

    final counts = candidates
        .map((s) => studentCounts[s.name] ?? 0)
        .toList(growable: false);
    if (counts.isEmpty) {
      return List<Student>.from(candidates);
    }

    final avg = counts.reduce((a, b) => a + b) / counts.length;
    final minCount = counts.reduce(min);
    final maxCount = counts.reduce(max);

    List<Student> poolInitial = candidates
        .where((s) => (studentCounts[s.name] ?? 0) <= avg)
        .toList();

    if (maxCount - minCount > settings.gapThreshold) {
      final filtered = candidates
          .where((s) => (studentCounts[s.name] ?? 0) < maxCount)
          .toList();
      if (filtered.isNotEmpty) {
        final filteredCounts = filtered
            .map((s) => studentCounts[s.name] ?? 0)
            .toList(growable: false);
        final filteredAvg =
            filteredCounts.reduce((a, b) => a + b) / filteredCounts.length;
        poolInitial = filtered
            .where((s) => (studentCounts[s.name] ?? 0) <= filteredAvg)
            .toList();
      }
    }

    final requiredSize = max(drawCount, settings.minPoolSize);
    if (poolInitial.length < requiredSize) {
      int threshold = avg.ceil();
      List<Student> expanded = candidates
          .where((s) => (studentCounts[s.name] ?? 0) <= threshold)
          .toList();

      while (expanded.length < requiredSize && threshold < maxCount) {
        threshold += 1;
        expanded = candidates
            .where((s) => (studentCounts[s.name] ?? 0) <= threshold)
            .toList();
      }

      if (expanded.length < requiredSize) {
        expanded = List<Student>.from(candidates);
      }

      final sorted = _sortByCount(expanded, studentCounts);
      poolInitial = sorted.length > requiredSize
          ? sorted.take(requiredSize).toList()
          : sorted;
    }

    if (poolInitial.isEmpty) {
      return _sortByCount(List<Student>.from(candidates), studentCounts);
    }
    return poolInitial;
  }

  double _calculateFrequencyFactor({
    required int functionType,
    required int totalCount,
    required int maxTotalCount,
  }) {
    if (functionType == 0) {
      return (maxTotalCount - totalCount + 1) / (maxTotalCount + 1);
    }
    if (functionType == 2) {
      if (maxTotalCount == 0) {
        return 1.0;
      }
      return exp((maxTotalCount - totalCount) / maxTotalCount);
    }
    return sqrt(maxTotalCount + 1) / sqrt(totalCount + 1);
  }

  List<Student> _sortByCount(List<Student> students, Map<String, int> counts) {
    students.sort((a, b) {
      final countCompare = (counts[a.name] ?? 0).compareTo(counts[b.name] ?? 0);
      if (countCompare != 0) {
        return countCompare;
      }
      return a.id.compareTo(b.id);
    });
    return students;
  }

  double _roundTo2(double value) {
    return (value * 100).round() / 100;
  }
}
