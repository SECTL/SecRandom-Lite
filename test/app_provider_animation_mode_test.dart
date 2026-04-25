import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:secrandom_lite/models/app_config.dart';
import 'package:secrandom_lite/providers/app_provider.dart';
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

Future<void> _waitForProviderLoaded(AppProvider provider) async {
  for (int i = 0; i < 120; i++) {
    if (provider.totalCount > 0) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('AppProvider did not finish loading in time');
}

Future<void> _waitForPersistence() async {
  await Future<void>.delayed(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await _cleanupDataDirs();
  });

  test('manual stop defers rollcall side effects until stop', () async {
    final provider = AppProvider();
    await _waitForProviderLoaded(provider);

    provider.setFairDrawEnabled(false);
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

    provider.dispose();
  });

  test('repeated stop only finalizes manual rollcall once', () async {
    final provider = AppProvider();
    await _waitForProviderLoaded(provider);

    provider.setFairDrawEnabled(false);
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

    provider.dispose();
  });

  test('rollcall and lottery animation modes persist independently', () async {
    final provider = AppProvider();
    await _waitForProviderLoaded(provider);

    provider.setRollcallAnimationMode(AnimationMode.manualStop);
    provider.setLotteryAnimationMode(AnimationMode.none);
    await _waitForPersistence();
    provider.dispose();

    final reloadedProvider = AppProvider();
    await _waitForProviderLoaded(reloadedProvider);

    expect(reloadedProvider.rollcallAnimationMode, AnimationMode.manualStop);
    expect(reloadedProvider.lotteryAnimationMode, AnimationMode.none);

    reloadedProvider.dispose();
  });
}
