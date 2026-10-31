import 'package:flutter_test/flutter_test.dart';
import 'package:secrandom_lite/models/app_config.dart';
import 'package:secrandom_lite/providers/app_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers/isolated_data_dir.dart';
import 'helpers/test_students.dart';

void _registerProviderTearDown(AppProvider provider) {
  addTearDown(() async {
    await provider.waitForPendingConfigSave();
    provider.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  isolateDataServiceDir();

  setUp(() async {
    clearTestDataDir();
    await seedTestStudents();
    SharedPreferences.setMockInitialValues({});
  });

  test('manual stop defers rollcall side effects until stop', () async {
    final provider = AppProvider();
    _registerProviderTearDown(provider);
    await provider.ready;

    provider.setNonRepeatEnabled(true);
    provider.setSelectCount(1);
    provider.setRollcallAnimationMode(AnimationMode.manualStop);

    final beforeRemaining = provider.remainingCount;
    final beforeHistoryCount = provider.history.length;

    await provider.startRollCall();

    expect(provider.isRolling, isTrue);
    expect(provider.currentSelection, isEmpty);
    expect(provider.remainingCount, beforeRemaining);
    expect(provider.history.length, beforeHistoryCount);

    await provider.stopRollCall();

    expect(provider.isRolling, isFalse);
    expect(provider.currentSelection.length, 1);
    expect(provider.remainingCount, beforeRemaining - 1);
    expect(provider.history.length, beforeHistoryCount + 1);
  });

  test('repeated stop only finalizes manual rollcall once', () async {
    final provider = AppProvider();
    _registerProviderTearDown(provider);
    await provider.ready;

    provider.setNonRepeatEnabled(true);
    provider.setSelectCount(1);
    provider.setRollcallAnimationMode(AnimationMode.manualStop);

    final beforeRemaining = provider.remainingCount;
    final beforeHistoryCount = provider.history.length;

    await provider.startRollCall();
    await Future.wait([provider.stopRollCall(), provider.stopRollCall()]);

    expect(provider.isRolling, isFalse);
    expect(provider.currentSelection.length, 1);
    expect(provider.remainingCount, beforeRemaining - 1);
    expect(provider.history.length, beforeHistoryCount + 1);
  });

  test(
    'none mode finalizes immediately without lingering rolling state',
    () async {
      final provider = AppProvider();
      _registerProviderTearDown(provider);
      await provider.ready;

      provider.setNonRepeatEnabled(true);
      provider.setSelectCount(1);
      provider.setRollcallAnimationMode(AnimationMode.none);

      final beforeRemaining = provider.remainingCount;
      final beforeHistoryCount = provider.history.length;

      await provider.startRollCall();

      expect(provider.isRolling, isFalse);
      expect(provider.currentSelection.length, 1);
      expect(provider.remainingCount, beforeRemaining - 1);
      expect(provider.history.length, beforeHistoryCount + 1);

      await provider.stopRollCall();

      expect(provider.isRolling, isFalse);
      expect(provider.currentSelection.length, 1);
      expect(provider.remainingCount, beforeRemaining - 1);
      expect(provider.history.length, beforeHistoryCount + 1);
    },
  );

  test('rollcall and lottery animation modes persist independently', () async {
    final provider = AppProvider();
    _registerProviderTearDown(provider);
    await provider.ready;

    provider.setRollcallAnimationMode(AnimationMode.manualStop);
    provider.setLotteryAnimationMode(AnimationMode.none);
    await provider.waitForPendingConfigSave();

    final reloadedProvider = AppProvider();
    _registerProviderTearDown(reloadedProvider);
    await reloadedProvider.ready;

    expect(reloadedProvider.rollcallAnimationMode, AnimationMode.manualStop);
    expect(reloadedProvider.lotteryAnimationMode, AnimationMode.none);
  });
}
