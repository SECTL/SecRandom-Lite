import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:secrandom_lite/providers/app_provider.dart';
import 'package:secrandom_lite/screens/home_screen.dart';
import 'package:secrandom_lite/services/rollcall_quick_entry_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers/isolated_data_dir.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('secrandom_lite/quick_entry');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final service = RollCallQuickEntryService.instance;
  final calls = <String>[];

  // 悬浮窗只有 Windows 实现，其余平台应完全不触碰原生通道。
  final unsupportedSkip = service.supportsFloatingWindow
      ? '悬浮窗仅 Windows 支持，当前平台走另一分支'
      : false;
  final windowsSkip = service.supportsFloatingWindow
      ? false
      : '悬浮窗仅 Windows 支持';

  Future<void> receiveFromPlatform(String method) {
    return messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
      (_) {},
    );
  }

  isolateDataServiceDir();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    await service.initialize();
    calls.clear();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    calls.clear();
  });

  test(
    'Windows 开关重复打开/关闭时各只发一次原生调用',
    () async {
      await service.setFloatingWindowEnabled(true);
      await service.setFloatingWindowEnabled(true);
      expect(await service.loadFloatingWindowEnabled(), isTrue);
      expect(calls, ['showFloatingWindow', 'showFloatingWindow']);

      await service.setFloatingWindowEnabled(false);
      await service.setFloatingWindowEnabled(false);
      expect(await service.loadFloatingWindowEnabled(), isFalse);
      expect(calls.sublist(2), ['hideFloatingWindow', 'hideFloatingWindow']);
    },
    skip: windowsSkip,
  );

  test(
    '悬浮窗被点击时请求点名，开关保持开启以便继续使用',
    () async {
      await service.setFloatingWindowEnabled(true);
      final request = service.openRollCallRequests.first;
      await receiveFromPlatform('openRollCall');
      await request;
      expect(
        await service.loadFloatingWindowEnabled(),
        isTrue,
        reason: '点击只是打开点名页，不应把悬浮窗功能关掉',
      );
    },
    skip: windowsSkip,
  );

  test(
    '不支持悬浮窗的平台不发送任何原生调用',
    () async {
      await service.setFloatingWindowEnabled(true);
      await service.setFloatingWindowEnabled(false);
      expect(calls, isEmpty);
      expect(await service.loadFloatingWindowEnabled(), isFalse);
    },
    skip: unsupportedSkip,
  );

  test(
    '监听者挂载前到达的点名请求会被补投且只投一次',
    () async {
      // 模拟冷启动：事件先到，页面随后才挂监听。
      await receiveFromPlatform('openRollCall');
      await Future<void>.delayed(Duration.zero);

      var opened = 0;
      final subscription = service.openRollCallRequests.listen((_) {
        opened++;
      });
      addTearDown(subscription.cancel);
      await Future<void>.delayed(Duration.zero);

      expect(opened, 1);
    },
    skip: windowsSkip,
  );

  test('外观参数发送到原生窗口并持久化', () async {
    final appearance = {'size': 100, 'color': 0xFF30343B};
    await service.saveAppearance(appearance);
    expect(calls, contains('setFloatingAppearance'));
    expect(await service.loadAppearance(), appearance);
  }, skip: windowsSkip);

  testWidgets('收到点名请求后主页切回点名页', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppProvider(),
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.byKey(const ValueKey('rollcall_layout_large')), findsOneWidget);

    await tester.tap(find.text('历史记录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.byKey(const ValueKey('rollcall_layout_large')), findsNothing);

    await receiveFromPlatform('openRollCall');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.byKey(const ValueKey('rollcall_layout_large')), findsOneWidget);
  });
}
