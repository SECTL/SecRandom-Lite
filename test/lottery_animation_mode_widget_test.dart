import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secrandom_lite/models/app_config.dart';
import 'package:secrandom_lite/models/prize_pool.dart';
import 'package:secrandom_lite/screens/lottery_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LotteryControlPanel', () {
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
        _iconButton(tester, LotteryControlPanel.decrementDrawCountKey).onPressed == null,
        locked,
      );
      expect(
        _iconButton(tester, LotteryControlPanel.incrementDrawCountKey).onPressed == null,
        locked,
      );
      expect(_resetButtonWidget(tester).onPressed == null, locked);
      expect(_poolDropdown(tester).onChanged == null, locked);
    }

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
            onStartDraw: () => startCalls++,
            onStopDraw: () => stopCalls++,
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
            onStartDraw: () => startCalls++,
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
  });
}
