import 'package:flutter/material.dart';
import '../../models/lottery_record.dart';
import '../../models/history_filter.dart';
import '../../services/lottery_service.dart';
import '../../widgets/history/filter_row.dart';

class LotteryHistoryDetailScreen extends StatefulWidget {
  final String? initialPool;

  const LotteryHistoryDetailScreen({
    super.key,
    this.initialPool,
  });

  @override
  State<LotteryHistoryDetailScreen> createState() => _LotteryHistoryDetailScreenState();
}

class _LotteryHistoryDetailScreenState extends State<LotteryHistoryDetailScreen> {
  late LotteryHistoryFilter _filter;
  final LotteryService _lotteryService = LotteryService();
  List<LotteryRecord> _lotteryRecords = [];
  bool _isInitialLoading = true;

  final int _batchSize = 30;
  int _currentRow = 0;
  int _totalRows = 0;
  bool _isLoading = false;
  bool _hasLoadedAll = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _filter = LotteryHistoryFilter(selectedPool: widget.initialPool);
    _scrollController.addListener(_onScroll);
    _loadLotteryRecords();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLotteryRecords() async {
    try {
      final records = await _lotteryService.loadLotteryRecords();
      setState(() {
        _lotteryRecords = records;
        final poolNames = records.map((r) => r.poolName).toSet().toList()..sort();
        if (poolNames.isNotEmpty &&
            (_filter.selectedPool == null || !poolNames.contains(_filter.selectedPool))) {
          _filter = _filter.copyWith(selectedPool: poolNames.first);
        }
        _isInitialLoading = false;
      });
    } catch (e) {
      setState(() => _isInitialLoading = false);
    }
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

  void _updateFilter(LotteryHistoryFilter newFilter) {
    setState(() {
      _filter = newFilter;
      _resetPagination();
    });
  }

  Future<void> _clearCurrentHistory() async {
    if (_filter.selectedPool == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前没有可清空的奖池历史')),
      );
      return;
    }
    final confirmed = await _showClearConfirmDialog(
      title: '确认清空',
      content: '确定要清空奖池 "${_filter.selectedPool}" 的抽奖历史吗？',
    );
    if (confirmed != true || !mounted) return;
    try {
      await _lotteryService.clearLotteryRecords(poolName: _filter.selectedPool);
      await _loadLotteryRecords();
      if (!mounted) return;
      _resetPagination();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清空当前奖池抽奖历史')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('清空抽奖历史失败')),
      );
    }
  }

  Future<void> _clearAllHistory() async {
    final confirmed = await _showClearConfirmDialog(
      title: '确认清空',
      content: '确定要清空全部抽奖历史吗？此操作无法撤销。',
    );
    if (confirmed != true || !mounted) return;
    try {
      await _lotteryService.clearLotteryRecords();
      await _loadLotteryRecords();
      if (!mounted) return;
      _resetPagination();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清空全部抽奖历史')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('清空抽奖历史失败')),
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
    if (_isInitialLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final poolNames = _lotteryRecords.map((r) => r.poolName).toSet().toList()..sort();
    final filteredRecords = _filter.selectedPool != null
        ? _lotteryRecords.where((r) => r.poolName == _filter.selectedPool).toList()
        : <LotteryRecord>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('抽奖历史详情'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'clearCurrent') {
                _clearCurrentHistory();
              } else if (value == 'clearAll') {
                _clearAllHistory();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'clearCurrent', child: Text('清空当前奖池历史')),
              PopupMenuItem(value: 'clearAll', child: Text('清空全部抽奖历史')),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildFilters(poolNames),
            const SizedBox(height: 16),
            _buildDataTable(filteredRecords),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters(List<String> poolNames) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          FilterRow(
            icon: Icons.card_giftcard_outlined,
            title: '选择奖池',
            subtitle: '选择要查看历史记录的奖池',
            trailing: _buildDropdown(
              value: poolNames.contains(_filter.selectedPool) ? _filter.selectedPool : null,
              hint: '请选择奖池',
              items: poolNames,
              onChanged: (value) {
                _updateFilter(_filter.copyWith(selectedPool: value));
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
              items: const ['全部记录', '按时间查看'],
              onChanged: (value) {
                if (value != null) {
                  _updateFilter(_filter.copyWith(viewMode: value, clearSort: true));
                }
              },
            ),
          ),
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

  Widget _buildDataTable(List<LotteryRecord> records) {
    final headers = _getHeaders();
    final allData = _getTableData(records);
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
      case '按时间查看':
        return ['抽奖时间', '奖品名称', '中奖者'];
      default:
        return ['奖品名称', '中奖次数', '最后中奖时间'];
    }
  }

  bool _canSort(int columnIndex) {
    return _filter.viewMode == '全部记录' && columnIndex < 3;
  }

  List<List<String>> _getTableData(List<LotteryRecord> records) {
    switch (_filter.viewMode) {
      case '按时间查看':
        final sortedRecords = List<LotteryRecord>.from(records)
          ..sort((a, b) => b.drawTime.compareTo(a.drawTime));
        return sortedRecords.map((record) {
          return [
            _formatDateTime(record.drawTime),
            record.prizeName,
            record.studentName ?? '-',
          ];
        }).toList();
      default:
        final poolStats = <String, List<LotteryRecord>>{};
        for (var record in records) {
          poolStats.putIfAbsent(record.prizeName, () => []).add(record);
        }
        final result = <List<String>>[];
        poolStats.forEach((prizeName, prizeRecords) {
          final sortedRecords = List<LotteryRecord>.from(prizeRecords)
            ..sort((a, b) => b.drawTime.compareTo(a.drawTime));
          final lastDrawTime = sortedRecords.first.drawTime;
          result.add([
            prizeName,
            prizeRecords.length.toString(),
            _formatDateTime(lastDrawTime),
          ]);
        });
        return result;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
