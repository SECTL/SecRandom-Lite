import 'dart:math';

import '../models/draw_stats.dart';
import '../models/history_record.dart';
import '../models/student.dart';
import 'fair_weight_service.dart';

class FairDrawService {
  FairDrawService({Random? random, FairWeightService? fairWeightService})
    : _random = random ?? Random.secure(),
      _fairWeightService = fairWeightService ?? FairWeightService();

  final Random _random;
  final FairWeightService _fairWeightService;

  List<Student> draw({
    required List<Student> candidates,
    List<HistoryRecord>? classHistory,
    DrawStats? stats,
    required int count,
    FairDrawSettings settings = FairDrawSettings.defaults,
  }) {
    if (count <= 0 || candidates.isEmpty) {
      return [];
    }

    final drawCount = min(count, candidates.length);
    final studentCounts = stats != null
        ? _fairWeightService.buildDrawCountsFromStats(candidates, stats)
        : _fairWeightService.buildDrawCounts(candidates, classHistory ?? []);

    // Select from the least-drawn frontier, updating virtual counts after
    // every pick. Random tie-breaking keeps equal-count candidates unbiased.
    final remaining = List<Student>.from(candidates);
    final virtualCounts = <String, int>{
      for (final student in remaining)
        student.name: studentCounts[student.name] ?? 0,
    };
    final result = <Student>[];

    for (int i = 0; i < drawCount && remaining.isNotEmpty; i++) {
      final minCount = virtualCounts.values.reduce(min);
      final frontier = remaining
          .where((student) => virtualCounts[student.name] == minCount)
          .toList();
      frontier.shuffle(_random);
      final selected = frontier.first;
      result.add(selected);
      remaining.removeWhere((student) => student.id == selected.id);
      virtualCounts[selected.name] = minCount + 1;
    }

    return result;
  }
}
