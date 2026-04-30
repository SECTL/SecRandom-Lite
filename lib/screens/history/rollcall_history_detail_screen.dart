import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../models/student.dart';
import '../../models/history_record.dart';
import '../../models/history_filter.dart';
import '../../services/fair_weight_service.dart';
import '../../widgets/history/filter_row.dart';

class RollcallHistoryDetailScreen extends StatefulWidget {
  final String initialClass;

  const RollcallHistoryDetailScreen({
    super.key,
    required this.initialClass,
  });

  @override
  State<RollcallHistoryDetailScreen> createState() => _RollcallHistoryDetailScreenState();
}

class _RollcallHistoryDetailScreenState extends State<RollcallHistoryDetailScreen> {
  late HistoryFilter _filter;
  final int _batchSize = 30;
  int _currentRow = 0;
  int _totalRows = 0;
  bool _isLoading = false;
  bool _hasLoadedAll = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _filter = HistoryFilter(selectedClass: widget.initialClass);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isLoading || _hasLoadedAll) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    const delta = 200.0;
    if (maxScroll - currentScroll <= delta) {
      _loadMoreData();
    }
  }

  void _loadMoreData() {
    if (_isLoading || _hasLoadedAll || _currentRow >= _totalRows) return;
    setState(() => _isLoading = true);
    Future.delayed(const Duration(milliseconds: 100), () {
      setState(() {
        final newRow = _currentRow + _batchSize;
        _currentRow = newRow > _totalRows ? _totalRows : newRow;
        _hasLoadedAll = _currentRow >= _totalRows;
        _isLoading = false;
      });
    });
  }

  void _resetPagination() {
    setState(() {
      _currentRow = 0;
      _totalRows = 0;
      _isLoading = false;
      _hasLoadedAll = false;
    });
  }

  void _updateFilter(HistoryFilter newFilter) {
    setState(() {
      _filter = newFilter;
      _resetPagination();
    });
  }

  Future<void> _clearCurrentHistory(AppProvider appProvider) async {
    final confirmed = await _showClearConfirmDialog(
      title: '确认清空',
      content: '确定要清空班级 "${_filter.selectedClass}" 的点名历史吗？',
    );
    if (confirmed != true || !mounted) return;
    try {
      await appProvider.clearHistory(className: _filter.selectedClass);
      if (!mounted) return;
      _resetPagination();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清空当前班级点名历史')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('清空点名历史失败')),
      );
    }
  }

  Future<void> _clearAllHistory(AppProvider appProvider) async {
    final confirmed = await _showClearConfirmDialog(
      title: '确认清空',
      content: '确定要清空全部点名历史吗？此操作无法撤销。',
    );
    if (confirmed != true || !mounted) return;
    try {
      await appProvider.clearHistory();
      if (!mounted) return;
      _resetPagination();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清空全部点名历史')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('清空点名历史失败')),
      );
    }
  }

  Future<bool?> _showClearConfirmDialog({
    required String title,
    required String content,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);
    final allStudents = appProvider.allStudents;
    final history = appProvider.history;

    final Set<String> classNames = allStudents.map((s) => s.className).toSet();
    final List<String> classOptions = classNames.toList()..sort();

    final filteredStudents = allStudents
        .where((s) => s.className == _filter.selectedClass)
        .toList();
    final filteredHistory = history
        .where((h) => h.className == _filter.selectedClass)
        .toList();

    final Map<String, int> callCounts = {};
    for (var record in filteredHistory) {
      final names = record.name.split(',').map((e) => e.trim()).toList();
      for (var name in names) {
        callCounts[name] = (callCounts[name] ?? 0) + 1;
      }
    }

    final currentWeights = appProvider.fairDrawEnabled
        ? FairWeightService().computeCurrentWeights(
            students: filteredStudents,
            history: filteredHistory,
          )
        : const <String, double>{};

    return Scaffold(
      appBar: AppBar(
        title: const Text('点名历史详情'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'clearCurrent') {
                _clearCurrentHistory(appProvider);
              } else if (value == 'clearAll') {
                _clearAllHistory(appProvider);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'clearCurrent', child: Text('清空当前班级历史')),
              PopupMenuItem(value: 'clearAll', child: Text('清空全部点名历史')),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildFilters(classOptions, filteredStudents),
            const SizedBox(height: 16),
            _buildDataTable(
              filteredStudents,
              filteredHistory,
              callCounts,
              currentWeights,
              appProvider.fairDrawEnabled,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters(List<String> classOptions, List<Student> filteredStudents) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          FilterRow(
            icon: Icons.bookmark_outline,
            title: '选择班级',
            subtitle: '选择要查看历史记录的班级',
            trailing: _buildDropdown(
              value: classOptions.contains(_filter.selectedClass)
                  ? _filter.selectedClass
                  : null,
              items: classOptions,
              onChanged: (value) {
                if (value != null) {
                  _updateFilter(_filter.copyWith(
                    selectedClass: value,
                    clearStudent: true,
                  ));
                }
              },
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          FilterRow(
            icon: Icons.description_outlined,
            title: '查看模式',
            subtitle: '选择历史记录的查看方式',
            trailing: _buildDropdown(
              value: _filter.viewMode,
              items: const ['全部记录', '个人记录'],
              onChanged: (value) {
                if (value != null) {
                  _updateFilter(_filter.copyWith(
                    viewMode: value,
                    clearStudent: true,
                    clearSort: true,
                  ));
                }
              },
            ),
          ),
          if (_filter.viewMode == '个人记录') ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            FilterRow(
              icon: Icons.person_outline,
              title: '选择学生',
              subtitle: '选择要查看历史记录的学生',
              trailing: _buildDropdown(
                value: _filter.selectedStudent,
                hint: '请选择学生',
                items: filteredStudents.map((s) => s.name).toList(),
                onChanged: (value) {
                  setState(() {
                    _filter = _filter.copyWith(selectedStudent: value);
                  });
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    String? hint,
  }) {
    return DropdownButtonHideUnderline(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(4),
        ),
        child: DropdownButton<String>(
          value: value,
          hint: hint != null ? Text(hint) : null,
          isDense: true,
          style: Theme.of(context).textTheme.bodyMedium,
          dropdownColor: Theme.of(context).cardColor,
          items: items.map((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildDataTable(
    List<Student> students,
    List<HistoryRecord> history,
    Map<String, int> callCounts,
    Map<String, double> currentWeights,
    bool fairDrawEnabled,
  ) {
    final headers = _getHeaders();
    final allData = _getTableData(
      students,
      history,
      callCounts,
      currentWeights,
      fairDrawEnabled,
    );
    _totalRows = allData.length;
    if (_currentRow == 0 && _totalRows > 0) {
      _currentRow = _totalRows < _batchSize ? _totalRows : _batchSize;
    }
    final displayData = allData.take(_currentRow).toList();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth;
                final isCompact = maxWidth < 600;
                final isVeryCompact = maxWidth < 430;
                final columnSpacing = isVeryCompact ? 8.0 : (isCompact ? 12.0 : 24.0);
                final horizontalMargin = isVeryCompact ? 8.0 : (isCompact ? 12.0 : 24.0);
                final tableFontSize = isVeryCompact ? 11.0 : (isCompact ? 12.0 : null);

                final baseStyle = Theme.of(context).textTheme.bodyMedium;
                final tableTextStyle = baseStyle?.copyWith(fontSize: tableFontSize);

                return DataTable(
                  headingRowColor: WidgetStateProperty.resolveWith((states) {
                    if (Theme.of(context).brightness == Brightness.dark) {
                      return const Color(0xFF303030);
                    }
                    return const Color(0xFFFAFAFA);
                  }),
                  columnSpacing: columnSpacing,
                  horizontalMargin: horizontalMargin,
                  sortColumnIndex: _filter.sortColumn,
                  sortAscending: _filter.sortAscending,
                  columns: headers.asMap().entries.map((entry) {
                    return DataColumn(
                      headingRowAlignment: MainAxisAlignment.center,
                      label: Text(entry.value, style: tableTextStyle),
                      onSort: _canSort(entry.key)
                          ? (columnIndex, ascending) {
                              _updateFilter(_filter.copyWith(
                                sortColumn: columnIndex,
                                sortAscending: ascending,
                              ));
                            }
                          : null,
                    );
                  }).toList(),
                  rows: displayData.map((row) {
                    return DataRow(
                      cells: row.map((cell) {
                        return DataCell(Center(
                          child: Text(cell, style: tableTextStyle),
                        ));
                      }).toList(),
                    );
                  }).toList(),
                );
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_hasLoadedAll && _totalRows > 0)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '已加载全部数据',
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                  fontSize: 12,
                ),
              ),
            ),
          if (displayData.isEmpty && !_isLoading)
            const SizedBox(height: 200, child: Center(child: Text('暂无数据'))),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  List<String> _getHeaders() {
    switch (_filter.viewMode) {
      case '个人记录':
        return ['点名时间', '点名模式', '点名人数', '性别限制', '小组限制'];
      default:
        return ['学号', '姓名', '性别', '小组', '点名次数', '权重'];
    }
  }

  bool _canSort(int columnIndex) {
    return _filter.viewMode == '全部记录' && columnIndex < 4;
  }

  List<List<String>> _getTableData(
    List<Student> students,
    List<HistoryRecord> history,
    Map<String, int> callCounts,
    Map<String, double> currentWeights,
    bool fairDrawEnabled,
  ) {
    switch (_filter.viewMode) {
      case '个人记录':
        if (_filter.selectedStudent == null) return [];
        final studentHistory = history
            .where((h) => h.name.contains(_filter.selectedStudent!))
            .toList()
          ..sort((a, b) => b.drawTime.compareTo(a.drawTime));
        return studentHistory.map((record) {
          return [
            record.drawTime,
            record.drawMethod == 1 ? '单人点名' : '多人点名',
            record.drawPeopleNumbers.toString(),
            record.drawGender,
            record.drawGroup,
          ];
        }).toList();
      default:
        final sortedData = List<Student>.from(students);
        if (_filter.sortColumn != null && _filter.sortColumn! >= 0) {
          sortedData.sort((a, b) {
            int result = 0;
            switch (_filter.sortColumn!) {
              case 0:
                result = a.id.compareTo(b.id);
                break;
              case 1:
                result = a.name.compareTo(b.name);
                break;
              case 2:
                result = a.gender.compareTo(b.gender);
                break;
              case 3:
                result = a.group.compareTo(b.group);
                break;
            }
            return _filter.sortAscending ? result : -result;
          });
        }
        return sortedData.map((student) {
          final count = callCounts[student.name] ?? 0;
          final weight = fairDrawEnabled
              ? (currentWeights[student.name] ?? 1.0).toStringAsFixed(2)
              : '-';
          return [
            student.id.toString(),
            student.name,
            student.gender,
            student.group,
            count.toString(),
            weight,
          ];
        }).toList();
    }
  }
}
