import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/prize.dart';
import '../models/prize_pool.dart';
import '../models/lottery_record.dart';
import '../providers/app_provider.dart';
import '../services/lottery_service.dart';

class LotteryScreen extends StatefulWidget {
  const LotteryScreen({super.key});

  @override
  State<LotteryScreen> createState() => _LotteryScreenState();
}

class _LotteryScreenState extends State<LotteryScreen> {
  static const double _kPhoneLandscapeAspectRatioMin = 1.55;
  static const double _kPhoneLandscapeMinWidth = 560;
  static const double _kPhoneMaxShortestSide = 500;
  static const double _kPanelWidth = 280;
  static const double _kPanelGap = 24;
  static const double _kNarrowPanelHeight = 300;

  final LotteryService _lotteryService = LotteryService();
  final Random _random = Random.secure();

  Timer? _timer;
  List<LotteryRecord> _displayedRecords = [];

  List<PrizePool> _prizePools = [];
  List<Prize> _prizes = [];

  PrizePool? _selectedPool;

  int _drawCount = 1;

  @override
  void dispose() {
    _timer?.cancel();
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

  void _startDraw() {
    if (_selectedPool == null || _drawCount <= 0) return;

    setState(() {
      _displayedRecords = [];
    });

    _startRollingAnimation();
  }

  void _startRollingAnimation() {
    if (_timer != null && _timer!.isActive) return;

    final pool = _selectedPool!;
    final availablePrizes = _lotteryService.getAvailablePrizes(pool, _prizes);

    if (availablePrizes.isEmpty) {
      return;
    }

    _timer = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final List<LotteryRecord> rollingRecords = [];
      for (int i = 0; i < _drawCount; i++) {
        final randomPrize =
            availablePrizes[_random.nextInt(availablePrizes.length)];
        rollingRecords.add(
          LotteryRecord(
            id: DateTime.now().millisecondsSinceEpoch.toString() + '_$i',
            poolName: pool.name,
            prizeName: randomPrize.name,
            drawTime: DateTime.now(),
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

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _stopRollingAnimation();
        _finalizeDraw();
      }
    });
  }

  void _stopRollingAnimation() {
    _timer?.cancel();
    _timer = null;
  }

  void _finalizeDraw() async {
    if (_selectedPool == null) return;

    try {
      final pool = _selectedPool!;

      final prizes = _lotteryService.drawPrizes(_prizes, _drawCount, pool);
      final records = prizes
          .map(
            (prize) => LotteryRecord(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              poolName: pool.name,
              prizeName: prize.name,
              drawTime: DateTime.now(),
              drawCount: 1,
            ),
          )
          .toList();

      for (var record in records) {
        await _lotteryService.saveLotteryRecord(record);
      }

      if (mounted) {
        setState(() {
          _displayedRecords = records;
        });
      }
    } catch (e) {}
  }

  void _resetDraw() {
    if (_selectedPool == null) return;

    _lotteryService.resetDrawnRecords(_selectedPool!.name);

    if (mounted) {
      setState(() {
        _displayedRecords = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double aspectRatio =
              constraints.maxWidth / constraints.maxHeight;
          final double shortestSide = constraints.biggest.shortestSide;
          final bool isLandscapePhone =
              aspectRatio >= _kPhoneLandscapeAspectRatioMin &&
              constraints.maxWidth >= _kPhoneLandscapeMinWidth &&
              shortestSide <= _kPhoneMaxShortestSide;
          final bool isWideScreen =
              constraints.maxWidth > 800 || isLandscapePhone;
          final double panelAvailableHeight =
              constraints.maxHeight - (_kPanelGap * 2);

          return isWideScreen
              ? Container(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        right: _kPanelWidth + _kPanelGap,
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
                          width: _kPanelWidth,
                          child: LotteryControlPanel(
                            layoutMode: LotteryControlPanelLayoutMode.autoFit,
                            availableHeight: panelAvailableHeight,
                            prizePools: _prizePools,
                            selectedPool: _selectedPool,
                            drawCount: _drawCount,
                            totalPrizeCount: _totalPrizeCount,
                            remainingPrizeCount: _remainingPrizeCount,
                            onPoolChanged: (pool) async {
                              setState(() {
                                _selectedPool = pool;
                                _displayedRecords = [];
                              });
                              await _loadPrizes();
                            },
                            onDrawCountChanged: (count) {
                              setState(() {
                                _drawCount = count;
                              });
                            },
                            onStartDraw: _startDraw,
                            onResetDraw: _resetDraw,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : Container(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  child: Column(
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8.0,
                          vertical: 6.0,
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
                        child: SizedBox(
                          height: _kNarrowPanelHeight,
                          child: LotteryControlPanel(
                            prizePools: _prizePools,
                            selectedPool: _selectedPool,
                            drawCount: _drawCount,
                            totalPrizeCount: _totalPrizeCount,
                            remainingPrizeCount: _remainingPrizeCount,
                            onPoolChanged: (pool) async {
                              setState(() {
                                _selectedPool = pool;
                                _displayedRecords = [];
                              });
                              await _loadPrizes();
                            },
                            onDrawCountChanged: (count) {
                              setState(() {
                                _drawCount = count;
                              });
                            },
                            onStartDraw: _startDraw,
                            onResetDraw: _resetDraw,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
        },
      ),
    );
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
    final currentFontSize = isWideScreen ? resultFontSize : resultFontSize * 0.75;

    return Center(
      child: records == null || records!.isEmpty
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
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
  final ValueChanged<PrizePool?> onPoolChanged;
  final ValueChanged<int> onDrawCountChanged;
  final VoidCallback onStartDraw;
  final VoidCallback onResetDraw;

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
    required this.onPoolChanged,
    required this.onDrawCountChanged,
    required this.onStartDraw,
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
              onPressed: drawCount > 1
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
              onPressed: drawCount < maxCount
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
            onPressed: onStartDraw,
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
            child: const Text('开始'),
          ),
        ),
        const SizedBox(height: 12),

        OutlinedButton.icon(
          onPressed: onResetDraw,
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
          value: selectedPool,
          decoration: InputDecoration(
            labelText: '奖池',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
          ),
          items: prizePools.map((pool) {
            return DropdownMenuItem(value: pool, child: Text(pool.name));
          }).toList(),
          onChanged: onPoolChanged,
        ),
        const SizedBox(height: 16),
        const Divider(),
        Padding(
          padding: const EdgeInsets.only(top: 12.0),
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
              onPressed: drawCount > 1
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
              child: Text('$drawCount', style: Theme.of(context).textTheme.titleLarge),
            ),
            IconButton.filledTonal(
              onPressed: drawCount < maxCount
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
            onPressed: onStartDraw,
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
            child: const Text('开始'),
          ),
        ),
        SizedBox(height: fillHeight ? 0 : 8),

        OutlinedButton.icon(
          onPressed: onResetDraw,
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
          value: selectedPool,
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
            return DropdownMenuItem(value: pool, child: Text(pool.name));
          }).toList(),
          onChanged: onPoolChanged,
        ),
        SizedBox(height: fillHeight ? 0 : 12),
        const Divider(),
        Padding(
          padding: const EdgeInsets.only(top: 6.0),
          child: Text(
            '剩余: $remainingPrizeCount | 总数: $totalPrizeCount',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
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
                onPressed: drawCount > 1
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
                onPressed: drawCount < maxCount
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
              onPressed: onStartDraw,
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
              child: const Text('开始'),
            ),
          ),
          const SizedBox(height: 6),

          OutlinedButton.icon(
            onPressed: onResetDraw,
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
            value: selectedPool,
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
              return DropdownMenuItem(value: pool, child: Text(pool.name));
            }).toList(),
            onChanged: onPoolChanged,
          ),

          const SizedBox(height: 8),
          const Divider(),
          Padding(
            padding: const EdgeInsets.only(top: 6.0),
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
