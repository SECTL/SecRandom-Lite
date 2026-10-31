import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:secrandom_lite/providers/app_provider.dart';
import 'package:secrandom_lite/screens/settings/general_settings_screen.dart';
import 'package:secrandom_lite/screens/settings/personalization_settings_screen.dart';
import 'package:secrandom_lite/screens/settings/rollcall_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers/isolated_data_dir.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  isolateDataServiceDir();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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

  testWidgets('通用设置提供不重复抽取开关并可切换', (tester) async {
    await pump(tester, const GeneralSettingsBody());

    final provider = Provider.of<AppProvider>(
      tester.element(find.byType(GeneralSettingsBody)),
      listen: false,
    );

    final finder = find.byKey(const ValueKey('non_repeat_switch'));
    expect(find.text('启用不重复抽取'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(finder).value, isTrue);

    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pump();

    expect(provider.nonRepeatEnabled, isFalse);
    expect(tester.widget<SwitchListTile>(finder).value, isFalse);
  });

  testWidgets('通用设置项只出现在通用设置中', (tester) async {
    void expectNoGeneralItems(String screen) {
      expect(find.text('启用不重复抽取'), findsNothing, reason: screen);
      expect(find.text('点名悬浮窗'), findsNothing, reason: screen);
      expect(find.text('显示悬浮窗'), findsNothing, reason: screen);
      expect(find.text('登录时启动'), findsNothing, reason: screen);
      expect(
        find.byKey(const ValueKey('non_repeat_switch')),
        findsNothing,
        reason: screen,
      );
      expect(
        find.byKey(const ValueKey('auto_start_switch')),
        findsNothing,
        reason: screen,
      );
      expect(
        find.byKey(const ValueKey('floating_size_slider')),
        findsNothing,
        reason: screen,
      );
    }

    await pump(tester, const PersonalizationSettingsBody());
    expectNoGeneralItems('个性化设置');

    await pump(tester, const RollCallSettingsBody());
    expectNoGeneralItems('点名名单设置');
  });
}
