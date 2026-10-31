import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secrandom_lite/widgets/settings_layout.dart';

void main() {
  testWidgets('左侧导航切换时标题与图标颜色渐变', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsLayout(
            title: '设置',
            initialIndex: 0,
            items: [
              SettingItem(
                title: '甲',
                icon: Icons.person_outline,
                pageBuilder: () => const Text('甲内容'),
                routeName: '/a',
              ),
              SettingItem(
                title: '乙',
                icon: Icons.settings_outlined,
                pageBuilder: () => const Text('乙内容'),
                routeName: '/b',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Finder navTile(String title) => find.widgetWithText(ListTile, title);

    Color titleColor(String title) {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: navTile(title), matching: find.text(title)),
      );
      return paragraph.text.style!.color!;
    }

    FontWeight? titleWeight(String title) {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: navTile(title), matching: find.text(title)),
      );
      return paragraph.text.style?.fontWeight;
    }

    Color iconColor(String title) {
      final icon = tester.widget<Icon>(
        find.descendant(of: navTile(title), matching: find.byType(Icon)),
      );
      return icon.color!;
    }

    final theme = Theme.of(tester.element(find.byType(SettingsLayout)));
    final selectedColor = theme.colorScheme.primary;
    final unselectedColor = theme.colorScheme.onSurface;
    final unselectedIconColor = unselectedColor.withValues(alpha: 0.6);

    expect(titleColor('甲'), selectedColor);
    expect(titleColor('乙'), unselectedColor);
    expect(titleWeight('甲'), isNot(FontWeight.bold));
    expect(titleWeight('乙'), isNot(FontWeight.bold));
    expect(iconColor('甲'), selectedColor);
    expect(iconColor('乙'), unselectedIconColor);

    await tester.tap(navTile('乙'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final fading = titleColor('甲');
    expect(fading, isNot(selectedColor));
    expect(fading, isNot(unselectedColor));
    final fadingIcon = iconColor('甲');
    expect(fadingIcon, isNot(selectedColor));
    expect(fadingIcon, isNot(unselectedIconColor));

    await tester.pumpAndSettle();
    expect(titleColor('甲'), unselectedColor);
    expect(titleColor('乙'), selectedColor);
    expect(titleWeight('乙'), isNot(FontWeight.bold));
    expect(iconColor('甲'), unselectedIconColor);
    expect(iconColor('乙'), selectedColor);
  });
}
