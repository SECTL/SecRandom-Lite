import 'package:secrandom_lite/models/app_config.dart';
import 'package:secrandom_lite/providers/app_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers/isolated_data_dir.dart';
import 'helpers/test_students.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  isolateDataServiceDir();

  setUp(() async {
    clearTestDataDir();
    await seedTestStudents();
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'nonRepeatEnabled=true should decrease remainingCount after draw',
    () async {
      final provider = AppProvider();
      await provider.ready;

      provider.setFairDrawEnabled(false);
      provider.setNonRepeatEnabled(true);
      provider.setSelectCount(1);
      // 并行测试文件共享磁盘 data/ 目录，其它文件可能把 config 的动画模式
      // 写成 manualStop（startRollCall 不会产出结果）；显式钉住 none。
      provider.setRollcallAnimationMode(AnimationMode.none);

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
      await provider.ready;

      provider.setFairDrawEnabled(false);
      provider.setNonRepeatEnabled(false);
      provider.setSelectCount(1);
      provider.setRollcallAnimationMode(AnimationMode.none);

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
    await provider.ready;

    provider.setFairDrawEnabled(false);
    provider.setNonRepeatEnabled(true);
    provider.setSelectCount(1);
    provider.setRollcallAnimationMode(AnimationMode.none);

    await provider.startRollCall();
    expect(provider.remainingCount, lessThan(provider.totalCount));

    provider.setNonRepeatEnabled(false);
    expect(provider.remainingCount, provider.totalCount);

    provider.dispose();
  });
}
