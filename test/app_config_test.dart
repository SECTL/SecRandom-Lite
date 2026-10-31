import 'package:secrandom_lite/models/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig non repeat draw', () {
    test('fromJson should default nonRepeatEnabled to true for old data', () {
      final config = AppConfig.fromJson({
        'theme_mode': 'system',
        'select_count': 1,
      });

      expect(config.nonRepeatEnabled, isTrue);
    });

    test('toJson should persist nonRepeatEnabled', () {
      final config = AppConfig(
        themeMode: 'dark',
        selectCount: 2,
        nonRepeatEnabled: false,
      );

      final json = config.toJson();
      expect(json['non_repeat_enabled'], isFalse);
    });
  });

  group('AppConfig result font size', () {
    test('fromJson should default result font size to 48 for old data', () {
      final config = AppConfig.fromJson({
        'theme_mode': 'system',
        'select_count': 1,
      });

      expect(config.rollcallResultFontSize, 48);
    });

    test('toJson should persist result font size', () {
      final config = AppConfig(themeMode: 'dark', rollcallResultFontSize: 52);

      final json = config.toJson();
      expect(json['rollcall_result_font_size'], 52);
    });
  });

  group('AppConfig animation mode', () {
    test('fromJson should default animation mode to auto for old data', () {
      final config = AppConfig.fromJson({
        'theme_mode': 'system',
        'select_count': 1,
      });

      expect(config.rollcallAnimationMode, AnimationMode.auto);
    });

    test('fromJson should fall back to auto for invalid animation values', () {
      final config = AppConfig.fromJson({
        'theme_mode': 'system',
        'select_count': 1,
        'rollcall_animation_mode': 'invalid',
      });

      expect(config.rollcallAnimationMode, AnimationMode.auto);
    });

    test('toJson should persist animation mode', () {
      final config = AppConfig(
        themeMode: 'dark',
        rollcallAnimationMode: AnimationMode.manualStop,
      );

      final json = config.toJson();
      expect(json['rollcall_animation_mode'], 'manualStop');

      final restored = AppConfig.fromJson(json);
      expect(restored.rollcallAnimationMode, AnimationMode.manualStop);
    });
  });
}
