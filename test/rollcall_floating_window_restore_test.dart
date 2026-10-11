import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secrandom_lite/services/rollcall_quick_entry_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 悬浮窗开关跨重启恢复。
///
/// 恢复发生在首次 initialize()，而单例只能初始化一次，所以这条路径必须独占
/// 一个测试文件（每个测试文件独立运行，单例在该文件内是全新的）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('secrandom_lite/quick_entry');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final service = RollCallQuickEntryService.instance;
  final windowsSkip = service.supportsFloatingWindow ? false : '悬浮窗仅 Windows 支持';

  test('上次开启过悬浮窗时，启动会重新创建它', () async {
    SharedPreferences.setMockInitialValues({
      'rollcall_floating_window_enabled': true,
    });
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await service.initialize();

    expect(calls, contains('showFloatingWindow'));
    expect(await service.loadFloatingWindowEnabled(), isTrue);
  }, skip: windowsSkip);
}
