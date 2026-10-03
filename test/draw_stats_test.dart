import 'package:flutter_test/flutter_test.dart';
import 'package:secrandom_lite/models/draw_stats.dart';
import 'package:secrandom_lite/models/lottery_record.dart';

void main() {
  group('DrawStats 基本操作', () {
    test('increment 与 countOf', () {
      final stats = DrawStats();
      expect(stats.countOf('张三'), 0);
      stats.increment('张三');
      stats.increment('张三');
      stats.increment('李四', 3);
      expect(stats.countOf('张三'), 2);
      expect(stats.countOf('李四'), 3);
    });

    test('mergeMax 同名取大，只增不减', () {
      final local = DrawStats({'张三': 5, '李四': 1});
      final remote = DrawStats({'张三': 3, '王五': 7});
      local.mergeMax(remote);
      expect(local.countOf('张三'), 5);
      expect(local.countOf('李四'), 1);
      expect(local.countOf('王五'), 7);
    });

    test('fromHistoryNames 解析逗号分隔多人并跳过空名', () {
      final stats = DrawStats.fromHistoryNames([
        '张三,李四',
        '王五，赵六',
        '  ',
      ]);
      expect(stats.countOf('张三'), 1);
      expect(stats.countOf('李四'), 1);
      expect(stats.countOf('王五'), 1);
      expect(stats.countOf('赵六'), 1);
      expect(stats.toMap(), hasLength(4));
    });

    test('toJson/fromJson 往返', () {
      final stats = DrawStats({'张三': 2});
      final restored = DrawStats.fromJson(stats.toJson());
      expect(restored.countOf('张三'), 2);
    });

    test('mergeSum 逐项求和（多设备累加）', () {
      final a = DrawStats({'张三': 3});
      a.mergeSum(DrawStats({'张三': 2, '李四': 1}));
      expect(a.countOf('张三'), 5);
      expect(a.countOf('李四'), 1);
    });
  });

  group('抽奖统计', () {
    LotteryRecord record({
      String? studentName,
      String prizeName = '奖品A',
      int drawCount = 1,
    }) {
      return LotteryRecord(
        id: 'id-$studentName-$prizeName-$drawCount',
        poolName: '池1',
        prizeName: prizeName,
        studentName: studentName,
        drawTime: DateTime(2026, 1, 1),
        drawCount: drawCount,
      );
    }

    test('lotteryStatKey 优先 studentName，回退 prizeName', () {
      expect(
        DrawStats.lotteryStatKey(record(studentName: '张三', prizeName: '奖品A')),
        '张三',
      );
      expect(DrawStats.lotteryStatKey(record(prizeName: '奖品A')), '奖品A');
      expect(
        DrawStats.lotteryStatKey(
          record(studentName: '  ', prizeName: '  '),
        ),
        isNull,
      );
    });

    test('fromLotteryRecords 按 drawCount 累加', () {
      final stats = DrawStats.fromLotteryRecords([
        record(prizeName: '奖品A'),
        record(prizeName: '奖品A', drawCount: 2),
        record(studentName: '张三', prizeName: '奖品A'),
      ]);
      expect(stats.countOf('奖品A'), 3);
      expect(stats.countOf('张三'), 1);
    });

    test('addLotteryRecord 对 drawCount<1 按 1 计数', () {
      final stats = DrawStats();
      stats.addLotteryRecord(record(prizeName: '奖品A', drawCount: 0));
      expect(stats.countOf('奖品A'), 1);
    });
  });
}
