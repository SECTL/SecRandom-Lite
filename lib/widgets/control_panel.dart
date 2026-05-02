import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_config.dart';
import '../providers/app_provider.dart';

enum ControlPanelLayoutMode {
  auto,
  autoFit,
  normal,
  compact,
  ultraCompact,
}

class ControlPanel extends StatelessWidget {
  const ControlPanel({
    super.key,
    this.layoutMode = ControlPanelLayoutMode.auto,
    this.availableHeight,
    this.fillHeight = false,
  });

  final ControlPanelLayoutMode layoutMode;
  final double? availableHeight;
  final bool fillHeight;

  static const startButtonKey = ValueKey('rollcall_start_button');
  static const decrementSelectCountKey = ValueKey('rollcall_select_count_decrement');
  static const incrementSelectCountKey = ValueKey('rollcall_select_count_increment');
  static const classDropdownKey = ValueKey('rollcall_class_dropdown');
  static const groupDropdownKey = ValueKey('rollcall_group_dropdown');
  static const genderDropdownKey = ValueKey('rollcall_gender_dropdown');

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);
    final viewportHeight = availableHeight ?? MediaQuery.of(context).size.height;

    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedMode = _resolveLayoutMode(
          constraints.maxWidth,
          viewportHeight,
        );
        if (resolvedMode == ControlPanelLayoutMode.autoFit) {
          return _AutoFitControlPanel(
            panel: this,
            appProvider: appProvider,
            availableHeight: viewportHeight,
            fillHeight: fillHeight,
          );
        }
        return _buildCard(
          context,
          appProvider,
          resolvedMode,
          fillHeight: fillHeight,
        );
      },
    );
  }

  ControlPanelLayoutMode _resolveLayoutMode(double maxWidth, double currentHeight) {
    if (layoutMode == ControlPanelLayoutMode.autoFit) {
      return ControlPanelLayoutMode.autoFit;
    }
    if (layoutMode != ControlPanelLayoutMode.auto) {
      return layoutMode;
    }

    final isCompact = maxWidth < 800;
    final isHeightConstrained = currentHeight < 400;
    if (isHeightConstrained) {
      return ControlPanelLayoutMode.ultraCompact;
    }
    if (isCompact) {
      return ControlPanelLayoutMode.compact;
    }
    return ControlPanelLayoutMode.normal;
  }

  Widget _buildCard(
    BuildContext context,
    AppProvider appProvider,
    ControlPanelLayoutMode resolvedMode, {
    required bool fillHeight,
    Key? measureKey,
  }) {
    final isCompactMode = resolvedMode != ControlPanelLayoutMode.normal;
    final layout = _buildLayoutByMode(
      context,
      appProvider,
      resolvedMode,
      fillHeight: fillHeight,
    );
    return Card(
      key: measureKey,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isCompactMode ? 12 : 16),
      ),
      color: Theme.of(context).cardColor,
      child: Container(
        width: isCompactMode ? null : 280,
        constraints: BoxConstraints(
          minWidth: isCompactMode ? 0 : 280,
          maxWidth: isCompactMode ? double.infinity : 320,
        ),
        height: fillHeight ? double.infinity : null,
        padding: EdgeInsets.all(isCompactMode ? 8 : 20),
        child: layout,
      ),
    );
  }

  Widget _buildLayoutByMode(
    BuildContext context,
    AppProvider appProvider,
    ControlPanelLayoutMode resolvedMode,
    {required bool fillHeight}
  ) {
    switch (resolvedMode) {
      case ControlPanelLayoutMode.normal:
        return _buildNormalLayout(context, appProvider);
      case ControlPanelLayoutMode.compact:
        return _buildCompactLayout(context, appProvider, fillHeight: fillHeight);
      case ControlPanelLayoutMode.ultraCompact:
        return _buildUltraCompactLayout(context, appProvider);
      case ControlPanelLayoutMode.autoFit:
      case ControlPanelLayoutMode.auto:
        return _buildNormalLayout(context, appProvider);
    }
  }

  // 构建班级下拉选项
  List<DropdownMenuItem<String>> _buildClassItems(AppProvider appProvider) {
    final items = <DropdownMenuItem<String>>[];
    for (final className in appProvider.groups) {
      items.add(DropdownMenuItem(value: className, child: Text(className)));
    }
    return items;
  }

  // 构建小组下拉选项
  List<DropdownMenuItem<String>> _buildGroupItems(AppProvider appProvider) {
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: null, child: Text('所有小组')),
    ];
    if (appProvider.selectedClass != null) {
      final groups = appProvider.getGroupsForClass(appProvider.selectedClass);
      for (final group in groups) {
        items.add(DropdownMenuItem(value: group, child: Text(group)));
      }
    } else {
      // 如果没有选择班级，显示所有小组
      final allGroups = <String>{};
      for (final className in appProvider.groups) {
        allGroups.addAll(appProvider.getGroupsForClass(className));
      }
      for (final group in allGroups.toList()..sort()) {
        items.add(DropdownMenuItem(value: group, child: Text(group)));
      }
    }
    return items;
  }

  // 构建性别下拉选项
  List<DropdownMenuItem<String>> _buildGenderItems(AppProvider appProvider) {
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: null, child: Text('所有性别')),
    ];

    // 获取所有学生中出现的性别（包括自定义性别）
    final allGenders = <String>{};
    for (final student in appProvider.allStudents) {
      if (student.gender.isNotEmpty) {
        allGenders.add(student.gender);
      }
    }

    // 按照常见性别排序，自定义性别排在后面
    final commonGenders = ['男', '女', '未知'];
    final customGenders = allGenders
        .where((g) => !commonGenders.contains(g))
        .toList()
      ..sort();

    // 添加常见性别
    for (final gender in commonGenders) {
      if (allGenders.contains(gender)) {
        items.add(DropdownMenuItem(value: gender, child: Text(gender)));
      }
    }

    // 添加自定义性别
    for (final gender in customGenders) {
      items.add(DropdownMenuItem(
        value: gender,
        child: Row(
          children: [
            Text(gender),
            const SizedBox(width: 4),
            const Icon(Icons.person, size: 14, color: Colors.grey),
          ],
        ),
      ));
    }

    return items;
  }

  bool _isRoundActive(AppProvider appProvider) => appProvider.isRolling;

  bool _candidateControlsLocked(AppProvider appProvider) => _isRoundActive(appProvider);

  bool _canManuallyStop(AppProvider appProvider) {
    return _isRoundActive(appProvider) &&
        appProvider.rollcallAnimationMode == AnimationMode.manualStop;
  }

  String _startButtonLabel(AppProvider appProvider) {
    if (_canManuallyStop(appProvider)) {
      return '停止';
    }
    if (_isRoundActive(appProvider)) {
      return '点名中...';
    }
    return '开始';
  }

  VoidCallback? _startButtonHandler(AppProvider appProvider) {
    if (_canManuallyStop(appProvider)) {
      return () {
        appProvider.stopRollCall();
      };
    }
    if (_isRoundActive(appProvider)) {
      return null;
    }
    return () {
      appProvider.startRollCall();
    };
  }

  Widget _buildNormalLayout(BuildContext context, AppProvider appProvider) {
    final maxCount = appProvider.totalCount;
    final controlsLocked = _candidateControlsLocked(appProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 计数器行
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton.filledTonal(
              key: decrementSelectCountKey,
              onPressed: !controlsLocked && appProvider.selectCount > 1
                  ? () => appProvider.setSelectCount(appProvider.selectCount - 1)
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
                '${appProvider.selectCount}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton.filledTonal(
              key: incrementSelectCountKey,
              onPressed: !controlsLocked && appProvider.selectCount < maxCount
                  ? () => appProvider.setSelectCount(appProvider.selectCount + 1)
                  : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // 开始按钮
        SizedBox(
          height: 56,
          child: FilledButton(
            key: startButtonKey,
            onPressed: _startButtonHandler(appProvider),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF66CCFF),
              foregroundColor: Colors.white,
              textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(_startButtonLabel(appProvider)),
          ),
        ),
        const SizedBox(height: 20),

        // 班级下拉菜单
        DropdownButtonFormField<String>(
          key: classDropdownKey,
          initialValue: appProvider.selectedClass,
          decoration: InputDecoration(
            labelText: '班级',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          items: _buildClassItems(appProvider),
          onChanged: controlsLocked
              ? null
              : (value) => appProvider.setSelectedClass(value),
        ),
        const SizedBox(height: 16),

        // 小组筛选
        DropdownButtonFormField<String>(
          key: groupDropdownKey,
          initialValue: appProvider.selectedGroup,
          decoration: InputDecoration(
            labelText: '小组',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          items: _buildGroupItems(appProvider),
          onChanged: controlsLocked
              ? null
              : (value) => appProvider.setSelectedGroup(value),
        ),
        const SizedBox(height: 16),

        // 性别筛选
        DropdownButtonFormField<String>(
          key: genderDropdownKey,
          initialValue: appProvider.selectedGender,
          decoration: InputDecoration(
            labelText: '性别',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          items: _buildGenderItems(appProvider),
          onChanged: controlsLocked
              ? null
              : (value) => appProvider.setSelectedGender(value),
        ),

        // 状态文本
        const SizedBox(height: 20),
        const Divider(),
        Padding(
          padding: const EdgeInsets.only(top: 12.0),
          child: Text(
            '剩余: ${appProvider.remainingCount} | 总数: ${appProvider.totalCount}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactLayout(
    BuildContext context,
    AppProvider appProvider, {
    required bool fillHeight,
  }) {
    final maxCount = appProvider.totalCount;
    final controlsLocked = _candidateControlsLocked(appProvider);

    return Column(
      mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: fillHeight ? MainAxisAlignment.spaceEvenly : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 计数器行
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton.filledTonal(
              key: decrementSelectCountKey,
              onPressed: !controlsLocked && appProvider.selectCount > 1
                  ? () => appProvider.setSelectCount(appProvider.selectCount - 1)
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
                '${appProvider.selectCount}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton.filledTonal(
              key: incrementSelectCountKey,
              onPressed: !controlsLocked && appProvider.selectCount < maxCount
                  ? () => appProvider.setSelectCount(appProvider.selectCount + 1)
                  : null,
              icon: const Icon(Icons.add, size: 20),
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
        SizedBox(height: fillHeight ? 0 : 12),

        // 开始按钮
        SizedBox(
          height: 44,
          child: FilledButton(
            key: startButtonKey,
            onPressed: _startButtonHandler(appProvider),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF66CCFF),
              foregroundColor: Colors.white,
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(_startButtonLabel(appProvider)),
          ),
        ),
        SizedBox(height: fillHeight ? 0 : 12),

        // 班级下拉菜单
        DropdownButtonFormField<String>(
          key: classDropdownKey,
          initialValue: appProvider.selectedClass,
          decoration: InputDecoration(
            labelText: '班级',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            isDense: true,
          ),
          items: _buildClassItems(appProvider).map((item) {
            return DropdownMenuItem<String>(
              value: item.value,
              child: Text(
                (item.child as Text).data!,
                style: const TextStyle(fontSize: 13),
              ),
            );
          }).toList(),
          onChanged: controlsLocked
              ? null
              : (value) => appProvider.setSelectedClass(value),
        ),
        SizedBox(height: fillHeight ? 0 : 12),

        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: groupDropdownKey,
                initialValue: appProvider.selectedGroup,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: '小组',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  isDense: true,
                  labelStyle: const TextStyle(fontSize: 12),
                ),
                items: _buildGroupItems(appProvider).map((item) {
                  return DropdownMenuItem<String>(
                    value: item.value,
                    child: Text(
                      (item.child as Text).data!,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: controlsLocked
                    ? null
                    : (value) => appProvider.setSelectedGroup(value),
              ),
            ),
            const SizedBox(width: 8),

            Expanded(
              child: DropdownButtonFormField<String>(
                key: genderDropdownKey,
                initialValue: appProvider.selectedGender,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: '性别',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  isDense: true,
                  labelStyle: const TextStyle(fontSize: 12),
                ),
                items: _buildGenderItems(appProvider).map((item) {
                  return DropdownMenuItem<String>(
                    value: item.value,
                    child: item.child is Row
                        ? item.child
                        : Text(
                            (item.child as Text).data!,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                  );
                }).toList(),
                onChanged: controlsLocked
                    ? null
                    : (value) => appProvider.setSelectedGender(value),
              ),
            ),
          ],
        ),

        // 状态文本
        SizedBox(height: fillHeight ? 0 : 8),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.only(top: 6.0, bottom: 4.0),
          child: Text(
            '剩余: ${appProvider.remainingCount} | 总数: ${appProvider.totalCount}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildUltraCompactLayout(BuildContext context, AppProvider appProvider) {
    final maxCount = appProvider.totalCount;
    final controlsLocked = _candidateControlsLocked(appProvider);

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 计数器行
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton.filledTonal(
                key: decrementSelectCountKey,
                onPressed: !controlsLocked && appProvider.selectCount > 1
                    ? () => appProvider.setSelectCount(appProvider.selectCount - 1)
                    : null,
                icon: const Icon(Icons.remove, size: 16),
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${appProvider.selectCount}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton.filledTonal(
                key: incrementSelectCountKey,
                onPressed: !controlsLocked && appProvider.selectCount < maxCount
                    ? () => appProvider.setSelectCount(appProvider.selectCount + 1)
                    : null,
                icon: const Icon(Icons.add, size: 16),
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),

          // 开始按钮
          SizedBox(
            height: 32,
            child: FilledButton(
              key: startButtonKey,
              onPressed: _startButtonHandler(appProvider),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF66CCFF),
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              child: Text(_startButtonLabel(appProvider)),
            ),
          ),

          // 班级下拉菜单
          DropdownButtonFormField<String>(
            key: classDropdownKey,
            initialValue: appProvider.selectedClass,
            decoration: InputDecoration(
              labelText: '班级',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              isDense: true,
              labelStyle: const TextStyle(fontSize: 11),
            ),
            items: _buildClassItems(appProvider).map((item) {
              return DropdownMenuItem<String>(
                value: item.value,
                child: Text(
                  (item.child as Text).data!,
                  style: const TextStyle(fontSize: 11),
                ),
              );
            }).toList(),
            onChanged: controlsLocked
                ? null
                : (value) => appProvider.setSelectedClass(value),
          ),

          // 小组和性别选择在同一行
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: groupDropdownKey,
                  initialValue: appProvider.selectedGroup,
                  isExpanded: true,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    isDense: true,
                    labelStyle: const TextStyle(fontSize: 10),
                  ),
                  items: _buildGroupItems(appProvider).map((item) {
                    return DropdownMenuItem<String>(
                      value: item.value,
                      child: Text(
                        (item.child as Text).data!,
                        style: const TextStyle(fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: controlsLocked
                      ? null
                      : (value) => appProvider.setSelectedGroup(value),
                ),
              ),
              const SizedBox(width: 6),

              Expanded(
                child: DropdownButtonFormField<String>(
                  key: genderDropdownKey,
                  initialValue: appProvider.selectedGender,
                  isExpanded: true,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    isDense: true,
                    labelStyle: const TextStyle(fontSize: 10),
                  ),
                  items: _buildGenderItems(appProvider).map((item) {
                    return DropdownMenuItem<String>(
                      value: item.value,
                      child: item.child is Row
                          ? item.child
                          : Text(
                              (item.child as Text).data!,
                              style: const TextStyle(fontSize: 10),
                              overflow: TextOverflow.ellipsis,
                            ),
                    );
                  }).toList(),
                  onChanged: controlsLocked
                      ? null
                      : (value) => appProvider.setSelectedGender(value),
                ),
              ),
            ],
          ),

          // 状态文本
          Text(
            '剩余: ${appProvider.remainingCount} | 总数: ${appProvider.totalCount}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey, fontSize: 10),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _AutoFitControlPanel extends StatefulWidget {
  const _AutoFitControlPanel({
    required this.panel,
    required this.appProvider,
    required this.availableHeight,
    required this.fillHeight,
  });

  final ControlPanel panel;
  final AppProvider appProvider;
  final double availableHeight;
  final bool fillHeight;

  @override
  State<_AutoFitControlPanel> createState() => _AutoFitControlPanelState();
}

class _AutoFitControlPanelState extends State<_AutoFitControlPanel> {
  final GlobalKey _normalKey = GlobalKey();
  final GlobalKey _compactKey = GlobalKey();
  final GlobalKey _ultraKey = GlobalKey();

  ControlPanelLayoutMode _resolvedMode = ControlPanelLayoutMode.normal;
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
                widget.appProvider,
                ControlPanelLayoutMode.normal,
                fillHeight: false,
                measureKey: _normalKey,
              ),
            ),
            Offstage(
              child: widget.panel._buildCard(
                context,
                widget.appProvider,
                ControlPanelLayoutMode.compact,
                fillHeight: false,
                measureKey: _compactKey,
              ),
            ),
            Offstage(
              child: widget.panel._buildCard(
                context,
                widget.appProvider,
                ControlPanelLayoutMode.ultraCompact,
                fillHeight: false,
                measureKey: _ultraKey,
              ),
            ),
            widget.panel._buildCard(
              context,
              widget.appProvider,
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
    final heightChanged = (widget.availableHeight - _lastAvailableHeight).abs() > 0.5;
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
      final nextMode = _selectMode(normalHeight, compactHeight, ultraHeight, widget.availableHeight);
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

  ControlPanelLayoutMode _selectMode(
    double normalHeight,
    double compactHeight,
    double ultraHeight,
    double availableHeight,
  ) {
    if (normalHeight <= availableHeight) {
      return ControlPanelLayoutMode.normal;
    }
    if (compactHeight <= availableHeight) {
      return ControlPanelLayoutMode.compact;
    }
    if (ultraHeight <= availableHeight) {
      return ControlPanelLayoutMode.ultraCompact;
    }
    return ControlPanelLayoutMode.ultraCompact;
  }
}
