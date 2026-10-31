import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:secrandom_lite/models/history_record.dart';
import 'package:secrandom_lite/models/student.dart';
import 'package:secrandom_lite/providers/app_provider.dart';
import 'package:secrandom_lite/services/cloud/cloud_sync_service.dart';
import 'package:secrandom_lite/services/data_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/isolated_data_dir.dart';

class _FakeCloudSyncService extends CloudSyncService {
  _FakeCloudSyncService({
    this.hasData = false,
    this.snapshot,
    this.offline = false,
  });

  bool hasData;
  CloudFullSnapshot? snapshot;
  bool offline;
  int pushAllCalls = 0;
  int fullSnapshotCalls = 0;

  @override
  Future<String> resolveDeviceId() async => 'dev-test';

  @override
  Future<bool> cloudHasAnyData() async {
    if (offline) throw StateError('offline');
    return hasData;
  }

  @override
  Future<CloudFullSnapshot?> pullFullSnapshot() async {
    fullSnapshotCalls++;
    if (offline) throw StateError('offline');
    return snapshot;
  }

  @override
  Future<bool> pushAll({
    required Map<String, int> ownRollcall,
    required Map<String, int> ownLottery,
    List<Student>? students,
  }) async {
    pushAllCalls++;
    return true;
  }
}

HistoryRecord _record(String uid, String name) => HistoryRecord(
  id: uid.hashCode,
  uid: uid,
  name: name,
  drawMethod: 1,
  drawTime: '2026-01-01 10:00:00',
  drawPeopleNumbers: 1,
  drawGroup: '1',
  drawGender: '所有性别',
  className: '1',
);

Map<String, dynamic> _cloudRecord(String uid, String name) => {
  'id': uid.hashCode,
  'uid': uid,
  'name': name,
  'draw_method': 1,
  'draw_time': '2026-02-02 09:00:00',
  'draw_people_numbers': 1,
  'draw_group': '所有小组',
  'draw_gender': '所有性别',
  'class_name': '1',
};

Student _student(String name, {String uid = ''}) => Student(
  id: 1,
  uid: uid,
  name: name,
  gender: '男',
  group: '1',
  className: '1',
  exist: true,
);

String _dataDir() => DataService.debugDataDirOverride!;

void _clearDataDir() {
  final root = Directory(_dataDir());
  if (root.existsSync()) {
    for (final entity in root.listSync()) {
      entity.deleteSync(recursive: true);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  isolateDataServiceDir();

  setUp(() async {
    _clearDataDir();
    DataService.resetWorkspaceToGuest();
    SharedPreferences.setMockInitialValues({});
  });

  test('guest 数据不被带进新账号；新账号从云端克隆', () async {
    final guestStudentFile = File(path.join(_dataDir(), 'students.json'));
    await DataService().saveStudents([
      _student('guest 学生', uid: 'legacy:guest-seed'),
    ]);
    await DataService().addHistoryRecord(_record('guest:1', 'guest 记录'));
    final guestBytes = await guestStudentFile.readAsString();

    final service = _FakeCloudSyncService(
      hasData: true,
      snapshot: CloudFullSnapshot(
        rollcallRecords: [_cloudRecord('cloud:1', '云端甲')],
        lotteryRecords: const [],
        rollcallContributions: const {},
        lotteryContributions: const {},
        students: [_student('云端学生')],
      ),
    );
    final provider = AppProvider(cloudSyncService: service);
    addTearDown(provider.dispose);
    await provider.ready;

    await provider.setAuthState(true, userId: 'user-a');

    expect(provider.allStudents.single.name, '云端学生');
    expect(provider.history.any((r) => r.name == '云端甲'), isTrue);
    expect(provider.history.any((r) => r.name == 'guest 记录'), isFalse);
    expect(await guestStudentFile.readAsString(), guestBytes);
    expect(DataService.currentWorkspace, isNot(DataService.guestWorkspace));
  });

  test('新账号云端为空：本地为空，guest 数据不被上传', () async {
    await DataService().saveStudents([_student('guest 学生')]);
    await DataService().addHistoryRecord(_record('guest:1', 'guest 记录'));

    final service = _FakeCloudSyncService(hasData: false);
    final provider = AppProvider(cloudSyncService: service);
    addTearDown(provider.dispose);
    await provider.ready;

    await provider.setAuthState(true, userId: 'user-empty');

    expect(provider.allStudents, isEmpty);
    expect(provider.history, isEmpty);
    expect(service.pushAllCalls, 0);
    expect(service.fullSnapshotCalls, 0);

    final key = DataService.workspaceKeyForUser('user-empty');
    expect(
      Directory(path.join(_dataDir(), 'accounts', key)).existsSync(),
      isTrue,
    );
    expect(
      File(path.join(_dataDir(), 'students.json')).existsSync(),
      isTrue,
      reason: 'guest 学生文件应保持原样',
    );
  });

  test('已有账号工作区再次登录：保留本地新增，不重复克隆', () async {
    final service = _FakeCloudSyncService(
      hasData: true,
      snapshot: CloudFullSnapshot(
        rollcallRecords: [_cloudRecord('cloud:1', '云端甲')],
        lotteryRecords: const [],
        rollcallContributions: const {},
        lotteryContributions: const {},
        students: [_student('云端学生')],
      ),
    );
    final provider = AppProvider(cloudSyncService: service);
    addTearDown(provider.dispose);
    await provider.ready;

    await provider.setAuthState(true, userId: 'user-existing');
    await DataService().addHistoryRecord(_record('local:1', '本地新增'));
    await provider.reloadData();
    expect(provider.history.any((r) => r.name == '本地新增'), isTrue);

    await provider.setAuthState(false);
    await provider.setAuthState(true, userId: 'user-existing');

    expect(provider.history.any((r) => r.name == '本地新增'), isTrue);
    expect(provider.history.any((r) => r.name == '云端甲'), isTrue);
  });

  test('A→B→A：两个账号的数据与主题配置互不影响', () async {
    final service = _FakeCloudSyncService(hasData: false);
    final provider = AppProvider(cloudSyncService: service);
    addTearDown(provider.dispose);
    await provider.ready;

    await provider.setAuthState(true, userId: 'user-a');
    provider.setThemeMode(ThemeMode.dark);
    await provider.waitForPendingConfigSave();
    await provider.setAuthState(false);

    await provider.setAuthState(true, userId: 'user-b');
    provider.setThemeMode(ThemeMode.light);
    await provider.waitForPendingConfigSave();
    await provider.setAuthState(false);

    await provider.setAuthState(true, userId: 'user-a');
    expect(provider.themeMode, ThemeMode.dark);

    await provider.setAuthState(false);
    await provider.setAuthState(true, userId: 'user-b');
    expect(provider.themeMode, ThemeMode.light);
  });

  test('退出登录回到 guest，账号目录保留', () async {
    await DataService().saveStudents([_student('guest 学生')]);

    final service = _FakeCloudSyncService(hasData: false);
    final provider = AppProvider(cloudSyncService: service);
    addTearDown(provider.dispose);
    await provider.ready;

    await provider.setAuthState(true, userId: 'user-logout');
    expect(provider.allStudents, isEmpty);

    final key = DataService.workspaceKeyForUser('user-logout');
    final accountDir = Directory(path.join(_dataDir(), 'accounts', key));
    expect(accountDir.existsSync(), isTrue);

    await provider.setAuthState(false);
    expect(DataService.currentWorkspace, DataService.guestWorkspace);
    expect(provider.allStudents.single.name, 'guest 学生');
    expect(accountDir.existsSync(), isTrue);
  });

  test('首次登录离线：不把空工作区推上云，保留未初始化状态', () async {
    await DataService().saveStudents([_student('guest 学生')]);

    final service = _FakeCloudSyncService(offline: true);
    final provider = AppProvider(cloudSyncService: service);
    addTearDown(provider.dispose);
    await provider.ready;

    await provider.setAuthState(true, userId: 'user-offline');

    expect(provider.cloudLoggedIn, isTrue);
    expect(provider.allStudents, isEmpty);
    expect(await provider.pushToCloud(), isFalse);
    expect(service.pushAllCalls, 0);

    final state = await provider.cloudSyncService.loadState();
    expect(state.baselineInitialized, isFalse);
  });
}
