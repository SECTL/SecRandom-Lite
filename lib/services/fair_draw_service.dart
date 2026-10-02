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

    try {
      final studentCounts = stats != null
          ? _fairWeightService.buildDrawCountsFromStats(candidates, stats)
          : _fairWeightService.buildDrawCounts(candidates, classHistory ?? []);
      var pool = _fairWeightService.applyAvgGapProtection(
        candidates: candidates,
        studentCounts: studentCounts,
        drawCount: drawCount,
        settings: settings,
      );
      if (pool.isEmpty) {
        pool = List<Student>.from(candidates);
      }

      final weightMap = _fairWeightService.computeCurrentWeights(
        students: pool,
        history: classHistory,
        stats: stats,
        settings: settings,
      );

      final result = <Student>[];
      final mutablePool = List<Student>.from(pool);
      final mutableWeights = mutablePool
          .map((student) => weightMap[student.name] ?? settings.baseWeight)
          .toList();

      for (int i = 0; i < drawCount && mutablePool.isNotEmpty; i++) {
        final index = _pickWeightedIndex(mutableWeights);
        result.add(mutablePool.removeAt(index));
        mutableWeights.removeAt(index);
      }

      if (result.isNotEmpty) {
        return result;
      }
    } catch (_) {
      // Fallback to random draw below.
    }

    return _drawRandomNoRepeat(candidates, drawCount);
  }

  int _pickWeightedIndex(List<double> weights) {
    final totalWeight = weights.fold<double>(0, (sum, weight) => sum + weight);
    if (totalWeight <= 0) {
      return _random.nextInt(weights.length);
    }

    final randomValue = _random.nextDouble() * totalWeight;
    double cumulativeWeight = 0;

    for (int i = 0; i < weights.length; i++) {
      cumulativeWeight += weights[i];
      if (randomValue <= cumulativeWeight) {
        return i;
      }
    }

    return weights.length - 1;
  }

  List<Student> _drawRandomNoRepeat(List<Student> candidates, int drawCount) {
    final pool = List<Student>.from(candidates)..shuffle(_random);
    return pool.take(drawCount).toList();
  }
}
