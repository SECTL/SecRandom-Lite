import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:secrandom_lite/models/student.dart';
import 'package:secrandom_lite/services/data_service.dart';

import 'helpers/isolated_data_dir.dart';

Student _student(int id, String name, {String className = '1'}) => Student(
      id: id,
      name: name,
      gender: '男',
      group: '1',
      className: className,
      exist: true,
    );

String _dataDir() => DataService.debugDataDirOverride!;

File _file(String relative) => File(path.join(_dataDir(), relative));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  isolateDataServiceDir();

  setUp(() {
    DataService.resetWorkspaceToGuest();
    final root = Directory(_dataDir());
    if (root.existsSync()) {
      for (final entity in root.listSync()) {
        entity.deleteSync(recursive: true);
      }
    }
  });

  test('账号 key 稳定、只含哈希前缀，不同账号不同', () {
    final a1 = DataService.workspaceKeyForUser('user-a');
    final a2 = DataService.workspaceKeyForUser('user-a');
    final b = DataService.workspaceKeyForUser('user-b');

    expect(a1, a2);
    expect(a1, isNot(b));
    expect(a1, matches(RegExp(r'^acct_[0-9a-f]{24}$')));
    expect(DataService.workspaceKeyForUser(''), DataService.guestWorkspace);
  });

  test('guest 与账号、账号与账号之间的学生数据互相隔离', () async {
    final data = DataService();
    await data.saveStudents([_student(1, 'guest 学生')]);

    final accountA = DataService.workspaceKeyForUser('user-a');
    DataService.setWorkspace(accountA);
    await DataService.ensureWorkspace(accountA);
    expect(await data.loadStudents(), isEmpty, reason: '新账号不应读到 guest 名单');

    await data.saveStudents([_student(1, '账号 A 学生')]);

    final accountB = DataService.workspaceKeyForUser('user-b');
    DataService.setWorkspace(accountB);
    await DataService.ensureWorkspace(accountB);
    expect(await data.loadStudents(), isEmpty, reason: '账号 B 不应读到账号 A 名单');

    DataService.setWorkspace(DataService.guestWorkspace);
    final guestStudents = await data.loadStudents();
    expect(guestStudents.single.name, 'guest 学生');
    expect(_file('students.json').existsSync(), isTrue);

    DataService.setWorkspace(accountA);
    final aStudents = await data.loadStudents();
    expect(aStudents.single.name, '账号 A 学生');
    expect(
      _file(path.join('accounts', accountA, 'students.json')).existsSync(),
      isTrue,
    );
  });

  test('workspaceExists 以 marker 为准，并兼容没有 marker 的旧目录', () async {
    final key = DataService.workspaceKeyForUser('user-marker');
    expect(await DataService.workspaceExists(key), isFalse);

    await DataService.ensureWorkspace(key);
    expect(await DataService.workspaceExists(key), isTrue);
    expect(
      _file(path.join('accounts', key, 'workspace.json')).existsSync(),
      isTrue,
    );
    expect(await DataService.workspaceExists(DataService.guestWorkspace), isTrue);

    final legacyKey = DataService.workspaceKeyForUser('user-legacy-dir');
    final legacyDir = Directory(path.join(_dataDir(), 'accounts', legacyKey));
    await legacyDir.create(recursive: true);
    await File(path.join(legacyDir.path, 'students.json')).writeAsString('{}');
    expect(await DataService.workspaceExists(legacyKey), isTrue);
  });

  test('新装学生名单为空，不再生成默认 40 人', () async {
    final students = await DataService().loadStudents();
    expect(students, isEmpty);
  });

  test('旧版默认 40 人文件仍能原样读出', () async {
    final data = <String, dynamic>{
      '1': List.generate(
        40,
        (index) => {
          'id': index + 1,
          'name': '学生 ${index + 1}',
          'gender': index % 2 == 0 ? '男' : '女',
          'group': '1',
          'exist': true,
        },
      ),
    };
    await _file('students.json').writeAsString(jsonEncode(data));

    final students = await DataService().loadStudents();
    expect(students, hasLength(40));
    expect(students.first.name, '学生 1');
  });

  test('旧学生没有 uid 时派生 legacy uid 并写回文件', () async {
    final data = <String, dynamic>{
      '1': [
        {
          'id': 7,
          'name': '旧学生',
          'gender': '女',
          'group': '2',
          'exist': true,
        },
      ],
    };
    await _file('students.json').writeAsString(jsonEncode(data));

    final students = await DataService().loadStudents();
    expect(students.single.uid, startsWith('legacy:'));
    expect(students.single.uid.length, 'legacy:'.length + 32);

    final raw = await _file('students.json').readAsString();
    expect(raw, contains('"uid"'));
    expect(raw, contains(students.single.uid));
  });

  test('Web 存储 key：guest 无前缀，账号带 key 前缀', () {
    final key = DataService.workspaceKeyForUser('user-web');
    expect(
      DataService.webStorageKeyFor('students.json', DataService.guestWorkspace),
      'students.json',
    );
    expect(
      DataService.webStorageKeyFor('students.json', key),
      '$key:students.json',
    );
  });
}
