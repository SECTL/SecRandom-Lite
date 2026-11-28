import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:secrandom_lite/providers/app_provider.dart';
import 'package:secrandom_lite/screens/settings/general_settings_screen.dart';
import 'package:secrandom_lite/services/rollcall_quick_entry_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers/isolated_data_dir.dart';

/// 悬浮窗外观参数：大小滑块与恢复默认；颜色已统一由应用主题色控制。
///
/// 悬浮窗仅在 Windows 上有实现，其余平台整块不渲染，因此该用例只在
/// Windows 宿主执行。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final supportsFloatingWindow =
      RollCallQuickEntryService.instance.supportsFloatingWindow;

  isolateDataServiceDir();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('secrandom_lite/quick_entry'),
          (_) async => null,
        );
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

  testWidgets('关闭悬浮窗时隐藏外观设置，开启后可调节大小', (tester) async {
    await pump(tester, const GeneralSettingsBody());
    final sizeSlider = find.byKey(const ValueKey('floating_size_slider'));
    expect(sizeSlider, findsNothing);

    final toggle = find.byKey(const ValueKey('floating_window_switch'));
    await tester.ensureVisible(toggle);
    await tester.pump();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(sizeSlider, findsOneWidget);
    expect(find.text('背景颜色'), findsNothing);
    expect(find.text('自定义颜色'), findsNothing);

    await tester.ensureVisible(sizeSlider);
    await tester.pump();
    await tester.tap(sizeSlider);
    await tester.pump();
    expect(find.text('大小：64'), findsNothing);

    final reset = find.text('恢复默认');
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pump();
    expect(find.text('大小：64'), findsOneWidget);

    await tester.ensureVisible(toggle);
    await tester.pump();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(sizeSlider, findsNothing);
  }, skip: !supportsFloatingWindow);
}
