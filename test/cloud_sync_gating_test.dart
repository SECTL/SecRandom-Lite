import 'package:flutter_test/flutter_test.dart';
import 'package:secrandom_lite/providers/app_provider.dart';
import 'package:secrandom_lite/services/cloud/cloud_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('未登录时推/拉/历史加载静默跳过，不写 lastError、不进重试', () async {
    final provider = AppProvider();
    addTearDown(provider.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(provider.cloudLoggedIn, isFalse);
    expect(await provider.pushToCloud(), isFalse);
    expect(await provider.pullFromCloud(), isFalse);
    expect(await provider.loadHistoryFromCloud(), 0);

    final service = provider.cloudSyncService;
    expect(service.status, SyncStatus.idle,
        reason: '未登录不应触达 pushCore/pullCore');
    expect(service.lastError, isNull);
    expect(service.hasPendingRetry, isFalse);
  });

  test('未登录时 syncNow 静默跳过', () async {
    final provider = AppProvider();
    addTearDown(provider.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(await provider.syncNow(), isFalse);
    expect(provider.cloudSyncService.lastError, isNull);
  });

  test('未登录时重复 setAuthState(false) 是无副作用 no-op', () async {
    final provider = AppProvider();
    addTearDown(provider.dispose);
    // 等待 _loadData 完成，避免 dispose 后 notifyListeners
    await Future<void>.delayed(const Duration(milliseconds: 100));
    provider.setAuthState(false);
    provider.setAuthState(false);
    expect(provider.cloudLoggedIn, isFalse);
    expect(provider.cloudSyncService.hasPendingRetry, isFalse);
    expect(provider.cloudSyncService.status, SyncStatus.idle);
  });

  test('自动同步开关状态持久化到 SharedPreferences', () async {
    final provider = AppProvider();
    addTearDown(provider.dispose);
    // 等待 _loadData 完成默认值读取，避免覆盖测试写入
    await Future<void>.delayed(const Duration(milliseconds: 100));

    provider.setCloudSyncEnabled(false);
    expect(provider.cloudSyncEnabled, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('cloud_auto_sync_enabled'), isFalse);

    provider.setCloudSyncEnabled(true);
    expect(provider.cloudSyncEnabled, isTrue);
    expect(
      (await SharedPreferences.getInstance()).getBool('cloud_auto_sync_enabled'),
      isTrue,
    );
  });
}
