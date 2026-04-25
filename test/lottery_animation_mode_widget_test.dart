import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:secrandom_lite/models/app_config.dart';
import 'package:secrandom_lite/models/history_record.dart';
import 'package:secrandom_lite/models/prize.dart';
import 'package:secrandom_lite/models/prize_pool.dart';
import 'package:secrandom_lite/models/student.dart';
import 'package:secrandom_lite/providers/app_provider.dart';
import 'package:secrandom_lite/screens/lottery_screen.dart';
import 'package:secrandom_lite/services/lottery_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _cleanupDataDirs() async {
  try {
    final rootPath = path.dirname(Platform.resolvedExecutable);
    final dataDir = Directory(path.join(rootPath, 'data'));
    if (await dataDir.exists()) {
      await dataDir.delete(recursive: true);
    }
  } catch (_) {}

  try {
    final currentDir = Directory.current;
    final dataDir = Directory(path.join(currentDir.path, 'data'));
    if (await dataDir.exists()) {
      await dataDir.delete(recursive: true);
    }
  } catch (_) {}
}

class _FakeLotteryScreenProvider extends ChangeNotifier implements AppProvider {
  _FakeLotteryScreenProvider(this._mode);

  final AnimationMode _mode;

  @override
  AnimationMode get lotteryAnimationMode => _mode;

  @override
  double get lotteryResultFontSize => 48;

  // Stub implementations for AppProvider interface
  @override
  List<Student> get allStudents => [];
  @override
  List<Student> get currentSelection => [];
  @override
  bool get isRolling => false;
  @override
  ThemeMode get themeMode => ThemeMode.system;
  @override
  AnimationMode get rollcallAnimationMode => AnimationMode.auto;
  @override
  int get selectCount => 1;
  @override
  int get remainingCount => 0;
  @override
  int get totalCount => 0;
  @override
  bool get fairDrawEnabled => false;
  @override
  bool get nonRepeatEnabled => false;
  @override
  double get rollcallResultFontSize => 48;
  @override
  String? get selectedClass => null;
  @override
  String? get selectedGroup => null;
  @override
  String? get selectedGender => null;
  @override
  List<HistoryRecord> get history => [];
  @override
  List<Student> get filteredStudents => [];
  @override
  List<String> get groups => [];

  @override
  void setThemeMode(ThemeMode mode) {}
  @override
  void setSelectCount(int count) {}
  @override
  void setFairDrawEnabled(bool enabled) {}
  @override
  void setNonRepeatEnabled(bool enabled) {}
  @override
  void setRollcallResultFontSize(double value) {}
  @override
  void setLotteryResultFontSize(double value) {}
  @override
  void setRollcallAnimationMode(AnimationMode mode) {}
  @override
  void setLotteryAnimationMode(AnimationMode mode) {}
  @override
  void setSelectedClass(String? className) {}
  @override
  void setSelectedGroup(String? groupName) {}
  @override
  void setSelectedGender(String? gender) {}
  @override
  Future<void> startRollCall() async {}
  @override
  Future<void> stopRollCall() async {}
  @override
  Future<void> waitForPendingConfigSave() async {}
  @override
  List<String> getGroupsForClass(String? className) => [];
  @override
  Future<void> addGroupToClass(String className, String groupName) async {}
  @override
  Future<void> renameGroupInClass(String className, String oldName, String newName) async {}
  @override
  Future<void> deleteGroupFromClass(String className, String groupName) async {}
  @override
  Future<void> addClass(String className) async {}
  @override
  Future<void> renameClass(String oldName, String newName) async {}
  @override
  Future<void> deleteClass(String className) async {}
  @override
  Future<void> addStudentToClass(String className, {required String name, required String gender, required String group, bool exist = true}) async {}
  @override
  Future<void> updateStudentInClass(String className, int id, {String? name, String? gender, String? group, bool? exist}) async {}
  @override
  Future<void> deleteStudentFromClass(String className, int id) async {}
  @override
  Future<void> setStudentExistInClass(String className, int id, bool exist) async {}
  @override
  Future<void> addStudent(String name, String gender, String group, String className) async {}
  @override
  Future<void> updateStudentName(int id, String newName) async {}
  @override
  Future<void> updateStudentGroup(int id, String newGroup) async {}
  @override
  Future<void> updateStudentGender(int id, String newGender) async {}
  @override
  Future<void> deleteStudent(int id) async {}
  @override
  Future<BatchImportResult> batchImportStudents(String className, {required List<String> names, required List<String> genders, required List<String> groups, bool exist = true, int batchSize = 100, Function(int current, int total)? onProgress}) async =>
      const BatchImportResult(successCount: 0, failCount: 0);
  @override
  Future<void> clearHistory({String? className}) async {}
  @override
  Future<void> finalizeRollCall({int? sessionId}) async {}
}

Future<PrizePool> _seedLotteryData() async {
  final service = LotteryService();
  const poolName = '测试奖池';
  final pool = PrizePool(name: poolName, drawType: 1, drawMode: 0);

  await service.clearLotteryRecords();
  service.resetDrawnRecords(poolName);
  await service.savePrizePool(pool);
  await service.savePrizes(poolName, [
    Prize(id: 'p1', name: '一等奖', count: 3, weight: 1),
    Prize(id: 'p2', name: '二等奖', count: 3, weight: 1),
  ]);

  return pool;
}

Future<void> _pumpLotteryScreen(
  WidgetTester tester,
  AppProvider provider,
) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });

  await tester.pumpWidget(
    ChangeNotifierProvider<AppProvider>.value(
      value: provider,
      child: const MaterialApp(home: LotteryScreen()),
    ),
  );

  // Wait for LotteryScreen to load data and render the control panel
  for (int i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byKey(LotteryControlPanel.startButtonKey).evaluate().isNotEmpty) {
      // Additional pump to ensure data is fully loaded
      await tester.pump(const Duration(milliseconds: 200));
      return;
    }
  }

  fail('LotteryScreen did not load in time');
}

Future<void> _pumpControlPanel(
  WidgetTester tester, {
  required LotteryControlPanelLayoutMode layoutMode,
  required AnimationMode animationMode,
  required bool isDrawing,
  required bool controlsLocked,
  required void Function() onStartDraw,
  required void Function() onStopDraw,
}) async {
  final pool = PrizePool(name: '测试奖池', drawType: 1, drawMode: 0);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 640,
          child: LotteryControlPanel(
            layoutMode: layoutMode,
            prizePools: [pool],
            selectedPool: pool,
            drawCount: 2,
            totalPrizeCount: 6,
            remainingPrizeCount: 4,
            animationMode: animationMode,
            isDrawing: isDrawing,
            controlsLocked: controlsLocked,
            onPoolChanged: (_) {},
            onDrawCountChanged: (_) {},
            onStartDraw: onStartDraw,
            onStopDraw: onStopDraw,
            onResetDraw: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder _startButtonFinder() => find.byKey(LotteryControlPanel.startButtonKey);

FilledButton _startButtonWidget(WidgetTester tester) {
  return tester.widget<FilledButton>(_startButtonFinder());
}

OutlinedButton _resetButtonWidget(WidgetTester tester) {
  return tester.widget<OutlinedButton>(
    find.byKey(LotteryControlPanel.resetButtonKey),
  );
}

IconButton _iconButton(WidgetTester tester, Key key) {
  return tester.widget<IconButton>(find.byKey(key));
}

DropdownButtonFormField<PrizePool> _poolDropdown(WidgetTester tester) {
  return tester.widget<DropdownButtonFormField<PrizePool>>(
    find.byKey(LotteryControlPanel.poolDropdownKey),
  );
}

void _expectPrimaryButton(
  WidgetTester tester, {
  required String label,
  required bool enabled,
}) {
  expect(find.text(label), findsOneWidget);
  expect(_startButtonWidget(tester).onPressed == null, !enabled);
}

void _expectRoundControlsLocked(WidgetTester tester, {required bool locked}) {
  expect(
    _iconButton(tester, LotteryControlPanel.decrementDrawCountKey).onPressed ==
        null,
    locked,
  );
  expect(
    _iconButton(tester, LotteryControlPanel.incrementDrawCountKey).onPressed ==
        null,
    locked,
  );
  expect(_resetButtonWidget(tester).onPressed == null, locked);
  expect(_poolDropdown(tester).onChanged == null, locked);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await _cleanupDataDirs();
  });

  final layouts = <String, LotteryControlPanelLayoutMode>{
    'normal': LotteryControlPanelLayoutMode.normal,
    'compact': LotteryControlPanelLayoutMode.compact,
    'ultraCompact': LotteryControlPanelLayoutMode.ultraCompact,
  };

  testWidgets(
    'manualStop layout shows stop button and locks round-changing controls in all layouts',
    (tester) async {
      for (final entry in layouts.entries) {
        int startCalls = 0;
        int stopCalls = 0;

        await _pumpControlPanel(
          tester,
          layoutMode: entry.value,
          animationMode: AnimationMode.manualStop,
          isDrawing: true,
          controlsLocked: true,
          onStartDraw: () {
            startCalls++;
          },
          onStopDraw: () {
            stopCalls++;
          },
        );

        _expectPrimaryButton(tester, label: '停止', enabled: true);
        _expectRoundControlsLocked(tester, locked: true);

        await tester.tap(_startButtonFinder());
        await tester.pump();

        expect(startCalls, 0, reason: entry.key);
        expect(stopCalls, 1, reason: entry.key);
      }
    },
  );

  testWidgets(
    'auto layout disables the primary button and keeps round-changing controls locked in all layouts',
    (tester) async {
      for (final entry in layouts.entries) {
        await _pumpControlPanel(
          tester,
          layoutMode: entry.value,
          animationMode: AnimationMode.auto,
          isDrawing: true,
          controlsLocked: true,
          onStartDraw: () {},
          onStopDraw: () {},
        );

        _expectPrimaryButton(tester, label: '抽奖中...', enabled: false);
        _expectRoundControlsLocked(tester, locked: true);
      }
    },
  );

  testWidgets(
    'none layout settles to start state and unlocks controls in all layouts',
    (tester) async {
      for (final entry in layouts.entries) {
        int startCalls = 0;

        await _pumpControlPanel(
          tester,
          layoutMode: entry.value,
          animationMode: AnimationMode.none,
          isDrawing: false,
          controlsLocked: false,
          onStartDraw: () {
            startCalls++;
          },
          onStopDraw: () {},
        );

        _expectPrimaryButton(tester, label: '开始', enabled: true);
        _expectRoundControlsLocked(tester, locked: false);
        expect(find.text('抽奖中...'), findsNothing);

        await tester.tap(_startButtonFinder());
        await tester.pump();

        expect(startCalls, 1, reason: entry.key);
      }
    },
  );

  testWidgets('manualStop defers record persistence until explicit stop', (
    tester,
  ) async {
    final pool = await _seedLotteryData();
    final service = LotteryService();
    final provider = _FakeLotteryScreenProvider(AnimationMode.manualStop);

    await _pumpLotteryScreen(tester, provider);

    expect(await service.loadLotteryRecords(poolName: pool.name), isEmpty);

    await tester.tap(_startButtonFinder());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.text('停止'), findsOneWidget);
    expect(await service.loadLotteryRecords(poolName: pool.name), isEmpty);

    await tester.tap(_startButtonFinder());
    await tester.pump();
    await tester.pumpAndSettle();

    final records = await service.loadLotteryRecords(poolName: pool.name);
    expect(records.length, 1);
    expect(find.text('开始'), findsOneWidget);
  });

  testWidgets('repeated stop and teardown finalize lottery only once', (
    tester,
  ) async {
    final pool = await _seedLotteryData();
    final service = LotteryService();
    final provider = _FakeLotteryScreenProvider(AnimationMode.manualStop);

    await _pumpLotteryScreen(tester, provider);

    await tester.tap(_startButtonFinder());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));

    await tester.tap(_startButtonFinder());
    await tester.tap(_startButtonFinder());
    await tester.pump();

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final records = await service.loadLotteryRecords(poolName: pool.name);
    expect(records.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('none mode finalizes immediately without lingering draw state', (
    tester,
  ) async {
    final pool = await _seedLotteryData();
    final service = LotteryService();
    final provider = _FakeLotteryScreenProvider(AnimationMode.none);

    await _pumpLotteryScreen(tester, provider);

    await tester.tap(_startButtonFinder());
    await tester.pump();

    expect(find.text('抽奖中...'), findsNothing);
    expect(find.text('停止'), findsNothing);

    await tester.pumpAndSettle();

    final records = await service.loadLotteryRecords(poolName: pool.name);
    expect(records.length, 1);
    expect(find.text('开始'), findsOneWidget);
  });
}
