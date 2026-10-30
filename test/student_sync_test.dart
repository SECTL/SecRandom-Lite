import 'package:flutter_test/flutter_test.dart';
import 'package:secrandom_lite/models/student.dart';
import 'package:secrandom_lite/services/cloud/student_sync.dart';
import 'package:secrandom_lite/services/cloud/sync_state.dart';

Student _student(
  String uid, {
  int id = 1,
  String name = '张三',
  String className = '1',
  int rev = 0,
  String revBy = '',
  String gender = '男',
  String group = '1',
  bool exist = true,
}) => Student(
  id: id,
  uid: uid,
  name: name,
  gender: gender,
  group: group,
  className: className,
  exist: exist,
  rev: rev,
  revBy: revBy,
);

StudentTombstone _tombstone(int rev, String by) =>
    StudentTombstone(rev: rev, by: by, at: DateTime(2026, 10, 30));

void main() {
  test('云端独有学生加入本地', () {
    final result = mergeStudents(
      local: const [],
      localTombstones: const {},
      cloud: [_student('cloud:1', name: '云端学生')],
      cloudTombstones: const {},
      deviceId: 'dev-a',
      studentClock: 0,
    );

    expect(result.students.single.uid, 'cloud:1');
    expect(result.students.single.name, '云端学生');
    expect(result.changed, isTrue);
    expect(result.needsPush, isFalse);
  });

  test('本地独有学生保留并需要推送', () {
    final result = mergeStudents(
      local: [_student('local:1', name: '本地学生')],
      localTombstones: const {},
      cloud: const [],
      cloudTombstones: const {},
      deviceId: 'dev-a',
      studentClock: 0,
    );

    expect(result.students.single.uid, 'local:1');
    expect(result.students.single.rev, 1, reason: '本地独有旧学生要拿新修订号');
    expect(result.changed, isTrue);
    expect(result.needsPush, isTrue);
  });

  test('高 rev 胜；同 rev 比 revBy', () {
    final cloudWins = mergeStudents(
      local: [_student('u:1', name: '本地', rev: 2, revBy: 'dev-a')],
      localTombstones: const {},
      cloud: [_student('u:1', name: '云端', rev: 3, revBy: 'dev-b')],
      cloudTombstones: const {},
      deviceId: 'dev-a',
      studentClock: 0,
    );
    expect(cloudWins.students.single.name, '云端');
    expect(cloudWins.changed, isTrue);
    expect(cloudWins.needsPush, isFalse);

    final localWins = mergeStudents(
      local: [_student('u:1', name: '本地', rev: 3, revBy: 'dev-z')],
      localTombstones: const {},
      cloud: [_student('u:1', name: '云端', rev: 3, revBy: 'dev-a')],
      cloudTombstones: const {},
      deviceId: 'dev-z',
      studentClock: 0,
    );
    expect(localWins.students.single.name, '本地');
    expect(localWins.needsPush, isTrue);
  });

  test('墓碑胜存活；存活胜墓碑', () {
    final deleted = mergeStudents(
      local: [_student('u:1', rev: 2, revBy: 'dev-a')],
      localTombstones: {'u:1': _tombstone(3, 'dev-a')},
      cloud: const [],
      cloudTombstones: const {},
      deviceId: 'dev-a',
      studentClock: 0,
    );
    expect(deleted.students, isEmpty);
    expect(deleted.tombstones['u:1']!.rev, 3);
    expect(deleted.changed, isTrue);
    expect(deleted.needsPush, isTrue);

    final resurrected = mergeStudents(
      local: [_student('u:1', rev: 4, revBy: 'dev-a')],
      localTombstones: const {},
      cloud: const [],
      cloudTombstones: {'u:1': _tombstone(3, 'dev-b')},
      deviceId: 'dev-a',
      studentClock: 0,
    );
    expect(resurrected.students.single.uid, 'u:1');
    expect(resurrected.tombstones, isEmpty);
    expect(resurrected.needsPush, isTrue);
  });

  test('平局时本地内容胜', () {
    final result = mergeStudents(
      local: [_student('u:1', name: '本地', rev: 2, revBy: 'dev-a')],
      localTombstones: const {},
      cloud: [_student('u:1', name: '云端', rev: 2, revBy: 'dev-a')],
      cloudTombstones: const {},
      deviceId: 'dev-a',
      studentClock: 0,
    );

    expect(result.students.single.name, '本地');
    expect(result.needsPush, isTrue);
  });

  test('两端 rev 0 内容不同：本地胜并分配新 rev，第二次合并不再翻转', () {
    final first = mergeStudents(
      local: [_student('u:1', name: '本地')],
      localTombstones: const {},
      cloud: [_student('u:1', name: '云端')],
      cloudTombstones: const {},
      deviceId: 'dev-a',
      studentClock: 5,
    );

    expect(first.students.single.name, '本地');
    expect(first.students.single.rev, 6);
    expect(first.students.single.revBy, 'dev-a');
    expect(first.studentClock, 6);
    expect(first.changed, isTrue);
    expect(first.needsPush, isTrue);

    final second = mergeStudents(
      local: first.students,
      localTombstones: first.tombstones,
      cloud: [_student('u:1', name: '云端')],
      cloudTombstones: const {},
      deviceId: 'dev-a',
      studentClock: first.studentClock,
    );

    expect(second.students.single.name, '本地');
    expect(second.students.single.rev, 6);
    expect(second.studentClock, 6);
    expect(second.changed, isFalse);
    expect(second.needsPush, isTrue);
  });

  test('不同 uid 相同班级和 id：两个都保留，后到者 id 重排', () {
    final result = mergeStudents(
      local: [_student('local:1', id: 1)],
      localTombstones: const {},
      cloud: [_student('cloud:1', id: 1, name: '云端')],
      cloudTombstones: const {},
      deviceId: 'dev-a',
      studentClock: 0,
    );

    expect(result.students, hasLength(2));
    final byUid = {for (final s in result.students) s.uid: s};
    expect(byUid['local:1']!.id, 1);
    expect(byUid['cloud:1']!.id, 2);
  });

  test('班级重命名：uid 不变、本地高 rev 胜出并需要推送', () {
    final result = mergeStudents(
      local: [_student('u:1', className: '2', rev: 3, revBy: 'dev-a')],
      localTombstones: const {},
      cloud: [_student('u:1', className: '1', rev: 2, revBy: 'dev-b')],
      cloudTombstones: const {},
      deviceId: 'dev-a',
      studentClock: 0,
    );

    expect(result.students.single.uid, 'u:1');
    expect(result.students.single.className, '2');
    expect(result.students.single.rev, 3);
    expect(result.needsPush, isTrue);
  });

  test('studentClock 取本地、云端与墓碑的最大 rev', () {
    final result = mergeStudents(
      local: [_student('local:1', rev: 3, revBy: 'dev-a')],
      localTombstones: {'gone:1': _tombstone(5, 'dev-a')},
      cloud: [_student('cloud:1', rev: 7, revBy: 'dev-b')],
      cloudTombstones: const {},
      deviceId: 'dev-a',
      studentClock: 1,
    );

    expect(result.studentClock, 7);
  });

  test('缺少 uid 的旧学生按 legacy 规则派生后再合并', () {
    final result = mergeStudents(
      local: [_student('', name: '旧学生')],
      localTombstones: const {},
      cloud: const [],
      cloudTombstones: const {},
      deviceId: 'dev-a',
      studentClock: 0,
    );

    expect(result.students.single.uid, startsWith('legacy:'));
    expect(result.needsPush, isTrue);
  });
}
