import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:secrandom_lite/providers/app_provider.dart';
import 'package:secrandom_lite/screens/settings/personalization_settings_screen.dart';
import 'package:secrandom_lite/services/auto_start_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers/isolated_data_dir.dart';

/// 开机自启开关的归属：应在个性化设置，且只在 Windows 上渲染。
///
/// `supportsAutoStart` 取自 dart:io 的 `Platform.isWindows`（宿主平台），
/// 不受 `debugDefaultTargetPlatformOverride` 影响，因此两个方向都用镜像式
/// skip：Windows 宿主跑写入与回落三条，CI 的 ubuntu runner 跑「不渲染」那条，
/// 两侧分支在各自的宿主上都真实执行，不会出现空跑通过。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final supportsAutoStart = AutoStartService.instance.supportsAutoStart;
  const channel = MethodChannel('secrandom_lite/auto_start');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final calls = <MethodCall>[];

  /// 默认把注册表读作关闭，写入成功；单条用例可自行覆盖。
  void mockRegistry({bool enabled = false, bool failWrites = false}) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'isEnabled':
          return enabled;
        case 'setEnabled':
          if (failWrites) {
            throw PlatformException(code: 'registry_write_failed');
          }
          return call.arguments;
      }
      return null;
    });
  }

  isolateDataServiceDir();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    mockRegistry();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  Finder switchTile() => find.byKey(const ValueKey('auto_start_switch'));
  Finder switchControl() => find.descendant(
        of: switchTile(),
        matching: find.byType(Switch),
      );

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppProvider(),
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
  }

  testWidgets('个性化设置提供开机自启开关', (tester) async {
    await pump(tester, const PersonalizationSettingsBody());

    expect(find.text('开机自启'), findsOneWidget);
    expect(find.text('登录时启动'), findsOneWidget);
    expect(switchTile(), findsOneWidget);
  }, skip: !supportsAutoStart);

  testWidgets('开关按注册表的真实状态显示', (tester) async {
    mockRegistry(enabled: true);
    await pump(tester, const PersonalizationSettingsBody());
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(switchTile()).value, isTrue);
    // 读取状态只查注册表，不写入。
    expect(calls.map((call) => call.method), ['isEnabled']);
  }, skip: !supportsAutoStart);

  testWidgets('开启开机自启把状态写进注册表', (tester) async {
    await pump(tester, const PersonalizationSettingsBody());
    await tester.pumpAndSettle();
    calls.clear();

    await tester.ensureVisible(switchTile());
    await tester.pump();
    await tester.tap(switchControl());
    await tester.pumpAndSettle();

    final write = calls.singleWhere((call) => call.method == 'setEnabled');
    expect(write.arguments, isTrue);
    expect(tester.widget<SwitchListTile>(switchTile()).value, isTrue);
  }, skip: !supportsAutoStart);

  testWidgets('写入失败时开关回落并给出提示', (tester) async {
    mockRegistry(failWrites: true);
    await pump(tester, const PersonalizationSettingsBody());
    await tester.pumpAndSettle();

    await tester.ensureVisible(switchTile());
    await tester.pump();
    await tester.tap(switchControl());
    await tester.pumpAndSettle();

    // 回落后开关必须可再次操作，不能卡在禁用态。
    expect(tester.widget<SwitchListTile>(switchTile()).value, isFalse);
    expect(find.text('无法修改开机自启设置'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(switchTile()).onChanged,
      isNotNull,
    );
  }, skip: !supportsAutoStart);

  testWidgets('非 Windows 不渲染开机自启开关', (tester) async {
    await pump(tester, const PersonalizationSettingsBody());

    expect(find.text('开机自启'), findsNothing);
    expect(find.text('登录时启动'), findsNothing);
    expect(switchTile(), findsNothing);
    expect(calls, isEmpty);
  }, skip: supportsAutoStart);
}
