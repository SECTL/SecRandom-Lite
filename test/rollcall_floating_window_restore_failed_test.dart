import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secrandom_lite/services/rollcall_quick_entry_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 恢复失败时必须如实回落为关闭，否则设置里会显示“已开启”却没有窗口。
///
/// 与恢复成功同样独占一个测试文件：单例的首次 initialize() 只能走一次。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('secrandom_lite/quick_entry');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final service = RollCallQuickEntryService.instance;
  final windowsSkip = service.supportsFloatingWindow ? false : '悬浮窗仅 Windows 支持';

  test('启动恢复悬浮窗失败时开关回落为关闭', () async {
    SharedPreferences.setMockInitialValues({
      'rollcall_floating_window_enabled': true,
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'showFloatingWindow') {
        throw PlatformException(code: 'window_creation_failed');
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final states = <bool>[];
    final subscription = service.floatingWindowState.listen(states.add);
    addTearDown(subscription.cancel);

    await service.initialize();
    await Future<void>.delayed(Duration.zero);

    expect(await service.loadFloatingWindowEnabled(), isFalse);
    expect(states, contains(false));
  }, skip: windowsSkip);
}
