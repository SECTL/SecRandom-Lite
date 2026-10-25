import 'package:flutter_test/flutter_test.dart';
import 'package:secrandom_lite/models/history_record.dart';
import 'package:secrandom_lite/models/lottery_record.dart';
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final data = DataService();
    await data.saveSyncState({});
    await data.saveSyncOutbox({});
    await data.clearHistoryRecords();
    await data.clearAllLotteryRecords();
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
    final outbox = await provider.cloudSyncService.loadOutbox();
    expect(
      outbox.rollcall.any((record) => record['name'] == '本地生'),
      isTrue,
      reason: '云端为空时完整本地历史应进入 outbox',
    );
  });

  test('已有本地数据：登录后按 uid 并集合并，本地独有记录保留并补传', () async {
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

    // 本地独有记录：不能被云端快照覆盖掉，且应补传到 outbox。
    await DataService().addHistoryRecord(_record(1, '本地旧'));
    await provider.reloadData();
    expect(provider.history.any((r) => r.name == '本地旧'), isTrue);

    provider.setAuthState(true);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(service.fullSnapshotCalls, 1, reason: '已有基线应拉取完整快照做合并');
    expect(service.pushAllCalls, 1, reason: '本地独有记录应触发补传');
    expect(
      provider.history.any((r) => r.name == '云端甲'),
      isTrue,
      reason: '云端记录应合并到本地',
    );
    expect(
      provider.history.any((r) => r.name == '本地旧'),
      isTrue,
      reason: '本地独有记录必须保留',
    );
    expect(
      provider.allStudents.any((s) => s.name == '云端学生'),
      isTrue,
      reason: '名单仍按云端优先',
    );

    final outbox = await provider.cloudSyncService.loadOutbox();
    expect(
      outbox.rollcall.any((record) => record['name'] == '本地旧'),
      isTrue,
      reason: '本地独有记录应补入 outbox',
    );
    expect(
      outbox.rollcall.any((record) => record['name'] == '云端甲'),
      isFalse,
      reason: '云端已有记录不应重复上传',
    );

    // 统计总视图 = 云端贡献求和（张三2 + 李四3）。
    expect(provider.rollcallStats.countOf('张三'), 2);
    expect(provider.rollcallStats.countOf('李四'), 3);
  });

  test('登录并集合同步抽奖历史', () async {
    final service = _FakeCloudSyncService(
      cloudHasData: true,
      snapshot: const CloudFullSnapshot(
        rollcallRecords: [],
        lotteryRecords: [
          {
            'id': 'cloud-1',
            'uid': 'dev-b:1',
            'poolName': '池',
            'prizeName': '云端奖品',
            'studentName': null,
            'groupName': null,
            'gender': null,
            'drawTime': '2026-02-02T09:00:00.000',
            'drawCount': 1,
            'classFilter': null,
            'groupFilter': null,
            'genderFilter': null,
          },
        ],
        rollcallContributions: {},
        lotteryContributions: {},
        students: [],
      ),
    );
    final provider = AppProvider(cloudSyncService: service);
    addTearDown(provider.dispose);
    await provider.reloadData();

    await DataService().addLotteryRecord(
      LotteryRecord(
        id: 'local-1',
        poolName: '池',
        prizeName: '本地奖品',
        drawTime: DateTime(2026, 1, 1, 8),
      ),
    );
    await provider.reloadData();

    provider.setAuthState(true);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final records = await DataService().loadLotteryRecords();
    expect(records.any((r) => r.prizeName == '云端奖品'), isTrue);
    expect(records.any((r) => r.prizeName == '本地奖品'), isTrue);
    final outbox = await provider.cloudSyncService.loadOutbox();
    expect(
      outbox.lottery.any((record) => record['prizeName'] == '本地奖品'),
      isTrue,
    );
    expect(
      outbox.lottery.any((record) => record['prizeName'] == '云端奖品'),
      isFalse,
    );
  });

  test('首次登录（本地无基线）：云端严格覆盖本地，不上传', () async {
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

    expect(service.fullSnapshotCalls, 1, reason: '无本地基线应拉取云端快照');
    expect(service.pushAllCalls, 0, reason: '基线初始化不应上传本地');
    // 总视图求和
    expect(provider.rollcallStats.countOf('本机人'), 4);
    expect(provider.rollcallStats.countOf('他机人'), 1);

    // own 贡献只含本机部分，ownSeq 推进到本机最大序号 5（后续新记录用 6，避免复用）
    final state = await provider.cloudSyncService.loadState();
    expect(state.ownRollcallStats['本机人'], 4);
    expect(state.ownSeq['rollcall'], 5);
    expect(state.baselineInitialized, isTrue);
  });

  test('导入/恢复后补传本地独有历史', () async {
    final service = _FakeCloudSyncService(
      cloudHasData: true,
      snapshot: const CloudFullSnapshot(
        rollcallRecords: [],
        lotteryRecords: [],
        rollcallContributions: {},
        lotteryContributions: {},
        students: [],
      ),
    );
    final provider = AppProvider(cloudSyncService: service);
    addTearDown(provider.dispose);
    await provider.reloadData();

    await DataService().addHistoryRecord(_record(1, '导入记录'));
    await provider.reloadData();

    // 模拟导入后手动补传：关闭自动同步，避免登录初始同步干扰计数。
    provider.setCloudSyncEnabled(false);
    provider.setAuthState(true);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final ok = await provider.syncLocalHistoryToCloud();
    expect(ok, isTrue);
    expect(service.fullSnapshotCalls, 1);
    expect(service.pushAllCalls, 1);
    final outbox = await provider.cloudSyncService.loadOutbox();
    expect(
      outbox.rollcall.any((record) => record['name'] == '导入记录'),
      isTrue,
    );
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
