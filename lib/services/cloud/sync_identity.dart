import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../models/history_record.dart';
import '../../models/lottery_record.dart';

/// 新记录 uid：`<deviceId>:<本地单调序号>`
String newRecordUid(String deviceId, int seq) => '$deviceId:$seq';

/// 旧点名记录派生 uid（两设备对同一份旧数据派生结果一致）
String deriveLegacyHistoryUid(HistoryRecord record) {
  final raw = '${record.className}|${record.id}|${record.drawTime}';
  return 'legacy:${sha256.convert(utf8.encode(raw)).toString().substring(0, 32)}';
}

/// 旧抽奖记录派生 uid
String deriveLegacyLotteryUid(LotteryRecord record) {
  final raw = '${record.poolName}|${record.id}';
  return 'legacy:${sha256.convert(utf8.encode(raw)).toString().substring(0, 32)}';
}
