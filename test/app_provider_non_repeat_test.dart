import 'dart:io';

import 'package:SecRandom_lutter/providers/app_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await _cleanupDataDirs();
  });

  test(
    'nonRepeatEnabled=true should decrease remainingCount after draw',
    () async {
      final provider = AppProvider();
      await _waitForProviderLoaded(provider);

      provider.setFairDrawEnabled(false);
      provider.setNonRepeatEnabled(true);
      provider.setSelectCount(1);

      final before = provider.remainingCount;
      await provider.startRollCall();

      expect(provider.currentSelection.length, 1);
      expect(provider.remainingCount, before - 1);

      provider.dispose();
    },
  );

  test(
    'nonRepeatEnabled=false should keep remainingCount equal to totalCount',
    () async {
      final provider = AppProvider();
      await _waitForProviderLoaded(provider);

      provider.setFairDrawEnabled(false);
      provider.setNonRepeatEnabled(false);
      provider.setSelectCount(1);

      final total = provider.totalCount;
      expect(provider.remainingCount, total);

      await provider.startRollCall();
      expect(provider.currentSelection.length, 1);
      expect(provider.remainingCount, total);

      await provider.startRollCall();
      expect(provider.remainingCount, total);

      provider.dispose();
    },
  );

  test('toggling nonRepeatEnabled off should reset remaining pool', () async {
    final provider = AppProvider();
    await _waitForProviderLoaded(provider);

    provider.setFairDrawEnabled(false);
    provider.setNonRepeatEnabled(true);
    provider.setSelectCount(1);

    await provider.startRollCall();
    expect(provider.remainingCount, lessThan(provider.totalCount));

    provider.setNonRepeatEnabled(false);
    expect(provider.remainingCount, provider.totalCount);

    provider.dispose();
  });
}
