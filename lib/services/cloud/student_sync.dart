import '../../models/student.dart';
import 'sync_identity.dart';
import 'sync_state.dart';

/// 学生名单合并结果。
class StudentMergeResult {
  const StudentMergeResult({
    required this.students,
    required this.tombstones,
    required this.studentClock,
    required this.changed,
    required this.needsPush,
  });

  /// 合并后的本地学生列表（id 已按班级去重，按 uid 排序）
  final List<Student> students;

  /// 合并后的墓碑
  final Map<String, StudentTombstone> tombstones;

  /// 推进后的 Lamport 计数器
  final int studentClock;

  /// 本地是否需要落盘
  final bool changed;

  /// 云端是否需要更新
  final bool needsPush;
}

/// 比较 `(rev, by)`；返回正数表示 a 更新。
int _compareRev(int revA, String byA, int revB, String byB) {
  if (revA != revB) return revA.compareTo(revB);
  return byA.compareTo(byB);
}

bool _sameContent(Student a, Student b) =>
    a.name == b.name &&
    a.gender == b.gender &&
    a.group == b.group &&
    a.className == b.className &&
    a.exist == b.exist;

Student _normalizeUid(Student student) => student.uid.isNotEmpty
    ? student
    : student.copyWith(uid: deriveLegacyStudentUid(student));

Map<String, Student> _byUid(Iterable<Student> students) {
  final result = <String, Student>{};
  for (final student in students) {
    final normalized = _normalizeUid(student);
    if (normalized.uid.isEmpty) continue;
    result[normalized.uid] = normalized;
  }
  return result;
}

bool _studentsEquivalent(
  Iterable<Student> a,
  Iterable<Student> b, {
  bool compareId = false,
}) {
  final left = _byUid(a);
  final right = _byUid(b);
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    final other = right[entry.key];
    if (other == null) return false;
    final x = entry.value;
    if (compareId && x.id != other.id) return false;
    if (x.name != other.name ||
        x.gender != other.gender ||
        x.group != other.group ||
        x.className != other.className ||
        x.exist != other.exist ||
        x.rev != other.rev ||
        x.revBy != other.revBy) {
      return false;
    }
  }
  return true;
}

bool _tombstonesEquivalent(
  Map<String, StudentTombstone> a,
  Map<String, StudentTombstone> b,
) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    if (other == null) return false;
    if (entry.value.rev != other.rev || entry.value.by != other.by) {
      return false;
    }
  }
  return true;
}

/// 合并本地与云端学生名单。
///
/// 规则见 `docs/superpowers/specs/2026-10-30-cloud-sync-v2.1-design.md` 3.3：
/// - uid 为身份，`(rev, revBy)` 大者胜；完全相等时本地内容胜。
/// - 墓碑与存活记录同样按 `(rev, by)` 比较，墓碑胜则删除学生。
/// - `rev == 0` 的旧记录在本地胜出时分配新修订号，避免两端永久互相覆盖。
/// - 合并后按 `(className, id)` 重排冲突的本地 id。
StudentMergeResult mergeStudents({
  required List<Student> local,
  required Map<String, StudentTombstone> localTombstones,
  required List<Student> cloud,
  required Map<String, StudentTombstone> cloudTombstones,
  required String deviceId,
  required int studentClock,
}) {
  final localByUid = _byUid(local);
  final cloudByUid = _byUid(cloud);

  // 1. 墓碑并集：同一 uid 取修订更高的一条。
  final tombstones = <String, StudentTombstone>{...localTombstones};
  for (final entry in cloudTombstones.entries) {
    final current = tombstones[entry.key];
    if (current == null ||
        _compareRev(entry.value.rev, entry.value.by, current.rev, current.by) >
            0) {
      tombstones[entry.key] = entry.value;
    }
  }

  var clock = studentClock;
  final winners = <String, Student>{};
  final removedTombstones = <String>{};

  final uids = <String>{
    ...localByUid.keys,
    ...cloudByUid.keys,
    ...tombstones.keys,
  }.toList()..sort();

  for (final uid in uids) {
    final localStudent = localByUid[uid];
    final cloudStudent = cloudByUid[uid];
    final tombstone = tombstones[uid];

    if (localStudent != null && localStudent.rev > clock) {
      clock = localStudent.rev;
    }
    if (cloudStudent != null && cloudStudent.rev > clock) {
      clock = cloudStudent.rev;
    }
    if (tombstone != null && tombstone.rev > clock) {
      clock = tombstone.rev;
    }

    // 2. 先选出存活记录中修订更高的一方。
    Student? winner;
    var winnerIsLocal = false;
    var bumpLegacyLocal = false;

    if (localStudent != null && cloudStudent != null) {
      if (localStudent.rev == 0 && cloudStudent.rev == 0) {
        if (_sameContent(localStudent, cloudStudent)) {
          winner = localStudent;
          winnerIsLocal = true;
        } else {
          winner = localStudent;
          winnerIsLocal = true;
          bumpLegacyLocal = true;
        }
      } else {
        final cmp = _compareRev(
          localStudent.rev,
          localStudent.revBy,
          cloudStudent.rev,
          cloudStudent.revBy,
        );
        if (cmp >= 0) {
          winner = localStudent;
          winnerIsLocal = true;
        } else {
          winner = cloudStudent;
        }
      }
    } else if (localStudent != null) {
      winner = localStudent;
      winnerIsLocal = true;
      bumpLegacyLocal = localStudent.rev == 0;
    } else if (cloudStudent != null) {
      winner = cloudStudent;
    }

    if (winner == null) {
      // 只剩墓碑：保留删除记录。
      continue;
    }

    // 3. 墓碑与存活记录比较；相等时墓碑胜，避免已删除学生被复活。
    if (tombstone != null) {
      final cmp = _compareRev(
        tombstone.rev,
        tombstone.by,
        winner.rev,
        winner.revBy,
      );
      if (cmp >= 0) {
        continue; // 墓碑胜：不加入学生，保留墓碑
      }
      removedTombstones.add(uid);
    }

    // 4. 本地旧记录胜出时分配新修订号，写回云端后两端才能收敛。
    var resolved = winner;
    if (winnerIsLocal && bumpLegacyLocal) {
      clock += 1;
      resolved = winner.copyWith(rev: clock, revBy: deviceId);
    }

    // 云端胜出但本地也有同一 uid 时，保留本地 id，避免界面编辑/删除串人。
    if (!winnerIsLocal &&
        localStudent != null &&
        resolved.id != localStudent.id) {
      resolved = resolved.copyWith(id: localStudent.id);
    }

    winners[uid] = resolved;
  }

  for (final uid in removedTombstones) {
    tombstones.remove(uid);
  }

  // 5. 按 `(className, id)` 去重：本地 id 优先，云端独有学生冲突时重排。
  final maxIds = <String, int>{};
  for (final student in winners.values) {
    final current = maxIds[student.className] ?? 0;
    if (student.id > current) maxIds[student.className] = student.id;
  }

  final usedIds = <String, Set<int>>{};
  final orderedUids = winners.keys.toList()
    ..sort((a, b) {
      final aLocal = localByUid.containsKey(a);
      final bLocal = localByUid.containsKey(b);
      if (aLocal != bLocal) return aLocal ? -1 : 1;
      return a.compareTo(b);
    });

  final students = <Student>[];
  for (final uid in orderedUids) {
    var student = winners[uid]!;
    final used = usedIds.putIfAbsent(student.className, () => <int>{});
    if (student.id <= 0 || used.contains(student.id)) {
      final next = (maxIds[student.className] ?? 0) + 1;
      maxIds[student.className] = next;
      student = student.copyWith(id: next);
    }
    used.add(student.id);
    students.add(student);
  }

  students.sort((a, b) => a.uid.compareTo(b.uid));

  return StudentMergeResult(
    students: students,
    tombstones: tombstones,
    studentClock: clock,
    changed:
        !_studentsEquivalent(students, local, compareId: true) ||
        !_tombstonesEquivalent(tombstones, localTombstones),
    needsPush:
        !_studentsEquivalent(students, cloud) ||
        !_tombstonesEquivalent(tombstones, cloudTombstones),
  );
}
