import 'package:flutter/material.dart';

import '../widgets/control_panel.dart';
import '../widgets/name_display.dart';
import '../widgets/nav_rail.dart';
import 'history_screen.dart';
import 'lottery_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const double _kPhoneLandscapeAspectRatioMin = 1.55;
  static const double _kPhoneLandscapeMinWidth = 560;
  static const double _kPhoneMaxShortestSide = 500;
  static const double _kRailMinWidth = 700;
  static const double _kPanelWidth = 280;
  static const double _kPanelGap = 24;

  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double aspectRatio = constraints.maxWidth / constraints.maxHeight;
        final double shortestSide = constraints.biggest.shortestSide;
        final bool isLandscapePhone =
            aspectRatio >= _kPhoneLandscapeAspectRatioMin &&
            constraints.maxWidth >= _kPhoneLandscapeMinWidth &&
            shortestSide <= _kPhoneMaxShortestSide;
        final bool isWideScreen = constraints.maxWidth > 800 || isLandscapePhone;
        final bool isRailVisible = constraints.maxWidth >= _kRailMinWidth;

        return Scaffold(
          bottomNavigationBar: !isRailVisible
              ? NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) =>
                      setState(() => _selectedIndex = index),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.people_outline),
                      label: '点名',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.card_giftcard_outlined),
                      label: '抽奖',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.history_outlined),
                      label: '历史记录',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.settings_outlined),
                      label: '设置',
                    ),
                  ],
                )
              : null,
          body: Row(
            children: [
              if (isRailVisible)
                NavRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (int index) {
                    setState(() {
                      _selectedIndex = index;
                    });
                  },
                ),
              if (isRailVisible) const VerticalDivider(thickness: 1, width: 1),
              Expanded(child: _buildBody(isWideScreen, constraints)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(bool isWideScreen, BoxConstraints viewportConstraints) {
    switch (_selectedIndex) {
      case 0:
        if (isWideScreen) {
          final normalPanelAvailableHeight =
              viewportConstraints.maxHeight - (_kPanelGap * 2);
          const rightPanelReservedWidth = _kPanelWidth + _kPanelGap;

          return Container(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: Stack(
              children: [
                const Positioned(
                  left: 0,
                  right: rightPanelReservedWidth,
                  top: 0,
                  bottom: 0,
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: NameDisplay(isWideScreen: true),
                  ),
                ),
                Positioned(
                  right: _kPanelGap,
                  bottom: _kPanelGap,
                  child: SizedBox(
                    width: _kPanelWidth,
                    child: ControlPanel(
                      layoutMode: ControlPanelLayoutMode.autoFit,
                      availableHeight: normalPanelAvailableHeight,
                    ),
                  ),
                ),
              ],
            ),
          );
        } else {
          return Container(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: Column(
              children: [
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: NameDisplay(isWideScreen: false),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: const ControlPanel(),
                ),
              ],
            ),
          );
        }
      case 1:
        return const LotteryScreen();
      case 2:
        return const HistoryScreen();
      case 3:
        return const SettingsScreen();
      default:
        return const SizedBox.shrink();
    }
  }
}
