class HistoryFilter {
  final String selectedClass;
  final String? selectedStudent;
  final String viewMode;
  final int? sortColumn;
  final bool sortAscending;

  const HistoryFilter({
    this.selectedClass = '1',
    this.selectedStudent,
    this.viewMode = '全部记录',
    this.sortColumn,
    this.sortAscending = true,
  });

  HistoryFilter copyWith({
    String? selectedClass,
    String? selectedStudent,
    String? viewMode,
    int? sortColumn,
    bool? sortAscending,
    bool clearStudent = false,
    bool clearSort = false,
  }) {
    return HistoryFilter(
      selectedClass: selectedClass ?? this.selectedClass,
      selectedStudent: clearStudent ? null : (selectedStudent ?? this.selectedStudent),
      viewMode: viewMode ?? this.viewMode,
      sortColumn: clearSort ? null : (sortColumn ?? this.sortColumn),
      sortAscending: sortAscending ?? this.sortAscending,
    );
  }

  static HistoryFilter defaultFilter() => const HistoryFilter();
}

class LotteryHistoryFilter {
  final String? selectedPool;
  final String viewMode;
  final int? sortColumn;
  final bool sortAscending;

  const LotteryHistoryFilter({
    this.selectedPool,
    this.viewMode = '全部记录',
    this.sortColumn,
    this.sortAscending = true,
  });

  LotteryHistoryFilter copyWith({
    String? selectedPool,
    String? viewMode,
    int? sortColumn,
    bool? sortAscending,
    bool clearPool = false,
    bool clearSort = false,
  }) {
    return LotteryHistoryFilter(
      selectedPool: clearPool ? null : (selectedPool ?? this.selectedPool),
      viewMode: viewMode ?? this.viewMode,
      sortColumn: clearSort ? null : (sortColumn ?? this.sortColumn),
      sortAscending: sortAscending ?? this.sortAscending,
    );
  }

  static LotteryHistoryFilter defaultFilter() => const LotteryHistoryFilter();
}
