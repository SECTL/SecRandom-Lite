import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:secrandom_lite/providers/app_provider.dart';
import 'package:secrandom_lite/screens/history/history_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers/isolated_data_dir.dart';

/// 历史页右下角刷新按钮：桌面端替代移动端下拉刷新。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  isolateDataServiceDir();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 平台覆盖必须在测试体内复原：框架在测试体结束时就会校验调试变量。
  Future<void> withPlatform(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  /// 页面初始加载读的是真实文件，FakeAsync 不会推进真实 I/O，
  /// 需要用 runAsync 放行事件循环，否则会一直停在加载态。
  Future<void> settleRealIo(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpHistory(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // 在真实事件循环里先完成 provider 的初始文件加载。直接在 widget 测试的
    // fake-async 环境里创建 AppProvider，配置读取会停在文件 I/O 上并一直占着
    // config.lock，导致 tearDownAll 无法删除临时目录。
    late AppProvider provider;
    await tester.runAsync(() async {
      provider = AppProvider();
      await provider.ready;
      await provider.waitForPendingConfigSave();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => provider,
        child: const MaterialApp(home: HistoryScreen()),
      ),
    );
    await settleRealIo(tester);
  }

  testWidgets('桌面端显示刷新按钮并与查看详情按钮并存', (tester) async {
    await withPlatform(TargetPlatform.windows, () async {
      await pumpHistory(tester);

      expect(find.byTooltip('刷新记录'), findsOneWidget);
      expect(find.byTooltip('查看详细记录'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNWidgets(2));
    });
  });

  testWidgets('移动端不显示刷新按钮，保留下滑刷新', (tester) async {
    await withPlatform(TargetPlatform.android, () async {
      await pumpHistory(tester);

      expect(find.byTooltip('刷新记录'), findsNothing);
      expect(find.byTooltip('查看详细记录'), findsOneWidget);
      expect(find.byType(RefreshIndicator), findsWidgets);
    });
  });

  testWidgets('点击刷新按钮会执行刷新并给出反馈', (tester) async {
    await withPlatform(TargetPlatform.windows, () async {
      await pumpHistory(tester);

      await tester.tap(find.byTooltip('刷新记录'));
      await settleRealIo(tester);

      // 未登录时应回退为刷新本地记录，并给出提示
      expect(find.text('未登录，已刷新本地记录'), findsOneWidget);
      // 刷新结束后恢复空闲状态，按钮可再次点击
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });
  });
}
