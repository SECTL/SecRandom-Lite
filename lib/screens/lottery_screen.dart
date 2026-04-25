import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_config.dart';
import '../models/prize.dart';
import '../models/prize_pool.dart';
import '../models/lottery_record.dart';
import '../providers/app_provider.dart';
import '../services/lottery_service.dart';
import '../utils/responsive_layout_decider.dart';
import '../widgets/slide_panel.dart';

class LotteryScreen extends StatefulWidget {
  const LotteryScreen({super.key});

  @override
  State<LotteryScreen> createState() => _LotteryScreenState();
}

class _LotteryScreenState extends State<LotteryScreen> {
  static const double _kPanelWidth = 280;
  static const double _kPanelGap = 24;
  static const double _kNarrowPanelHeight = 300;
  static const double _kSafeEpsilon = 0.75;
  static const Duration _kResizeDebounce = Duration(milliseconds: 150);
  static const Duration _kStateSwitchMinInterval = Duration(milliseconds: 150);
  static const Duration _kAutoFinalizeDelay = Duration(seconds: 2);

  final LotteryService _lotteryService = LotteryService();
  final Random _random = Random.secure();

  Timer? _rollingTimer;
  Timer? _autoFinalizeTimer;
  List<LotteryRecord> _displayedRecords = [];
  bool _isDrawing = false;
  bool _isRoundActive = false;
  bool _isFinalizingDraw = false;
  int _drawSessionId = 0;

  List<PrizePool> _prizePools = [];
  List<Prize> _prizes = [];

  PrizePool? _selectedPool;

  int _drawCount = 1;
  final GlobalKey _lotteryContentKey = GlobalKey();
  final GlobalKey _lotteryLargePanelKey = GlobalKey();
  final GlobalKey _lotteryPortraitPanelKey = GlobalKey();

  ResponsiveScreenState _lotteryState = ResponsiveScreenState.large;
  bool _lotteryMeasurePending = false;
  DateTime? _lotteryLastMeasureAt;
  DateTime? _lotteryLastStateSwitchAt;
  double _lotteryLastWidth = -1;
  double _lotteryLastHeight = -1;
  double _lotteryLastLargePanelHeight = 320;
  double _lotteryLastPortraitPanelHeight = _kNarrowPanelHeight;

  @override
  void dispose() {
    _invalidateActiveRound();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final pools = await _lotteryService.loadPrizePools();

      if (mounted) {
        setState(() {
          _prizePools = pools;
          if (_prizePools.isNotEmpty) {
            _selectedPool = _prizePools.first;
          }
        });
        if (_selectedPool != null) {
          await _loadPrizes();
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _prizePools = [];
          _selectedPool = null;
          _prizes = [];
        });
      }
    }
  }

  Future<void> _loadPrizes() async {
    if (_selectedPool == null) return;
    try {
      final prizes = await _lotteryService.loadPrizes(_selectedPool!.name);
      if (mounted) {
        setState(() {
          _prizes = prizes;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _prizes = [];
        });
      }
    }
  }

  int get _totalPrizeCount {
    if (_selectedPool == null) return 0;
    return _lotteryService.getPrizeTotalCount(_selectedPool!, _prizes);
  }

  int get _remainingPrizeCount {
    if (_selectedPool == null) return 0;
    return _lotteryService.getPrizeRemainingCount(_selectedPool!, _prizes);
  }

  void _invalidateActiveRound() {
    _drawSessionId++;
    _cancelDrawTimers();
  }

  void _cancelDrawTimers() {
    _rollingTimer?.cancel();
    _rollingTimer = null;
    _autoFinalizeTimer?.cancel();
    _autoFinalizeTimer = null;
  }

  Future<void> _handlePoolChanged(PrizePool? pool) async {
    if (_isRoundActive) return;

    setState(() {
      _selectedPool = pool;
      _displayedRecords = [];
    });
    await _loadPrizes();
  }

  void _handleDrawCountChanged(int count) {
    if (_isRoundActive) return;

    setState(() {
      _drawCount = count;
    });
  }

  void _startDraw() {
    if (_selectedPool == null || _drawCount <= 0 || _isRoundActive) return;

    final animationMode = context.read<AppProvider>().lotteryAnimationMode;
    final pool = _selectedPool!;
    final availablePrizes = _lotteryService.getAvailablePrizes(pool, _prizes);

    if (availablePrizes.isEmpty) {
      return;
    }

    _drawSessionId++;
    final sessionId = _drawSessionId;

    setState(() {
      _displayedRecords = [];
      _isRoundActive = true;
      _isDrawing = animationMode != AnimationMode.none;
    });

    if (animationMode == AnimationMode.none) {
      unawaited(_finalizeDraw(sessionId: sessionId));
      return;
    }

    _startRollingAnimation(sessionId: sessionId, availablePrizes: availablePrizes);

    if (animationMode == AnimationMode.auto) {
      _autoFinalizeTimer = Timer(_kAutoFinalizeDelay, () {
        if (!mounted || sessionId != _drawSessionId) {
          return;
        }
        unawaited(_finalizeDraw(sessionId: sessionId));
      });
    }
  }

  void _startRollingAnimation({
    required int sessionId,
    required List<Prize> availablePrizes,
  }) {
    if (_rollingTimer != null && _rollingTimer!.isActive) return;
    if (_selectedPool == null || !_isRoundActive || !_isDrawing) {
      return;
    }

    final pool = _selectedPool!;
    final rollingDrawCount = _drawCount;

    _rollingTimer = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      if (!mounted || sessionId != _drawSessionId || !_isRoundActive || !_isDrawing) {
        timer.cancel();
        if (identical(_rollingTimer, timer)) {
          _rollingTimer = null;
        }
        return;
      }

      final List<LotteryRecord> rollingRecords = [];
      final now = DateTime.now();
      for (int i = 0; i < rollingDrawCount; i++) {
        final randomPrize =
            availablePrizes[_random.nextInt(availablePrizes.length)];
        rollingRecords.add(
          LotteryRecord(
            id: '${now.microsecondsSinceEpoch}_${sessionId}_$i',
            poolName: pool.name,
            prizeName: randomPrize.name,
            drawTime: now,
            drawCount: 1,
          ),
        );
      }

      if (mounted) {
        setState(() {
          _displayedRecords = rollingRecords;
        });
      }
    });
  }

  void _stopRollingAnimation({int? sessionId}) {
    if (sessionId != null && sessionId != _drawSessionId) {
      return;
    }
    _rollingTimer?.cancel();
    _rollingTimer = null;
  }

  void _stopDraw() {
    if (!_isRoundActive) return;
    unawaited(_finalizeDraw());
  }

  Future<void> _finalizeDraw({int? sessionId}) async {
    final activeSessionId = sessionId ?? _drawSessionId;
    if (_selectedPool == null ||
        !_isRoundActive ||
        _isFinalizingDraw ||
        activeSessionId != _drawSessionId) {
      return;
    }

    _isFinalizingDraw = true;
    _autoFinalizeTimer?.cancel();
    _autoFinalizeTimer = null;
    _stopRollingAnimation(sessionId: activeSessionId);

    final pool = _selectedPool!;

    try {
      final prizes = _lotteryService.drawPrizes(_prizes, _drawCount, pool);
      final drawTime = DateTime.now();
      final records = prizes
          .asMap()
          .entries
          .map(
            (entry) => LotteryRecord(
              id: '${drawTime.microsecondsSinceEpoch}_${activeSessionId}_${entry.key}',
              poolName: pool.name,
              prizeName: entry.value.name,
              drawTime: drawTime,
              drawCount: 1,
            ),
          )
          .toList();

      if (mounted) {
        setState(() {
          _displayedRecords = records;
          _isDrawing = false;
        });
      } else {
        _displayedRecords = records;
        _isDrawing = false;
      }

      for (var record in records) {
        await _lotteryService.saveLotteryRecord(record);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDrawing = false;
        });
      } else {
        _isDrawing = false;
      }
    } finally {
      if (mounted && activeSessionId == _drawSessionId) {
        setState(() {
          _isRoundActive = false;
        });
      } else {
        _isRoundActive = false;
      }
      _isFinalizingDraw = false;
    }
  }

  void _resetDraw() {
    if (_selectedPool == null || _isRoundActive) return;

    _lotteryService.resetDrawnRecords(_selectedPool!.name);

    if (mounted) {
      setState(() {
        _displayedRecords = [];
      });
    }
  }

  void _openSlidePanel() {
    final animationMode = context.read<AppProvider>().lotteryAnimationMode;

    SlidePanelOverlay.show(
      context: context,
      child: LotteryControlPanel(
        layoutMode: LotteryControlPanelLayoutMode.compact,
        fillHeight: false,
        prizePools: _prizePools,
        selectedPool: _selectedPool,
        drawCount: _drawCount,
        totalPrizeCount: _totalPrizeCount,
        remainingPrizeCount: _remainingPrizeCount,
        animationMode: animationMode,
        isDrawing: _isDrawing,
        controlsLocked: _isRoundActive,
        onPoolChanged: _handlePoolChanged,
        onDrawCountChanged: _handleDrawCountChanged,
        onStartDraw: _startDraw,
        onStopDraw: _stopDraw,
        onResetDraw: _resetDraw,
      ),
    );
  }

  void _scheduleLotteryStateMeasurement(Size contentSize) {
    final now = DateTime.now();
    final widthChanged = (contentSize.width - _lotteryLastWidth).abs() > 0.5;
    final heightChanged = (contentSize.height - _lotteryLastHeight).abs() > 0.5;
    if (!widthChanged && !heightChanged) {
      return;
    }
    if (_lotteryMeasurePending) {
      return;
    }
    if (_lotteryLastMeasureAt != null &&
        now.difference(_lotteryLastMeasureAt!) < _kResizeDebounce) {
      return;
    }

    _lotteryLastMeasureAt = now;
    _lotteryLastWidth = contentSize.width;
    _lotteryLastHeight = contentSize.height;
    _lotteryMeasurePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lotteryMeasurePending = false;
      if (!mounted) {
        return;
      }
      final contentTop = _readTop(_lotteryContentKey);
      if (contentTop == null) {
        return;
      }
      final largePanelHeight =
          _readHeight(_lotteryLargePanelKey) ?? _lotteryLastLargePanelHeight;
      final portraitPanelHeight =
          _readHeight(_lotteryPortraitPanelKey) ??
          _lotteryLastPortraitPanelHeight;
      _lotteryLastLargePanelHeight = largePanelHeight;
      _lotteryLastPortraitPanelHeight = portraitPanelHeight;

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

      if (nextState != _lotteryState) {
        final switchNow = DateTime.now();
        if (_lotteryLastStateSwitchAt != null &&
            switchNow.difference(_lotteryLastStateSwitchAt!) <
                _kStateSwitchMinInterval) {
          return;
        }
        _lotteryLastStateSwitchAt = switchNow;
        setState(() {
          _lotteryState = nextState;
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

  Widget _buildLotteryDrawerLayout() {
    return Stack(
      key: const ValueKey('lottery_layout_small'),
      children: [
        Positioned.fill(
          child: Container(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: LotteryResultDisplay(
                records: _displayedRecords,
                isWideScreen: false,
              ),
            ),
          ),
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: FloatingActionButton.small(
            heroTag: 'lottery_panel_fab',
            onPressed: _openSlidePanel,
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
            child: const Icon(Icons.tune, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _buildLotteryLargeLayout(double contentHeight) {
    const rightPanelReservedWidth = _kPanelWidth + _kPanelGap;
    final panelAvailableHeight = contentHeight - (_kPanelGap * 2);
    final animationMode = context.watch<AppProvider>().lotteryAnimationMode;

    return Stack(
      key: const ValueKey('lottery_layout_large'),
      children: [
        Positioned(
          left: 0,
          right: rightPanelReservedWidth,
          top: 0,
          bottom: 0,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: LotteryResultDisplay(
              records: _displayedRecords,
              isWideScreen: true,
            ),
          ),
        ),
        Positioned(
          right: _kPanelGap,
          bottom: _kPanelGap,
          child: SizedBox(
            key: _lotteryLargePanelKey,
            width: _kPanelWidth,
            child: LotteryControlPanel(
              layoutMode: LotteryControlPanelLayoutMode.normal,
              availableHeight: panelAvailableHeight,
              prizePools: _prizePools,
              selectedPool: _selectedPool,
              drawCount: _drawCount,
              totalPrizeCount: _totalPrizeCount,
              remainingPrizeCount: _remainingPrizeCount,
              animationMode: animationMode,
              isDrawing: _isDrawing,
              controlsLocked: _isRoundActive,
              onPoolChanged: _handlePoolChanged,
              onDrawCountChanged: _handleDrawCountChanged,
              onStartDraw: _startDraw,
              onStopDraw: _stopDraw,
              onResetDraw: _resetDraw,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLotteryPortraitLayout() {
    final animationMode = context.watch<AppProvider>().lotteryAnimationMode;

    return Column(
      key: const ValueKey('lottery_layout_portrait'),
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: LotteryResultDisplay(
              records: _displayedRecords,
              isWideScreen: false,
            ),
          ),
        ),
        Container(
          key: _lotteryPortraitPanelKey,
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
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: LotteryControlPanel(
              prizePools: _prizePools,
              selectedPool: _selectedPool,
              drawCount: _drawCount,
              totalPrizeCount: _totalPrizeCount,
              remainingPrizeCount: _remainingPrizeCount,
              animationMode: animationMode,
              isDrawing: _isDrawing,
              controlsLocked: _isRoundActive,
              onPoolChanged: _handlePoolChanged,
              onDrawCountChanged: _handleDrawCountChanged,
              onStartDraw: _startDraw,
              onStopDraw: _stopDraw,
              onResetDraw: _resetDraw,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLotteryShortLayout(double contentHeight) {
    final panelAvailableHeight = contentHeight;
    final animationMode = context.watch<AppProvider>().lotteryAnimationMode;

    return Padding(
      key: const ValueKey('lottery_layout_short'),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: LotteryResultDisplay(
                records: _displayedRecords,
                isWideScreen: true,
              ),
            ),
          ),
          const SizedBox(width: _kPanelGap),
          SizedBox(
            width: _kPanelWidth,
            child: LotteryControlPanel(
              layoutMode: LotteryControlPanelLayoutMode.compact,
              availableHeight: panelAvailableHeight,
              fillHeight: true,
              prizePools: _prizePools,
              selectedPool: _selectedPool,
              drawCount: _drawCount,
              totalPrizeCount: _totalPrizeCount,
              remainingPrizeCount: _remainingPrizeCount,
              animationMode: animationMode,
              isDrawing: _isDrawing,
              controlsLocked: _isRoundActive,
              onPoolChanged: _handlePoolChanged,
              onDrawCountChanged: _handleDrawCountChanged,
              onStartDraw: _startDraw,
              onStopDraw: _stopDraw,
              onResetDraw: _resetDraw,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLotteryContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentSize = Size(constraints.maxWidth, constraints.maxHeight);
        _scheduleLotteryStateMeasurement(contentSize);

        Widget child;
        switch (_lotteryState) {
          case ResponsiveScreenState.large:
            child = _buildLotteryLargeLayout(contentSize.height);
            break;
          case ResponsiveScreenState.portrait:
            child = _buildLotteryPortraitLayout();
            break;
          case ResponsiveScreenState.short:
            child = _buildLotteryShortLayout(contentSize.height);
            break;
          case ResponsiveScreenState.small:
            child = _buildLotteryDrawerLayout();
            break;
        }

        return Container(
          key: _lotteryContentKey,
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Stack(children: [Positioned.fill(child: child)]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: _buildLotteryContent());
  }
}

class LotteryResultDisplay extends StatelessWidget {
  final List<LotteryRecord>? records;
  final bool isWideScreen;

  const LotteryResultDisplay({
    super.key,
    required this.records,
    required this.isWideScreen,
  });

  @override
  Widget build(BuildContext context) {
    final resultFontSize = context.watch<AppProvider>().lotteryResultFontSize;
    final currentFontSize = isWideScreen
        ? resultFontSize
        : resultFontSize * 0.75;

    return Center(
      child: records == null || records!.isEmpty
          ? SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.card_giftcard_outlined,
                    size: 64,
                    color: Theme.of(context).disabledColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '准备抽奖',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Theme.of(context).disabledColor,
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16.0,
                runSpacing: 16.0,
                children: records!.map((record) {
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder:
                        (Widget child, Animation<double> animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.0, 0.2),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                    child: Padding(
                      key: ValueKey<String>("${record.id}-${record.prizeName}"),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24.0,
                        vertical: 12.0,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.card_giftcard,
                            size: isWideScreen ? 48 : 40,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            record.prizeName,
                            style: TextStyle(
                              fontSize: currentFontSize,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyLarge?.color,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (record.studentName != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              record.studentName!,
                              style: TextStyle(
                                fontSize: isWideScreen ? 20 : 16,
                                color: Colors.grey[600],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
    );
  }
}

enum LotteryControlPanelLayoutMode {
  auto,
  autoFit,
  normal,
  compact,
  ultraCompact,
}

class LotteryControlPanel extends StatelessWidget {
  final LotteryControlPanelLayoutMode layoutMode;
  final double? availableHeight;
  final bool fillHeight;
  final List<PrizePool> prizePools;
  final PrizePool? selectedPool;
  final int drawCount;
  final int totalPrizeCount;
  final int remainingPrizeCount;
  final AnimationMode animationMode;
  final bool isDrawing;
  final bool controlsLocked;
  final ValueChanged<PrizePool?> onPoolChanged;
  final ValueChanged<int> onDrawCountChanged;
  final VoidCallback onStartDraw;
  final VoidCallback onStopDraw;
  final VoidCallback onResetDraw;

  static const startButtonKey = ValueKey('lottery_start_button');
  static const resetButtonKey = ValueKey('lottery_reset_button');
  static const decrementDrawCountKey = ValueKey('lottery_draw_count_decrement');
  static const incrementDrawCountKey = ValueKey('lottery_draw_count_increment');
  static const poolDropdownKey = ValueKey('lottery_pool_dropdown');

  const LotteryControlPanel({
    super.key,
    this.layoutMode = LotteryControlPanelLayoutMode.auto,
    this.availableHeight,
    this.fillHeight = false,
    required this.prizePools,
    required this.selectedPool,
    required this.drawCount,
    required this.totalPrizeCount,
    required this.remainingPrizeCount,
    required this.animationMode,
    this.isDrawing = false,
    this.controlsLocked = false,
    required this.onPoolChanged,
    required this.onDrawCountChanged,
    required this.onStartDraw,
    required this.onStopDraw,
    required this.onResetDraw,
  });

  @override
  Widget build(BuildContext context) {
    final viewportHeight =
        availableHeight ?? MediaQuery.of(context).size.height;

    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedMode = _resolveLayoutMode(
          constraints.maxWidth,
          viewportHeight,
        );
        if (resolvedMode == LotteryControlPanelLayoutMode.autoFit) {
          return _AutoFitLotteryControlPanel(
            panel: this,
            availableHeight: viewportHeight,
            fillHeight: fillHeight,
          );
        }
        return _buildCard(context, resolvedMode, fillHeight: fillHeight);
      },
    );
  }

  LotteryControlPanelLayoutMode _resolveLayoutMode(
    double maxWidth,
    double currentHeight,
  ) {
    if (layoutMode == LotteryControlPanelLayoutMode.autoFit) {
      return LotteryControlPanelLayoutMode.autoFit;
    }
    if (layoutMode != LotteryControlPanelLayoutMode.auto) {
      return layoutMode;
    }
    final isCompact = maxWidth < 800;
    if (currentHeight < 400) {
      return LotteryControlPanelLayoutMode.ultraCompact;
    }
    if (isCompact) {
      return LotteryControlPanelLayoutMode.compact;
    }
    return LotteryControlPanelLayoutMode.normal;
  }

  Widget _buildCard(
    BuildContext context,
    LotteryControlPanelLayoutMode resolvedMode, {
    required bool fillHeight,
    Key? measureKey,
  }) {
    final isCompact = resolvedMode != LotteryControlPanelLayoutMode.normal;
    return Card(
      key: measureKey,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isCompact ? 12 : 16),
      ),
      color: Theme.of(context).cardColor,
      child: Container(
        width: isCompact ? null : 280,
        constraints: BoxConstraints(
          minWidth: isCompact ? 0 : 280,
          maxWidth: isCompact ? double.infinity : 320,
        ),
        height: fillHeight ? double.infinity : null,
        padding: EdgeInsets.all(isCompact ? 8.0 : 20.0),
        child: _buildLayout(context, resolvedMode, fillHeight: fillHeight),
      ),
    );
  }

  bool _canManuallyStop() {
    return isDrawing && animationMode == AnimationMode.manualStop;
  }

  String _startButtonLabel() {
    if (_canManuallyStop()) {
      return '停止';
    }
    if (isDrawing) {
      return '抽奖中...';
    }
    return '开始';
  }

  VoidCallback? _startButtonHandler() {
    if (_canManuallyStop()) {
      return onStopDraw;
    }
    if (controlsLocked) {
      return null;
    }
    return onStartDraw;
  }

  Widget _buildLayout(
    BuildContext context,
    LotteryControlPanelLayoutMode resolvedMode, {
    required bool fillHeight,
  }) {
    if (resolvedMode == LotteryControlPanelLayoutMode.ultraCompact) {
      return _buildUltraCompactLayout(context);
    } else if (resolvedMode == LotteryControlPanelLayoutMode.normal) {
      return _buildNormalLayout(context);
    } else {
      return _buildCompactLayout(context, fillHeight: fillHeight);
    }
  }

  Widget _buildNormalLayout(BuildContext context) {
    final maxCount = totalPrizeCount;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton.filledTonal(
              key: decrementDrawCountKey,
              onPressed: !controlsLocked && drawCount > 1
                  ? () => onDrawCountChanged(drawCount - 1)
                  : null,
              icon: const Icon(Icons.remove),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$drawCount',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton.filledTonal(
              key: incrementDrawCountKey,
              onPressed: !controlsLocked && drawCount < maxCount
                  ? () => onDrawCountChanged(drawCount + 1)
                  : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 20),

        SizedBox(
          height: 56,
          child: FilledButton(
            key: startButtonKey,
            onPressed: _startButtonHandler(),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF66CCFF),
              foregroundColor: Colors.white,
              textStyle: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(_startButtonLabel()),
          ),
        ),
        const SizedBox(height: 12),

        OutlinedButton.icon(
          key: resetButtonKey,
          onPressed: controlsLocked ? null : onResetDraw,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('重置'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.grey[600],
            side: BorderSide(color: Colors.grey[400]!),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 20),

        DropdownButtonFormField<PrizePool>(
          key: poolDropdownKey,
          initialValue: selectedPool,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: '奖池',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
          ),
          items: prizePools.map((pool) {
            return DropdownMenuItem(
              value: pool,
              child: Text(pool.name, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: controlsLocked ? null : onPoolChanged,
        ),
        const SizedBox(height: 12),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
          child: Text(
            '剩余: $remainingPrizeCount | 总数: $totalPrizeCount',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactLayout(BuildContext context, {required bool fillHeight}) {
    final maxCount = totalPrizeCount;

    return Column(
      mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: fillHeight
          ? MainAxisAlignment.spaceEvenly
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton.filledTonal(
              key: decrementDrawCountKey,
              onPressed: !controlsLocked && drawCount > 1
                  ? () => onDrawCountChanged(drawCount - 1)
                  : null,
              icon: const Icon(Icons.remove, size: 20),
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$drawCount',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton.filledTonal(
              key: incrementDrawCountKey,
              onPressed: !controlsLocked && drawCount < maxCount
                  ? () => onDrawCountChanged(drawCount + 1)
                  : null,
              icon: const Icon(Icons.add, size: 20),
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
        SizedBox(height: fillHeight ? 0 : 12),

        SizedBox(
          height: 44,
          child: FilledButton(
            key: startButtonKey,
            onPressed: _startButtonHandler(),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF66CCFF),
              foregroundColor: Colors.white,
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(_startButtonLabel()),
          ),
        ),
        SizedBox(height: fillHeight ? 0 : 8),

        OutlinedButton.icon(
          key: resetButtonKey,
          onPressed: controlsLocked ? null : onResetDraw,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('重置'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.grey[600],
            side: BorderSide(color: Colors.grey[400]!),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        SizedBox(height: fillHeight ? 0 : 12),

        DropdownButtonFormField<PrizePool>(
          key: poolDropdownKey,
          initialValue: selectedPool,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: '奖池',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            isDense: true,
          ),
          items: prizePools.map((pool) {
            return DropdownMenuItem(
              value: pool,
              child: Text(pool.name, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: controlsLocked ? null : onPoolChanged,
        ),
        SizedBox(height: fillHeight ? 0 : 8),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.only(top: 6.0, bottom: 4.0),
          child: Text(
            '剩余: $remainingPrizeCount | 总数: $totalPrizeCount',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildUltraCompactLayout(BuildContext context) {
    final maxCount = totalPrizeCount;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton.filledTonal(
                key: decrementDrawCountKey,
                onPressed: !controlsLocked && drawCount > 1
                    ? () => onDrawCountChanged(drawCount - 1)
                    : null,
                icon: const Icon(Icons.remove, size: 18),
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$drawCount',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton.filledTonal(
                key: incrementDrawCountKey,
                onPressed: !controlsLocked && drawCount < maxCount
                    ? () => onDrawCountChanged(drawCount + 1)
                    : null,
                icon: const Icon(Icons.add, size: 18),
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
          const SizedBox(height: 8),

          SizedBox(
            height: 40,
            child: FilledButton(
              key: startButtonKey,
              onPressed: _startButtonHandler(),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF66CCFF),
                foregroundColor: Colors.white,
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: Text(_startButtonLabel()),
            ),
          ),
          const SizedBox(height: 6),

          OutlinedButton.icon(
            key: resetButtonKey,
            onPressed: controlsLocked ? null : onResetDraw,
            icon: const Icon(Icons.refresh, size: 14),
            label: const Text('重置'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey[600],
              side: BorderSide(color: Colors.grey[400]!),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          const SizedBox(height: 8),

          DropdownButtonFormField<PrizePool>(
            key: poolDropdownKey,
            initialValue: selectedPool,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: '奖池',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              isDense: true,
              labelStyle: const TextStyle(fontSize: 11),
            ),
            items: prizePools.map((pool) {
              return DropdownMenuItem(
                value: pool,
                child: Text(
                  pool.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              );
            }).toList(),
            onChanged: controlsLocked ? null : onPoolChanged,
          ),

          const SizedBox(height: 6),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.only(top: 4.0, bottom: 4.0),
            child: Text(
              '剩余: $remainingPrizeCount | 总数: $totalPrizeCount',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey, fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _AutoFitLotteryControlPanel extends StatefulWidget {
  const _AutoFitLotteryControlPanel({
    required this.panel,
    required this.availableHeight,
    required this.fillHeight,
  });

  final LotteryControlPanel panel;
  final double availableHeight;
  final bool fillHeight;

  @override
  State<_AutoFitLotteryControlPanel> createState() =>
      _AutoFitLotteryControlPanelState();
}

class _AutoFitLotteryControlPanelState
    extends State<_AutoFitLotteryControlPanel> {
  final GlobalKey _normalKey = GlobalKey();
  final GlobalKey _compactKey = GlobalKey();
  final GlobalKey _ultraKey = GlobalKey();

  LotteryControlPanelLayoutMode _resolvedMode =
      LotteryControlPanelLayoutMode.normal;
  bool _pendingMeasurement = false;
  double _lastWidth = -1;
  double _lastAvailableHeight = -1;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _scheduleMeasurementIfNeeded(constraints.maxWidth);
        return Stack(
          children: [
            Offstage(
              child: widget.panel._buildCard(
                context,
                LotteryControlPanelLayoutMode.normal,
                fillHeight: false,
                measureKey: _normalKey,
              ),
            ),
            Offstage(
              child: widget.panel._buildCard(
                context,
                LotteryControlPanelLayoutMode.compact,
                fillHeight: false,
                measureKey: _compactKey,
              ),
            ),
            Offstage(
              child: widget.panel._buildCard(
                context,
                LotteryControlPanelLayoutMode.ultraCompact,
                fillHeight: false,
                measureKey: _ultraKey,
              ),
            ),
            widget.panel._buildCard(
              context,
              _resolvedMode,
              fillHeight: widget.fillHeight,
            ),
          ],
        );
      },
    );
  }

  void _scheduleMeasurementIfNeeded(double width) {
    final widthChanged = (width - _lastWidth).abs() > 0.5;
    final heightChanged =
        (widget.availableHeight - _lastAvailableHeight).abs() > 0.5;
    if (_pendingMeasurement || (!widthChanged && !heightChanged)) {
      return;
    }
    _lastWidth = width;
    _lastAvailableHeight = widget.availableHeight;
    _pendingMeasurement = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingMeasurement = false;
      if (!mounted) {
        return;
      }
      final normalHeight = _readHeight(_normalKey);
      final compactHeight = _readHeight(_compactKey);
      final ultraHeight = _readHeight(_ultraKey);
      final nextMode = _selectMode(
        normalHeight,
        compactHeight,
        ultraHeight,
        widget.availableHeight,
      );
      if (nextMode != _resolvedMode) {
        setState(() {
          _resolvedMode = nextMode;
        });
      }
    });
  }

  double _readHeight(GlobalKey key) {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is RenderBox) {
      return renderObject.size.height;
    }
    return double.infinity;
  }

  LotteryControlPanelLayoutMode _selectMode(
    double normalHeight,
    double compactHeight,
    double ultraHeight,
    double availableHeight,
  ) {
    if (normalHeight <= availableHeight) {
      return LotteryControlPanelLayoutMode.normal;
    }
    if (compactHeight <= availableHeight) {
      return LotteryControlPanelLayoutMode.compact;
    }
    if (ultraHeight <= availableHeight) {
      return LotteryControlPanelLayoutMode.ultraCompact;
    }
    return LotteryControlPanelLayoutMode.ultraCompact;
  }
}
