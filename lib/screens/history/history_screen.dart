import 'package:flutter/foundation.dart';
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
  bool _isRefreshing = false;

  /// 桌面端没有顺手的手势刷新，改用右下角按钮；移动端保留下滑刷新。
  bool get _isMobilePlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

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
      if (!mounted) return;
      final poolNames = records.map((r) => r.poolName).toSet().toList()..sort();
      setState(() {
        _lotteryRecords = records;
        if (poolNames.isNotEmpty && _selectedPool == null) {
          _selectedPool = poolNames.first;
        }
        _isInitialLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
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
    // 下拉刷新与按钮共用同一入口，避免重复触发并发拉取
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
    });
    try {
      final appProvider = context.read<AppProvider>();
      // 已登录立即拉云端（失败/未登录时内部回退为重载本地记录）
      final result = await appProvider.refreshHistory();
      if (!mounted) return;
      // 刷新本页展示状态：班级/奖池选项与抽奖记录
      await _loadData();
      if (!mounted) return;
      _showRefreshFeedback(appProvider, result);
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  void _showRefreshFeedback(
    AppProvider appProvider,
    HistoryRefreshResult result,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    if (result.errorMessage != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(result.errorMessage!),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    if (result.fromCloud) {
      if (result.newRecords > 0) {
        messenger.showSnackBar(
          SnackBar(content: Text('已从云端同步 ${result.newRecords} 条新记录')),
        );
      }
      return;
    }
    // 未走云端：未登录或云同步关闭，已回退为刷新本地记录
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          appProvider.cloudLoggedIn ? '云同步已关闭，已刷新本地记录' : '未登录，已刷新本地记录',
        ),
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
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
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
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!_isMobilePlatform) ...[
            FloatingActionButton(
              heroTag: 'history_refresh_fab',
              onPressed: _refreshData,
              tooltip: '刷新记录',
              child: _isRefreshing
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
            const SizedBox(height: 12),
          ],
          FloatingActionButton(
            heroTag: 'history_detail_fab',
            onPressed: _navigateToDetail,
            tooltip: '查看详细记录',
            child: const Icon(Icons.list_alt),
          ),
        ],
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
      // 空态也保持可下拉：新设备登录后要能直接拉取云端
      return RefreshIndicator(
        onRefresh: _refreshData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(
              height: 240,
              child: Center(child: Text('暂无点名历史记录，下拉可从云端同步')),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
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
      return RefreshIndicator(
        onRefresh: _refreshData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(
              height: 240,
              child: Center(child: Text('暂无抽奖历史记录，下拉可从云端同步')),
            ),
          ],
        ),
      );
    }

    final groupedRecords = _groupLotteryRecords(records);

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
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
