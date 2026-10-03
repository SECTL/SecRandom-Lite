import 'package:flutter_test/flutter_test.dart';
import 'package:secrandom_lite/models/history_record.dart';
import 'package:secrandom_lite/models/lottery_record.dart';
import 'package:secrandom_lite/services/cloud/sync_identity.dart';

HistoryRecord rollcall({int id = 1, String className = '1', String time = '2026-01-01 08:00:00'}) =>
    HistoryRecord(
      id: id,
      name: '张三',
      drawMethod: 1,
      drawTime: time,
      drawPeopleNumbers: 1,
      drawGroup: '所有小组',
      drawGender: '所有性别',
      className: className,
    );

void main() {
  test('新 uid 由设备与序号拼接', () {
    expect(newRecordUid('dev-1', 7), 'dev-1:7');
  });

  test('旧点名记录派生 uid 稳定且与班级/id/时间绑定', () {
    final a = deriveLegacyHistoryUid(rollcall());
    final b = deriveLegacyHistoryUid(rollcall());
    final c = deriveLegacyHistoryUid(rollcall(id: 2));
    expect(a, b);
    expect(a, isNot(c));
    expect(a.startsWith('legacy:'), isTrue);
  });

  test('旧抽奖记录派生 uid 稳定且与奖池/id 绑定', () {
    LotteryRecord rec(String id) => LotteryRecord(
          id: id,
          poolName: '开学奖品',
          prizeName: '笔记本',
          drawTime: DateTime(2026, 1, 1, 8),
        );
    expect(deriveLegacyLotteryUid(rec('a')), deriveLegacyLotteryUid(rec('a')));
    expect(deriveLegacyLotteryUid(rec('a')), isNot(deriveLegacyLotteryUid(rec('b'))));
  });

  test('记录带 uid 时 toJson 往返保留，缺失时 fromJson 容忍', () {
    final withUid = rollcall().copyWithUid('dev-1:1');
    expect(HistoryRecord.fromJson(withUid.toJson()).uid, 'dev-1:1');
    final plain = rollcall().toJson()..remove('uid');
    expect(HistoryRecord.fromJson(plain).uid, isNull);
  });
}
