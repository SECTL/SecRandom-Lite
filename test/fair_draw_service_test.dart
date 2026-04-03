import 'dart:math';

import 'package:secrandom_lite/models/history_record.dart';
import 'package:secrandom_lite/models/student.dart';
import 'package:secrandom_lite/services/fair_draw_service.dart';
import 'package:secrandom_lite/services/fair_weight_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FairWeightService', () {
    final service = FairWeightService();

    final students = <Student>[
      Student(
        id: 1,
        name: 'A',
        gender: 'M',
        group: '1',
        className: '1',
        exist: true,
      ),
      Student(
        id: 2,
        name: 'B',
        gender: 'M',
        group: '1',
        className: '1',
        exist: true,
      ),
      Student(
        id: 3,
        name: 'C',
        gender: 'F',
        group: '2',
        className: '1',
        exist: true,
      ),
    ];

    test('computeCurrentWeights should prefer less-drawn students', () {
      final history = <HistoryRecord>[
        for (int i = 0; i < 5; i++)
          HistoryRecord(
            id: i + 1,
            name: 'A',
            drawMethod: 2,
            drawTime: '2026-01-01 00:00:0$i',
            drawPeopleNumbers: 1,
            drawGroup: 'All',
            drawGender: 'All',
            className: '1',
          ),
        HistoryRecord(
          id: 6,
          name: 'B',
          drawMethod: 2,
          drawTime: '2026-01-01 00:00:06',
          drawPeopleNumbers: 1,
          drawGroup: 'All',
          drawGender: 'All',
          className: '1',
        ),
      ];

      final weights = service.computeCurrentWeights(
        students: students,
        history: history,
      );

      expect(weights['C']!, greaterThan(weights['B']!));
      expect(weights['B']!, greaterThan(weights['A']!));
    });

    test('applyAvgGapProtection should filter top outlier when enabled', () {
      final counts = {'A': 10, 'B': 1, 'C': 1};
      final protected = service.applyAvgGapProtection(
        candidates: students,
        studentCounts: counts,
        drawCount: 1,
        settings: const FairDrawSettings(
          baseWeight: 1.0,
          minWeight: 0.5,
          maxWeight: 5.0,
          frequencyFunction: 1,
          frequencyWeight: 1.0,
          groupWeight: 0.8,
          genderWeight: 0.8,
          timeWeight: 0.5,
          enableAvgGapProtection: true,
          gapThreshold: 1,
          minPoolSize: 1,
        ),
      );

      expect(protected.any((s) => s.name == 'A'), isFalse);
    });
  });

  group('FairDrawService', () {
    final candidates = <Student>[
      for (int i = 0; i < 10; i++)
        Student(
          id: i + 1,
          name: 'S$i',
          gender: i.isEven ? 'M' : 'F',
          group: '1',
          className: '1',
          exist: true,
        ),
    ];

    test('draw should return unique candidates and respect count', () {
      final service = FairDrawService(random: Random(1));
      final picked = service.draw(
        candidates: candidates,
        classHistory: const [],
        count: 5,
      );

      expect(picked.length, 5);
      expect(picked.map((e) => e.id).toSet().length, 5);
    });

    test('draw should return empty when count <= 0', () {
      final service = FairDrawService(random: Random(1));
      final picked = service.draw(
        candidates: candidates,
        classHistory: const [],
        count: 0,
      );

      expect(picked, isEmpty);
    });
  });
}
