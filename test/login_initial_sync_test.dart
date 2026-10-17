import 'package:flutter_test/flutter_test.dart';
import 'package:secrandom_lite/models/history_record.dart';
import 'package:secrandom_lite/models/student.dart';
import 'package:secrandom_lite/providers/app_provider.dart';
import 'package:secrandom_lite/services/cloud/cloud_sync_service.dart';
import 'package:secrandom_lite/services/data_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers/isolated_data_dir.dart';

/// 可脚本化的云同步服务：控制"云端是否有数据"与返回的完整快照
class _FakeCloudSyncService extends CloudSyncService {
  _FakeCloudSyncService({
    this.cloudHasData = false,
    this.snapshot,
    this.testDeviceId = 'dev-test',
  });

  bool cloudHasData;
  CloudFullSnapshot? snapshot;
  final String testDeviceId;

  int pushAllCalls = 0;
  int fullSnapshotCalls = 0;

  // 测试环境无安全存储，直接注入固定 deviceId，避免触达 TokenManager
  @override
  Future<String> resolveDeviceId() async => testDeviceId;

  @override
  Future<bool> cloudHasAnyData() async => cloudHasData;

  @override
  Future<CloudFullSnapshot?> pullFullSnapshot() async {
    fullSnapshotCalls++;
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

HistoryRecord _record(int id, String name) => HistoryRecord(
      id: id,
      name: name,
      drawMethod: 1,
      drawTime: '2026-01-01 10:00:00',
      drawPeopleNumbers: 1,
      drawGroup: '1',
      drawGender: '所有性别',
      className: '1',
    );

Map<String, dynamic> _cloudRecord(int id, String uid, String name) => {
      'id': id,
      'uid': uid,
      'name': name,
      'draw_method': 1,
      'draw_time': '2026-02-02 09:00:00',
      'draw_people_numbers': 1,
      'draw_group': '所有小组',
      'draw_gender': '所有性别',
      'class_name': '1',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  isolateDataServiceDir();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('云端无数据：登录后上传本地（pushAll），不覆盖', () async {
    final service = _FakeCloudSyncService(cloudHasData: false);
    final provider = AppProvider(cloudSyncService: service);
    addTearDown(provider.dispose);
    await provider.reloadData();

    // 本地已有数据
    await DataService().addHistoryRecord(_record(1, '本地生'));
    await provider.reloadData();

    provider.setAuthState(true);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(service.fullSnapshotCalls, 0, reason: '云端无数据不应拉取快照覆盖');
    expect(service.pushAllCalls, 1, reason: '云端无数据应上传本地');
    expect(
      provider.history.any((r) => r.name == '本地生'),
      isTrue,
      reason: '本地数据应保留',
    );
  });

  test('云端有数据：登录后用云端严格覆盖本地，不上传', () async {
    final service = _FakeCloudSyncService(
      cloudHasData: true,
      snapshot: CloudFullSnapshot(
        rollcallRecords: [_cloudRecord(1, 'dev-b:1', '云端甲')],
        lotteryRecords: const [],
        rollcallContributions: {
          'dev-a': {'张三': 2},
          'dev-b': {'李四': 3},
        },
        lotteryContributions: const {},
        students: [
          Student(
            id: 1,
            name: '云端学生',
            gender: '男',
            group: '1',
            className: '云端班',
            exist: true,
          ),
        ],
      ),
    );
    final provider = AppProvider(cloudSyncService: service);
    addTearDown(provider.dispose);
    await provider.reloadData();

    // 本地先写入会被覆盖掉的数据
    await DataService().addHistoryRecord(_record(1, '本地旧'));
    await provider.reloadData();
    expect(provider.history.any((r) => r.name == '本地旧'), isTrue);

    provider.setAuthState(true);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(service.fullSnapshotCalls, 1, reason: '云端有数据应拉取完整快照');
    expect(service.pushAllCalls, 0, reason: '云端有数据不应上传本地');
    expect(
      provider.history.any((r) => r.name == '云端甲'),
      isTrue,
      reason: '云端记录应覆盖到本地',
    );
    expect(
      provider.history.any((r) => r.name == '本地旧'),
      isFalse,
      reason: '本地旧记录应被云端覆盖移除',
    );
    expect(
      provider.allStudents.any((s) => s.name == '云端学生'),
      isTrue,
      reason: '名单应被云端覆盖',
    );
    // 统计总视图 = 两台设备贡献求和（张三2 + 李四3）
    expect(provider.rollcallStats.countOf('张三'), 2);
    expect(provider.rollcallStats.countOf('李四'), 3);
  });

  test('云端有数据覆盖后：own 统计取本机在云端的贡献，ownSeq 不回退', () async {
    // 本机 deviceId 由假服务注入为 'dev-test'，故本机贡献挂在 dev-test 上
    final service = _FakeCloudSyncService(
      cloudHasData: true,
      testDeviceId: 'dev-test',
      snapshot: CloudFullSnapshot(
        rollcallRecords: [
          _cloudRecord(1, 'dev-test:5', '云端五'),
          _cloudRecord(2, 'dev-b:1', '云端他机'),
        ],
        lotteryRecords: const [],
        rollcallContributions: {
          'dev-test': {'本机人': 4},
          'dev-b': {'他机人': 1},
        },
        lotteryContributions: const {},
        students: const [],
      ),
    );
    final provider = AppProvider(cloudSyncService: service);
    addTearDown(provider.dispose);
    await provider.reloadData();

    provider.setAuthState(true);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // 总视图求和
    expect(provider.rollcallStats.countOf('本机人'), 4);
    expect(provider.rollcallStats.countOf('他机人'), 1);

    // own 贡献只含本机部分，ownSeq 推进到本机最大序号 5（后续新记录用 6，避免复用）
    final state = await provider.cloudSyncService.loadState();
    expect(state.ownRollcallStats['本机人'], 4);
    expect(state.ownSeq['rollcall'], 5);
  });

  test('检查云端失败（网络异常）：登录跳过，不覆盖也不上传', () async {
    final service = _ThrowingCloudSyncService();
    final provider = AppProvider(cloudSyncService: service);
    addTearDown(provider.dispose);
    await provider.reloadData();

    await DataService().addHistoryRecord(_record(1, '保底'));
    await provider.reloadData();

    provider.setAuthState(true);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(service.pushAllCalls, 0);
    expect(service.fullSnapshotCalls, 0);
    expect(provider.history.any((r) => r.name == '保底'), isTrue,
        reason: '判断失败时本地数据应保持不变');
  });
}

/// cloudHasAnyData 抛异常的假服务
class _ThrowingCloudSyncService extends CloudSyncService {
  int pushAllCalls = 0;
  int fullSnapshotCalls = 0;

  @override
  Future<bool> cloudHasAnyData() async => throw Exception('网络异常');

  @override
  Future<CloudFullSnapshot?> pullFullSnapshot() async {
    fullSnapshotCalls++;
    return null;
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
