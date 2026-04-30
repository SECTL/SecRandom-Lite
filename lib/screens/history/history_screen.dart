import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../models/student.dart';
import '../../models/history_record.dart';
import '../../models/lottery_record.dart';
import '../../services/lottery_service.dart';
import '../../widgets/history/tab_switcher.dart';
import '../../widgets/history/rollcall_history_card.dart';
import '../../widgets/history/lottery_history_card.dart';
import 'rollcall_history_detail_screen.dart';
import 'lottery_history_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _selectedTab = '点名历史';
  String _selectedClass = '1';
  String? _selectedPool;
  final LotteryService _lotteryService = LotteryService();
  List<LotteryRecord> _lotteryRecords = [];
  bool _isInitialLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    final classNames = appProvider.allStudents.map((s) => s.className).toSet().toList()..sort();
    if (classNames.isNotEmpty && !classNames.contains(_selectedClass)) {
      _selectedClass = classNames.first;
    }

    try {
      final records = await _lotteryService.loadLotteryRecords();
      final poolNames = records.map((r) => r.poolName).toSet().toList()..sort();
      setState(() {
        _lotteryRecords = records;
        if (poolNames.isNotEmpty && _selectedPool == null) {
          _selectedPool = poolNames.first;
        }
        _isInitialLoading = false;
      });
    } catch (e) {
      setState(() {
        _isInitialLoading = false;
      });
    }
  }

  void _onTabChanged(String tab) {
    setState(() {
      _selectedTab = tab;
    });
  }

  void _onClassChanged(String className) {
    setState(() {
      _selectedClass = className;
    });
  }

  void _onPoolChanged(String? poolName) {
    if (poolName != null) {
      setState(() {
        _selectedPool = poolName;
      });
    }
  }

  void _navigateToDetail() {
    if (_selectedTab == '点名历史') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RollcallHistoryDetailScreen(
            initialClass: _selectedClass,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LotteryHistoryDetailScreen(
            initialPool: _lotteryRecords.isNotEmpty
                ? _lotteryRecords.first.poolName
                : null,
          ),
        ),
      );
    }
  }

  Future<void> _refreshData() async {
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitialLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final appProvider = Provider.of<AppProvider>(context);
    final allStudents = appProvider.allStudents;
    final history = appProvider.history;

    final Set<String> classNames = allStudents.map((s) => s.className).toSet();
    final List<String> classOptions = classNames.toList()..sort();

    final filteredStudents = allStudents
        .where((s) => s.className == _selectedClass)
        .toList();
    final filteredHistory = history
        .where((h) => h.className == _selectedClass)
        .toList();

    final studentMap = {for (var s in filteredStudents) s.name: s};

    final sortedHistory = List<HistoryRecord>.from(filteredHistory)
      ..sort((a, b) => b.drawTime.compareTo(a.drawTime));

    final poolNames = _lotteryRecords.map((r) => r.poolName).toSet().toList()..sort();
    final filteredLotteryRecords = _selectedPool != null
        ? _lotteryRecords.where((r) => r.poolName == _selectedPool).toList()
        : _lotteryRecords;
    final sortedLotteryRecords = List<LotteryRecord>.from(filteredLotteryRecords)
      ..sort((a, b) => b.drawTime.compareTo(a.drawTime));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TabSwitcher(
                tabs: const ['点名历史', '抽奖历史'],
                selectedTab: _selectedTab,
                onTabChanged: _onTabChanged,
              ),
            ),
            if (_selectedTab == '点名历史')
              _buildClassSelector(classOptions)
            else if (poolNames.isNotEmpty)
              _buildPoolSelector(poolNames),
            Expanded(
              child: _selectedTab == '点名历史'
                  ? _buildRollcallHistoryList(sortedHistory, studentMap)
                  : _buildLotteryHistoryList(sortedLotteryRecords),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToDetail,
        tooltip: '查看详细记录',
        child: const Icon(Icons.list_alt),
      ),
    );
  }

  Widget _buildClassSelector(List<String> classOptions) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.bookmark_outline, size: 18),
            const SizedBox(width: 8),
            const Text('班级：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: classOptions.contains(_selectedClass) ? _selectedClass : null,
                  isExpanded: true,
                  isDense: true,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
                  dropdownColor: Theme.of(context).cardColor,
                  items: classOptions.map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    if (newValue != null) {
                      _onClassChanged(newValue);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPoolSelector(List<String> poolOptions) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.card_giftcard_outlined, size: 18),
            const SizedBox(width: 8),
            const Text('奖池：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: poolOptions.contains(_selectedPool) ? _selectedPool : null,
                  isExpanded: true,
                  isDense: true,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
                  dropdownColor: Theme.of(context).cardColor,
                  items: poolOptions.map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: _onPoolChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRollcallHistoryList(
    List<HistoryRecord> history,
    Map<String, Student> studentMap,
  ) {
    if (history.isEmpty) {
      return const Center(child: Text('暂无点名历史记录'));
    }

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: history.length,
        itemBuilder: (context, index) {
          final record = history[index];
          return RollcallHistoryCard(
            record: record,
            studentMap: studentMap,
          );
        },
      ),
    );
  }

  Widget _buildLotteryHistoryList(List<LotteryRecord> records) {
    if (records.isEmpty) {
      return const Center(child: Text('暂无抽奖历史记录'));
    }

    final groupedRecords = _groupLotteryRecords(records);

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: groupedRecords.length,
        itemBuilder: (context, index) {
          final group = groupedRecords[index];
          return LotteryHistoryCard(
            drawTime: group.drawTime,
            poolName: group.poolName,
            records: group.records,
          );
        },
      ),
    );
  }

  List<_LotteryRecordGroup> _groupLotteryRecords(List<LotteryRecord> records) {
    final groups = <String, _LotteryRecordGroup>{};

    for (final record in records) {
      final dateKey = '${record.drawTime.year}-${record.drawTime.month}-${record.drawTime.day}-${record.poolName}';
      
      if (!groups.containsKey(dateKey)) {
        groups[dateKey] = _LotteryRecordGroup(
          drawTime: record.drawTime,
          poolName: record.poolName,
          records: [],
        );
      }
      groups[dateKey]!.records.add(record);
    }

    final sortedGroups = groups.values.toList()
      ..sort((a, b) => b.drawTime.compareTo(a.drawTime));

    for (final group in sortedGroups) {
      group.records.sort((a, b) => b.drawTime.compareTo(a.drawTime));
    }

    return sortedGroups;
  }
}

class _LotteryRecordGroup {
  final DateTime drawTime;
  final String poolName;
  final List<LotteryRecord> records;

  _LotteryRecordGroup({
    required this.drawTime,
    required this.poolName,
    required this.records,
  });
}
