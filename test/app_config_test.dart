import 'package:secrandom_lite/models/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig fair draw', () {
    test('fromJson should default fairDrawEnabled to true for old data', () {
      final config = AppConfig.fromJson({
        'theme_mode': 'system',
        'select_count': 1,
      });

      expect(config.fairDrawEnabled, isTrue);
    });

    test('toJson should persist fairDrawEnabled', () {
      final config = AppConfig(
        themeMode: 'dark',
        selectCount: 2,
        fairDrawEnabled: false,
      );

      final json = config.toJson();
      expect(json['fair_draw_enabled'], isFalse);
    });
  });

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
    test('fromJson should default result font sizes to 48 for old data', () {
      final config = AppConfig.fromJson({
        'theme_mode': 'system',
        'select_count': 1,
      });

      expect(config.rollcallResultFontSize, 48);
      expect(config.lotteryResultFontSize, 48);
    });

    test('toJson should persist result font sizes', () {
      final config = AppConfig(
        themeMode: 'dark',
        rollcallResultFontSize: 52,
        lotteryResultFontSize: 44,
      );

      final json = config.toJson();
      expect(json['rollcall_result_font_size'], 52);
      expect(json['lottery_result_font_size'], 44);
    });
  });
}
