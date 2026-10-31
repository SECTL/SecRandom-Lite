import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../models/history_record.dart';
import '../../models/student.dart';

/// 新记录 uid：`<deviceId>:<本地单调序号>`
String newRecordUid(String deviceId, int seq) => '$deviceId:$seq';

String _legacyUid(String raw) =>
    'legacy:${sha256.convert(utf8.encode(raw)).toString().substring(0, 32)}';

/// 旧点名记录派生 uid（两设备对同一份旧数据派生结果一致）
String deriveLegacyHistoryUid(HistoryRecord record) =>
    _legacyUid('${record.className}|${record.id}|${record.drawTime}');

/// 旧学生派生 uid：两端对同一份旧名单派生结果一致。
///
/// 使用班级、本地 id 和姓名；宁可把不同学生当成两个，也不静默合并。
String deriveLegacyStudentUid(Student student) =>
    _legacyUid('${student.className}|${student.id}|${student.name}');

/// 读取历史记录 uid；旧记录没有 uid 时派生稳定 uid 并写回 JSON。
String ensureHistoryUid(Map<String, dynamic> json) {
  final raw = json['uid'];
  final existing = raw is String ? raw.trim() : '';
  if (existing.isNotEmpty) return existing;
  final uid = _legacyUid(
    '${json['class_name'] ?? '1'}|${json['id'] ?? 0}|${json['draw_time'] ?? ''}',
  );
  json['uid'] = uid;
  return uid;
}
