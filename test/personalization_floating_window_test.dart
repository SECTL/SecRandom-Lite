import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:secrandom_lite/providers/app_provider.dart';
import 'package:secrandom_lite/screens/settings/personalization_settings_screen.dart';
import 'package:secrandom_lite/screens/settings/rollcall_settings_screen.dart';
import 'package:secrandom_lite/services/rollcall_quick_entry_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 悬浮窗开关的归属：应在个性化设置，不在点名名单设置。
///
/// 注意 `supportsFloatingWindow` 取自 dart:io 的 `Platform.isWindows`（宿主平台），
/// 不受 `debugDefaultTargetPlatformOverride` 影响，因此非 Windows 分支只能在
/// 非 Windows 宿主（如 CI 的 ubuntu runner）上执行，用镜像式 skip 处理。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final supportsFloatingWindow =
      RollCallQuickEntryService.instance.supportsFloatingWindow;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('secrandom_lite/quick_entry'), (_) async => null);
  });

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

  testWidgets('个性化设置提供点名悬浮窗开关', (tester) async {
    await pump(tester, const PersonalizationSettingsBody());

    expect(find.text('点名悬浮窗'), findsOneWidget);
    expect(find.text('显示悬浮窗'), findsOneWidget);
  }, skip: !supportsFloatingWindow);

  testWidgets('外观调节更新预览，恢复默认重置尺寸', (tester) async {
    await pump(tester, const PersonalizationSettingsBody());
    final slider = find.byKey(const ValueKey('floating_size_slider'));
    await tester.ensureVisible(slider);
    await tester.pump();
    await tester.tap(slider);
    await tester.pump();
    final preview = find.byKey(const ValueKey('floating_window_preview'));
    expect(tester.getSize(preview).width, isNot(80));
    final reset = find.text('恢复默认');
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pump();
    expect(tester.getSize(preview), const Size(80, 80));
    final custom = find.text('自定义颜色');
    await tester.ensureVisible(custom);
    await tester.tap(custom);
    await tester.pump();
    await tester.enterText(find.byType(TextField), '112233');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    final container = tester.widget<Container>(preview);
    expect((container.decoration as BoxDecoration).color, const Color(0xFF112233));
  }, skip: !supportsFloatingWindow);

  testWidgets('点名名单设置不再包含悬浮窗开关', (tester) async {
    await pump(tester, const RollCallSettingsBody());

    expect(find.text('点名悬浮窗'), findsNothing);
    expect(find.text('显示悬浮窗'), findsNothing);
  });
}
