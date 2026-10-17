import 'package:flutter_test/flutter_test.dart';
import 'package:secrandom_lite/models/history_record.dart';
import 'package:secrandom_lite/models/student.dart';
import 'package:secrandom_lite/providers/app_provider.dart';
import 'package:secrandom_lite/services/cloud/cloud_sync_service.dart';
import 'package:secrandom_lite/services/data_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers/isolated_data_dir.dart';

/// 可脚本化的云端服务：不触网，按需模拟成功/失败
class _FakeCloudSyncService extends CloudSyncService {
  int pullCalls = 0;
  bool pullSucceeds = true;
  int newRecordsOnSuccess = 0;

  @override
  Future<PullResult?> pullAll({
    required Future<Set<String>> Function(String kind) existingUids,
    required Future<void> Function(String kind, Map<String, dynamic> json)
        onNewRecord,
  }) async {
    pullCalls++;
    if (!pullSucceeds) return null;
    return PullResult(
      newRecords: newRecordsOnSuccess,
      rollcallContributions: const {},
      lotteryContributions: const {},
      students: const [],
    );
  }

  @override
  Future<bool> pushAll({
    required Map<String, int> ownRollcall,
    required Map<String, int> ownLottery,
    List<Student>? students,
  }) async =>
      true;
}

HistoryRecord _record(int id) => HistoryRecord(
      id: id,
      name: '刷新测试$id',
      drawMethod: 1,
      drawTime: '2026-01-01 10:00:00',
      drawPeopleNumbers: 1,
      drawGroup: '1',
      drawGender: '所有性别',
      className: '1',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  isolateDataServiceDir();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('未登录时下拉刷新静默回退本地，不触达云端', () async {
    final service = _FakeCloudSyncService();
    final provider = AppProvider(cloudSyncService: service);
    addTearDown(provider.dispose);
    await provider.reloadData();
    await Future<void>.delayed(const Duration(milliseconds: 100)); // 等构造时的初始加载收尾
    await provider.refreshHistory();

    // 构造 provider 之后才写入磁盘的记录，只有"重载本地"才能看到
    await DataService().addHistoryRecord(_record(999));
    expect(
      provider.history.any((r) => r.id == 999),
      isFalse,
      reason: '写盘前已刷新过一次，内存里不应有该记录',
    );

    final result = await provider.refreshHistory();

    expect(result.fromCloud, isFalse);
    expect(result.errorMessage, isNull, reason: '未登录是正常态，不是失败');
    expect(service.pullCalls, 0, reason: '未登录不应触达云端');
    expect(service.status, SyncStatus.idle);
    expect(
      provider.history.any((r) => r.id == 999),
      isTrue,
      reason: '本地回退必须从磁盘重载记录',
    );
  });

  test('登录且云同步开启时下拉刷新走云端并返回新增条数', () async {
    final service = _FakeCloudSyncService()..newRecordsOnSuccess = 3;
    final provider = AppProvider(cloudSyncService: service);
    addTearDown(provider.dispose);
    await provider.reloadData();

    provider.setAuthState(true);
    await Future<void>.delayed(const Duration(milliseconds: 200)); // 等登录初始同步
    service.pullCalls = 0;

    final result = await provider.refreshHistory();

    expect(result.fromCloud, isTrue);
    expect(result.newRecords, 3);
    expect(result.errorMessage, isNull);
    expect(service.pullCalls, 1);
  });

  test('登录后云端拉取失败时返回失败提示并回退本地', () async {
    final service = _FakeCloudSyncService()..pullSucceeds = false;
    final provider = AppProvider(cloudSyncService: service);
    addTearDown(provider.dispose);
    await provider.reloadData();

    provider.setAuthState(true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    service.pullCalls = 0;

    // 失败回退也必须重载本地：写盘后内存看不到的记录要被带回来
    await DataService().addHistoryRecord(_record(888));

    final result = await provider.refreshHistory();

    expect(result.fromCloud, isFalse);
    expect(result.errorMessage, '云端同步失败，已刷新本地记录');
    expect(service.pullCalls, 1, reason: '已登录应先尝试云端');
    expect(
      provider.history.any((r) => r.id == 888),
      isTrue,
      reason: '失败回退后展示的应是重载后的本地记录',
    );
  });

  test('云同步关闭时下拉刷新静默回退本地，不触达云端', () async {
    final service = _FakeCloudSyncService();
    final provider = AppProvider(cloudSyncService: service);
    addTearDown(provider.dispose);
    await provider.reloadData();

    provider.setAuthState(true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    provider.setCloudSyncEnabled(false);
    service.pullCalls = 0;

    final result = await provider.refreshHistory();

    expect(result.fromCloud, isFalse);
    expect(result.errorMessage, isNull, reason: '用户主动关闭同步，不是失败');
    expect(service.pullCalls, 0);
  });
}
