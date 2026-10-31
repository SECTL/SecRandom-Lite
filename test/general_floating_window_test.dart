import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:secrandom_lite/providers/app_provider.dart';
import 'package:secrandom_lite/screens/settings/general_settings_screen.dart';
import 'package:secrandom_lite/services/rollcall_quick_entry_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers/isolated_data_dir.dart';

/// 悬浮窗外观参数：滑块预览、恢复默认与自定义颜色。
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

  testWidgets('外观调节更新预览，恢复默认重置尺寸', (tester) async {
    await pump(tester, const GeneralSettingsBody());
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
    expect(
      (container.decoration as BoxDecoration).color,
      const Color(0xFF112233),
    );
  }, skip: !supportsFloatingWindow);
}
