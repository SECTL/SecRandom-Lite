import 'package:SecRandom_lutter/providers/app_provider.dart';
import 'package:SecRandom_lutter/screens/home_screen.dart';
import 'package:SecRandom_lutter/screens/lottery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpWithSize(WidgetTester tester, Size size, Widget child) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => AppProvider(),
      child: MaterialApp(home: child),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 320));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('HomeScreen uses large layout on wide viewport', (tester) async {
    await _pumpWithSize(tester, const Size(1400, 900), const HomeScreen());
    expect(find.byKey(const ValueKey('rollcall_layout_large')), findsOneWidget);
  });

  testWidgets('HomeScreen uses short layout on low-height viewport', (
    tester,
  ) async {
    await _pumpWithSize(tester, const Size(1000, 250), const HomeScreen());
    expect(find.byKey(const ValueKey('rollcall_layout_short')), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets(
    'HomeScreen uses small drawer layout when portrait result is too short',
    (tester) async {
      await _pumpWithSize(tester, const Size(600, 350), const HomeScreen());
      expect(
        find.byKey(const ValueKey('rollcall_layout_small')),
        findsOneWidget,
      );
    },
  );

  testWidgets('LotteryScreen uses large layout on wide viewport', (
    tester,
  ) async {
    await _pumpWithSize(tester, const Size(1400, 900), const LotteryScreen());
    expect(find.byKey(const ValueKey('lottery_layout_large')), findsOneWidget);
  });

  testWidgets('LotteryScreen uses short layout on low-height viewport', (
    tester,
  ) async {
    await _pumpWithSize(tester, const Size(1000, 250), const LotteryScreen());
    expect(find.byKey(const ValueKey('lottery_layout_short')), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets(
    'LotteryScreen uses small drawer layout when portrait result is too short',
    (tester) async {
      await _pumpWithSize(tester, const Size(600, 350), const LotteryScreen());
      expect(
        find.byKey(const ValueKey('lottery_layout_small')),
        findsOneWidget,
      );
    },
  );
}
