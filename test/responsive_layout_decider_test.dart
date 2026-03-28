import 'package:SecRandom_lutter/utils/responsive_layout_decider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decideResponsiveScreenState', () {
    test('keeps large when width >= 50% and panel does not overflow', () {
      const input = ResponsiveLayoutDecisionInput(
        contentWidth: 1000,
        contentHeight: 700,
        largeResultWidth: 500,
        largePanelTop: 40,
        contentTop: 10,
        portraitResultHeight: 500,
        shortResultWidth: 600,
      );

      final result = decideResponsiveScreenState(input, epsilon: 0.5);
      expect(result, ResponsiveScreenState.large);
    });

    test('large -> portrait when result width is less than 50%', () {
      const input = ResponsiveLayoutDecisionInput(
        contentWidth: 1000,
        contentHeight: 700,
        largeResultWidth: 499,
        largePanelTop: 40,
        contentTop: 10,
        portraitResultHeight: 500,
        shortResultWidth: 600,
      );

      final result = decideResponsiveScreenState(input, epsilon: 0.0);
      expect(result, ResponsiveScreenState.portrait);
    });

    test('large -> short when panel top overflows content top', () {
      const input = ResponsiveLayoutDecisionInput(
        contentWidth: 1000,
        contentHeight: 700,
        largeResultWidth: 600,
        largePanelTop: 10,
        contentTop: 10,
        portraitResultHeight: 500,
        shortResultWidth: 600,
      );

      final result = decideResponsiveScreenState(input, epsilon: 0.5);
      expect(result, ResponsiveScreenState.short);
    });

    test('portrait -> small when result height is less than 25%', () {
      const input = ResponsiveLayoutDecisionInput(
        contentWidth: 1000,
        contentHeight: 800,
        largeResultWidth: 490,
        largePanelTop: 40,
        contentTop: 10,
        portraitResultHeight: 199,
        shortResultWidth: 600,
      );

      final result = decideResponsiveScreenState(input, epsilon: 0.0);
      expect(result, ResponsiveScreenState.small);
    });

    test('short -> small when result width is less than 50%', () {
      const input = ResponsiveLayoutDecisionInput(
        contentWidth: 1000,
        contentHeight: 800,
        largeResultWidth: 600,
        largePanelTop: 9,
        contentTop: 10,
        portraitResultHeight: 500,
        shortResultWidth: 499,
      );

      final result = decideResponsiveScreenState(input, epsilon: 0.0);
      expect(result, ResponsiveScreenState.small);
    });
  });
}
