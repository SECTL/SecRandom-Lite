import 'package:flutter/material.dart';

import '../utils/responsive_layout_decider.dart';
import '../widgets/control_panel.dart';
import '../widgets/name_display.dart';
import '../widgets/nav_rail.dart';
import '../widgets/slide_panel.dart';
import 'history/history_screen.dart';
import 'lottery_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const double _kRailMinWidth = 700;
  static const double _kPanelWidth = 280;
  static const double _kPanelGap = 24;
  static const double _kNarrowPanelHeight = 300;
  static const double _kSafeEpsilon = 0.75;
  static const Duration _kResizeDebounce = Duration(milliseconds: 150);
  static const Duration _kStateSwitchMinInterval = Duration(milliseconds: 150);

  int _selectedIndex = 0;

  final GlobalKey _rollCallContentKey = GlobalKey();
  final GlobalKey _rollCallLargePanelKey = GlobalKey();
  final GlobalKey _rollCallPortraitPanelKey = GlobalKey();

  ResponsiveScreenState _rollCallState = ResponsiveScreenState.large;
  bool _rollCallMeasurePending = false;
  DateTime? _rollCallLastMeasureAt;
  DateTime? _rollCallLastStateSwitchAt;
  double _rollCallLastWidth = -1;
  double _rollCallLastHeight = -1;
  double _rollCallLastLargePanelHeight = 320;
  double _rollCallLastPortraitPanelHeight = _kNarrowPanelHeight;

  void _openSlidePanel(Widget panelContent) {
    SlidePanelOverlay.show(context: context, child: panelContent);
  }

  void _scheduleRollCallStateMeasurement(Size contentSize) {
    final now = DateTime.now();
    final widthChanged = (contentSize.width - _rollCallLastWidth).abs() > 0.5;
    final heightChanged =
        (contentSize.height - _rollCallLastHeight).abs() > 0.5;
    if (!widthChanged && !heightChanged) {
      return;
    }
    if (_rollCallMeasurePending) {
      return;
    }
    if (_rollCallLastMeasureAt != null &&
        now.difference(_rollCallLastMeasureAt!) < _kResizeDebounce) {
      return;
    }

    _rollCallLastMeasureAt = now;
    _rollCallLastWidth = contentSize.width;
    _rollCallLastHeight = contentSize.height;
    _rollCallMeasurePending = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rollCallMeasurePending = false;
      if (!mounted) {
        return;
      }

      final contentTop = _readTop(_rollCallContentKey);
      if (contentTop == null) {
        return;
      }
      final largePanelHeight =
          _readHeight(_rollCallLargePanelKey) ?? _rollCallLastLargePanelHeight;
      final portraitPanelHeight =
          _readHeight(_rollCallPortraitPanelKey) ??
          _rollCallLastPortraitPanelHeight;
      _rollCallLastLargePanelHeight = largePanelHeight;
      _rollCallLastPortraitPanelHeight = portraitPanelHeight;

      final largeResultWidth = contentSize.width - (_kPanelWidth + _kPanelGap);
      final largePanelTop =
          contentTop + contentSize.height - _kPanelGap - largePanelHeight;
      final portraitResultHeight = contentSize.height - portraitPanelHeight;
      final shortResultWidth = contentSize.width - (_kPanelWidth + _kPanelGap);

      final nextState = decideResponsiveScreenState(
        ResponsiveLayoutDecisionInput(
          contentWidth: contentSize.width,
          contentHeight: contentSize.height,
          largeResultWidth: largeResultWidth,
          largePanelTop: largePanelTop,
          contentTop: contentTop,
          portraitResultHeight: portraitResultHeight,
          shortResultWidth: shortResultWidth,
        ),
        epsilon: _kSafeEpsilon,
      );

      if (nextState != _rollCallState) {
        final switchNow = DateTime.now();
        if (_rollCallLastStateSwitchAt != null &&
            switchNow.difference(_rollCallLastStateSwitchAt!) <
                _kStateSwitchMinInterval) {
          return;
        }
        _rollCallLastStateSwitchAt = switchNow;
        setState(() {
          _rollCallState = nextState;
        });
      }
    });
  }

  double? _readHeight(GlobalKey key) {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is RenderBox) {
      return renderObject.size.height;
    }
    return null;
  }

  double? _readTop(GlobalKey key) {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is RenderBox) {
      return renderObject.localToGlobal(Offset.zero).dy;
    }
    return null;
  }

  Widget _buildRollCallDrawerLayout() {
    return Stack(
      key: const ValueKey('rollcall_layout_small'),
      children: [
        Positioned.fill(
          child: Container(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: NameDisplay(isWideScreen: false),
            ),
          ),
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: FloatingActionButton.small(
            heroTag: 'rollcall_panel_fab',
            onPressed: () {
              _openSlidePanel(
                const ControlPanel(
                  layoutMode: ControlPanelLayoutMode.compact,
                  fillHeight: false,
                ),
              );
            },
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
            child: const Icon(Icons.tune, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _buildRollCallLargeLayout(double contentHeight) {
    const rightPanelReservedWidth = _kPanelWidth + _kPanelGap;
    final panelAvailableHeight = contentHeight - (_kPanelGap * 2);

    return Stack(
      key: const ValueKey('rollcall_layout_large'),
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
            key: _rollCallLargePanelKey,
            width: _kPanelWidth,
            child: ControlPanel(
              layoutMode: ControlPanelLayoutMode.normal,
              availableHeight: panelAvailableHeight,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRollCallPortraitLayout() {
    return SafeArea(
      key: const ValueKey('rollcall_layout_portrait'),
      child: Column(
        children: [
          const Expanded(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: NameDisplay(isWideScreen: false),
            ),
          ),
          Container(
            key: _rollCallPortraitPanelKey,
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
            constraints: const BoxConstraints(maxHeight: _kNarrowPanelHeight),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: ControlPanel(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRollCallShortLayout(double contentHeight) {
    final panelAvailableHeight = contentHeight;

    return Padding(
      key: const ValueKey('rollcall_layout_short'),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Expanded(
            child: Padding(
              padding: EdgeInsets.all(8),
              child: NameDisplay(isWideScreen: true),
            ),
          ),
          const SizedBox(width: _kPanelGap),
          SizedBox(
            width: _kPanelWidth,
            child: ControlPanel(
              layoutMode: ControlPanelLayoutMode.compact,
              availableHeight: panelAvailableHeight,
              fillHeight: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRollCallScreen() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentSize = Size(constraints.maxWidth, constraints.maxHeight);
        _scheduleRollCallStateMeasurement(contentSize);

        Widget child;
        switch (_rollCallState) {
          case ResponsiveScreenState.large:
            child = _buildRollCallLargeLayout(contentSize.height);
            break;
          case ResponsiveScreenState.portrait:
            child = _buildRollCallPortraitLayout();
            break;
          case ResponsiveScreenState.short:
            child = _buildRollCallShortLayout(contentSize.height);
            break;
          case ResponsiveScreenState.small:
            child = _buildRollCallDrawerLayout();
            break;
        }

        return Container(
          key: _rollCallContentKey,
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Stack(children: [Positioned.fill(child: child)]),
        );
      },
    );
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return _buildRollCallScreen();
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isRailVisible = constraints.maxWidth >= _kRailMinWidth;

        return Scaffold(
          bottomNavigationBar: !isRailVisible
              ? NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) {
                    if (SlidePanelOverlay.isShowing) {
                      SlidePanelOverlay.hide();
                    }
                    setState(() => _selectedIndex = index);
                  },
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
                    if (SlidePanelOverlay.isShowing) {
                      SlidePanelOverlay.hide();
                    }
                    setState(() {
                      _selectedIndex = index;
                    });
                  },
                ),
              if (isRailVisible) const VerticalDivider(thickness: 1, width: 1),
              Expanded(child: _buildBody()),
            ],
          ),
        );
      },
    );
  }
}
