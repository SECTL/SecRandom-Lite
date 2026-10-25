import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_config.dart';
import '../models/draw_stats.dart';
import '../models/history_record.dart';
import '../models/lottery_record.dart';
import '../models/student.dart';
import '../services/auth/token_manager.dart';
import '../services/cloud/cloud_sync_service.dart';
import '../services/cloud/sync_identity.dart';
import '../services/cloud/sync_state.dart';
import '../services/data_service.dart';
import '../services/fair_draw_service.dart';
import '../services/random_service.dart';
import '../utils/logger.dart';

class AppProvider with ChangeNotifier {
  final DataService _dataService = DataService();
  final RandomService _randomService = RandomService();
  final FairDrawService _fairDrawService = FairDrawService();
  final CloudSyncService _cloudSyncService;
  DrawStats _ownRollcallStats = DrawStats();
  DrawStats _ownLotteryStats = DrawStats();
  String? _deviceId;
  DateTime? _lastForegroundSyncAt;
  int _lastPullNewRecords = 0;

  List<Student> _allStudents = [];
  List<Student> _remainingStudents = [];
  List<Student> _currentSelection = [];
  List<HistoryRecord> _history = [];
  List<String> _groups = ['1'];
  Map<String, List<String>> _classGroups = {};
  DrawStats _rollcallStats = DrawStats();
  DrawStats _lotteryStats = DrawStats();

  bool _isRolling = false;
  bool _isDisposed = false;
  bool _isFinalizingRollCall = false;
  ThemeMode _themeMode = ThemeMode.system;
  AnimationMode _rollcallAnimationMode = AnimationMode.auto;
  AnimationMode _lotteryAnimationMode = AnimationMode.auto;
  int _rollCallSessionId = 0;
  Future<void> _pendingConfigSave = Future<void>.value();

  // 云同步防抖
  bool _cloudDirty = false;
  bool _cloudSyncEnabled = true;
  bool _isLoggedIn = false;
  // 覆盖进行中：期间禁止并发的推送/拉取/回前台同步，避免把"半覆盖"状态推上云
  bool _overwriteInProgress = false;
  Timer? _cloudDebounceTimer;
  static const Duration _cloudDebounceDelay = Duration(seconds: 5);
  static const String _kAutoSyncPrefKey = 'cloud_auto_sync_enabled';

  int _selectCount = 1;
  bool _fairDrawEnabled = true;
  bool _nonRepeatEnabled = true;
  double _rollcallResultFontSize = 48;
  double _lotteryResultFontSize = 48;
  String? _selectedClass;
  String? _selectedGroup;
  String? _selectedGender;

  List<Student> get allStudents => _allStudents;
  List<Student> get currentSelection => _currentSelection;
  bool get isRolling => _isRolling;
  ThemeMode get themeMode => _themeMode;
  AnimationMode get rollcallAnimationMode => _rollcallAnimationMode;
  AnimationMode get lotteryAnimationMode => _lotteryAnimationMode;
  int get selectCount => _selectCount;
  int get remainingCount => _remainingStudents.length;
  int get totalCount => _filteredStudents().length;
  bool get fairDrawEnabled => _fairDrawEnabled;
  bool get nonRepeatEnabled => _nonRepeatEnabled;
  double get rollcallResultFontSize => _rollcallResultFontSize;
  double get lotteryResultFontSize => _lotteryResultFontSize;
  String? get selectedClass => _selectedClass;
  String? get selectedGroup => _selectedGroup;
  String? get selectedGender => _selectedGender;
  List<HistoryRecord> get history => _history;
  List<Student> get filteredStudents => _filteredStudents();
  List<String> get groups => _groups;
  DrawStats get rollcallStats => _rollcallStats;
  DrawStats get lotteryStats => _lotteryStats;
  CloudSyncService get cloudSyncService => _cloudSyncService;
  bool get cloudLoggedIn => _isLoggedIn;

  AppProvider({CloudSyncService? cloudSyncService})
      : _cloudSyncService = cloudSyncService ?? CloudSyncService() {
    _loadData();
  }

  /// 重新加载所有数据（用于导入后刷新）
  Future<void> reloadData() async {
    await _loadData();
  }

  Future<void> _loadData() async {
    _cloudSyncEnabled =
        (await SharedPreferences.getInstance()).getBool(_kAutoSyncPrefKey) ??
            true;
    _allStudents = await _dataService.loadStudents();
    _history = await _dataService.loadHistory();
    _deviceId = null;
    try {
      _deviceId = await TokenManager().getOrCreateDeviceUuid();
    } catch (_) {
      // 测试环境/无安全存储时降级；云操作仍需登录后才可用
    }
    final syncState = await _cloudSyncService.loadState();
    _ownRollcallStats = DrawStats(syncState.ownRollcallStats);
    _ownLotteryStats = DrawStats(syncState.ownLotteryStats);
    _rollcallStats = DrawStats(syncState.ownRollcallStats);
    _lotteryStats = DrawStats(syncState.ownLotteryStats);
    await _migrateLegacySyncData(syncState);

    final config = await _dataService.loadConfig();
    _themeMode = _parseThemeMode(config.themeMode);
    _selectCount = 1;
    _fairDrawEnabled = config.fairDrawEnabled;
    _nonRepeatEnabled = config.nonRepeatEnabled;
    _rollcallResultFontSize = config.rollcallResultFontSize;
    _lotteryResultFontSize = config.lotteryResultFontSize;
    _rollcallAnimationMode = config.rollcallAnimationMode;
    _lotteryAnimationMode = config.lotteryAnimationMode;
    _selectedClass = config.selectedClass;

    final jsonClassNames = await _dataService.loadClassNames();
    final configGroups = config.groups.toSet();
    final studentGroups = _allStudents.map((s) => s.className).toSet();
    _groups = {...configGroups, ...jsonClassNames, ...studentGroups}.toList()
      ..sort();
    if (_groups.isEmpty) {
      _groups = ['1'];
    }

    _classGroups = Map<String, List<String>>.from(config.classGroups);

    if (_selectedClass != null && !_groups.contains(_selectedClass)) {
      _selectedClass = _groups.first;
    }
    if (_selectedClass == null && _groups.isNotEmpty) {
      _selectedClass = _groups.first;
    }

    _resetRemaining();
    // _loadData() 是构造函数里 fire-and-forget 启动的，没有任何调用方 await
    // 它，因此它可能一直跑到 dispose 之后。这里必须走带防护的通知，否则会
    // 在 ChangeNotifier 已销毁后调用 notifyListeners。
    _notifyIfActive();
  }

  ThemeMode _parseThemeMode(String mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  Future<void> _saveConfig() async {
    final config = AppConfig(
      themeMode: _themeModeToString(_themeMode),
      selectCount: _selectCount,
      selectedClass: _selectedClass,
      groups: _groups,
      classGroups: _classGroups,
      fairDrawEnabled: _fairDrawEnabled,
      nonRepeatEnabled: _nonRepeatEnabled,
      rollcallResultFontSize: _rollcallResultFontSize,
      lotteryResultFontSize: _lotteryResultFontSize,
      rollcallAnimationMode: _rollcallAnimationMode,
      lotteryAnimationMode: _lotteryAnimationMode,
    );

    _pendingConfigSave = _pendingConfigSave.catchError((_) {}).then(
      (_) => _dataService.saveConfig(config),
    );

    await _pendingConfigSave;
  }

  Future<void> waitForPendingConfigSave() => _pendingConfigSave;

  void _notifyIfActive() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  List<String> getGroupsForClass(String? className) {
    if (className == null) return [];
    final dynamicGroups =
        _allStudents
            .where((s) => s.className == className)
            .map((s) => s.group.trim().isEmpty ? '1' : s.group)
            .toSet()
            .toList()
          ..sort();
    return dynamicGroups;
  }

  Future<void> addGroupToClass(String className, String groupName) async {
    if (className.isEmpty || groupName.isEmpty) return;
    if (!_classGroups.containsKey(className)) {
      _classGroups[className] = [];
    }
    if (!_classGroups[className]!.contains(groupName)) {
      _classGroups[className]!.add(groupName);
      _classGroups[className]!.sort();
      await _saveConfig();
      notifyListeners();
    }
  }

  Future<void> renameGroupInClass(
    String className,
    String oldName,
    String newName,
  ) async {
    if (className.isEmpty || newName.isEmpty || oldName == newName) return;

    final groups = _classGroups[className] ?? [];
    if (!groups.contains(oldName)) return;

    if (!groups.contains(newName)) {
      groups.add(newName);
      groups.sort();
    }
    groups.remove(oldName);
    _classGroups[className] = groups;

    bool changed = false;
    final updated = <Student>[];
    for (final s in _allStudents) {
      if (s.className == className && s.group == oldName) {
        updated.add(
          Student(
            id: s.id,
            name: s.name,
            gender: s.gender,
            group: newName,
            className: s.className,
            exist: s.exist,
          ),
        );
        changed = true;
      } else {
        updated.add(s);
      }
    }

    if (changed) {
      _allStudents = updated;
      await _dataService.saveStudents(_allStudents);
      _markCloudDirty();
      _resetRemaining();
    }
    await _saveConfig();
    notifyListeners();
  }

  Future<void> deleteGroupFromClass(String className, String groupName) async {
    if (className.isEmpty || groupName.isEmpty) return;
    final groups = _classGroups[className] ?? [];
    if (!groups.contains(groupName)) return;

    groups.remove(groupName);
    _classGroups[className] = groups;

    bool changed = false;
    final updated = <Student>[];
    for (final s in _allStudents) {
      if (s.className == className && s.group == groupName) {
        updated.add(
          Student(
            id: s.id,
            name: s.name,
            gender: s.gender,
            group: '1',
            className: s.className,
            exist: s.exist,
          ),
        );
        changed = true;
      } else {
        updated.add(s);
      }
    }

    if (changed) {
      _allStudents = updated;
      await _dataService.saveStudents(_allStudents);
      _markCloudDirty();
      _resetRemaining();
    }
    await _saveConfig();
    notifyListeners();
  }

  Future<void> addClass(String className) async {
    final normalized = className.trim();
    if (normalized.isEmpty) return;
    if (_groups.contains(normalized)) return;

    _groups.add(normalized);
    _groups.sort();
    if (!_classGroups.containsKey(normalized)) {
      _classGroups[normalized] = ['1'];
    }
    await _saveConfig();
    notifyListeners();
  }

  Future<void> renameClass(String oldName, String newName) async {
    final normalized = newName.trim();
    if (oldName.isEmpty || normalized.isEmpty || oldName == normalized) return;
    if (!_groups.contains(oldName)) return;
    if (_groups.contains(normalized)) return;

    _groups.add(normalized);
    _groups.remove(oldName);
    _groups.sort();

    bool changed = false;
    final updated = <Student>[];
    for (final s in _allStudents) {
      if (s.className == oldName) {
        updated.add(
          Student(
            id: s.id,
            name: s.name,
            gender: s.gender,
            group: s.group,
            className: normalized,
            exist: s.exist,
          ),
        );
        changed = true;
      } else {
        updated.add(s);
      }
    }

    if (_classGroups.containsKey(oldName)) {
      _classGroups[normalized] = _classGroups[oldName]!;
      _classGroups.remove(oldName);
    }

    if (changed) {
      _allStudents = updated;
      await _dataService.saveStudents(_allStudents);
      _markCloudDirty();
      _resetRemaining();
    }

    if (_selectedClass == oldName) {
      _selectedClass = normalized;
    }

    await _saveConfig();
    notifyListeners();
  }

  Future<void> deleteClass(String className) async {
    if (!_groups.contains(className)) return;

    _groups.remove(className);

    _allStudents.removeWhere((s) => s.className == className);
    await _dataService.saveStudents(_allStudents);
    _markCloudDirty();
    _resetRemaining();

    _classGroups.remove(className);

    if (_selectedClass == className) {
      _selectedClass = _groups.isNotEmpty ? _groups.first : null;
      _selectedGroup = null;
      _selectedGender = null;
    }

    await _saveConfig();
    notifyListeners();
  }

  void _resetRemaining() {
    _remainingStudents = List.from(_filteredStudents());
  }

  /// 应用云端拉取到的学生名单
  ///
  /// 新设备首次登录时本地只有占位班级 "1"，必须按拉取到的名单重建班级列表，
  /// 否则点名/抽奖页面仍按 "1" 筛选，看起来像名单没刷新。
  Future<void> _applyPulledStudents() async {
    _selectedGroup = null;
    _selectedGender = null;

    final studentClasses = _allStudents.map((s) => s.className).toSet();
    if (studentClasses.isNotEmpty) {
      _groups = studentClasses.toList()..sort();
    } else if (_groups.isEmpty) {
      _groups = ['1'];
    }

    if (!_classHasStudents(_selectedClass)) {
      _selectedClass = _pickDefaultClass();
    }

    _resetRemaining();
    await _saveConfig();
  }

  bool _classHasStudents(String? className) {
    if (className == null) return false;
    return _allStudents.any((s) => s.exist && s.className == className);
  }

  /// 优先返回有学生的班级，没有则退回首个班级
  String? _pickDefaultClass() {
    if (_groups.isEmpty) return null;
    for (final className in _groups) {
      if (_classHasStudents(className)) return className;
    }
    return _groups.first;
  }

  List<Student> _filteredStudents() {
    var filtered = _allStudents.where((s) => s.exist).toList();

    if (_selectedClass != null && _selectedClass != 'All') {
      filtered = filtered.where((s) => s.className == _selectedClass).toList();
    }
    if (_selectedGroup != null && _selectedGroup != 'All') {
      filtered = filtered.where((s) => s.group == _selectedGroup).toList();
    }
    if (_selectedGender != null && _selectedGender != 'All') {
      filtered = filtered.where((s) => s.gender == _selectedGender).toList();
    }

    return filtered;
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _saveConfig();
    notifyListeners();
  }

  void setSelectCount(int count) {
    if (count < 1) count = 1;
    final maxCount = _filteredStudents().length;
    if (maxCount > 0 && count > maxCount) count = maxCount;
    _selectCount = count;
    _saveConfig();
    notifyListeners();
  }

  void setFairDrawEnabled(bool enabled) {
    _fairDrawEnabled = enabled;
    _saveConfig();
    notifyListeners();
  }

  void setNonRepeatEnabled(bool enabled) {
    _nonRepeatEnabled = enabled;
    _resetRemaining();
    _saveConfig();
    notifyListeners();
  }

  void setRollcallResultFontSize(double value) {
    _rollcallResultFontSize = value.clamp(24.0, 72.0).toDouble();
    _saveConfig();
    notifyListeners();
  }

  void setLotteryResultFontSize(double value) {
    _lotteryResultFontSize = value.clamp(24.0, 72.0).toDouble();
    _saveConfig();
    notifyListeners();
  }

  void setRollcallAnimationMode(AnimationMode mode) {
    _rollcallAnimationMode = mode;
    _saveConfig();
    notifyListeners();
  }

  void setLotteryAnimationMode(AnimationMode mode) {
    _lotteryAnimationMode = mode;
    _saveConfig();
    notifyListeners();
  }

  void setSelectedClass(String? className) {
    _selectedClass = className;
    _selectedGroup = null;
    _selectedGender = null;
    _resetRemaining();
    _saveConfig();
    notifyListeners();
  }

  void setSelectedGroup(String? groupName) {
    _selectedGroup = groupName;
    _resetRemaining();
    notifyListeners();
  }

  void setSelectedGender(String? gender) {
    _selectedGender = gender;
    _resetRemaining();
    notifyListeners();
  }

  Future<void> addStudentToClass(
    String className, {
    required String name,
    required String gender,
    required String group,
    bool exist = true,
  }) async {
    final normalizedClass = className.trim();
    final normalizedName = name.trim();
    final normalizedGroup = group.trim().isEmpty ? '1' : group.trim();

    if (normalizedClass.isEmpty || normalizedName.isEmpty) return;

    if (!_groups.contains(normalizedClass)) {
      _groups.add(normalizedClass);
      _groups.sort();
    }

    int newId = 1;
    final classStudents = _allStudents
        .where((s) => s.className == normalizedClass)
        .toList();
    if (classStudents.isNotEmpty) {
      newId =
          classStudents.map((s) => s.id).reduce((a, b) => a > b ? a : b) + 1;
    }

    _allStudents.add(
      Student(
        id: newId,
        name: normalizedName,
        gender: gender,
        group: normalizedGroup,
        className: normalizedClass,
        exist: exist,
      ),
    );

    await _dataService.saveStudents(_allStudents);
    _markCloudDirty();
    _resetRemaining();
    await _saveConfig();
    notifyListeners();
  }

  Future<void> updateStudentInClass(
    String className,
    int id, {
    String? name,
    String? gender,
    String? group,
    bool? exist,
  }) async {
    final index = _allStudents.indexWhere(
      (s) => s.className == className && s.id == id,
    );
    if (index < 0) return;

    final old = _allStudents[index];
    final nextName = (name ?? old.name).trim();
    if (nextName.isEmpty) return;
    final nextGroup = (group ?? old.group).trim().isEmpty
        ? '1'
        : (group ?? old.group).trim();

    _allStudents[index] = Student(
      id: old.id,
      name: nextName,
      gender: gender ?? old.gender,
      group: nextGroup,
      className: old.className,
      exist: exist ?? old.exist,
    );

    await _dataService.saveStudents(_allStudents);
    _markCloudDirty();
    _resetRemaining();
    notifyListeners();
  }

  Future<void> deleteStudentFromClass(String className, int id) async {
    _allStudents.removeWhere((s) => s.className == className && s.id == id);
    await _dataService.saveStudents(_allStudents);
    _markCloudDirty();
    _resetRemaining();
    notifyListeners();
  }

  Future<void> setStudentExistInClass(
    String className,
    int id,
    bool exist,
  ) async {
    await updateStudentInClass(className, id, exist: exist);
  }

  Future<void> addStudent(
    String name,
    String gender,
    String group,
    String className,
  ) async {
    await addStudentToClass(
      className,
      name: name,
      gender: gender,
      group: group,
      exist: true,
    );
  }

  Future<void> updateStudentName(int id, String newName) async {
    if (_selectedClass == null) return;
    await updateStudentInClass(_selectedClass!, id, name: newName);
  }

  Future<void> updateStudentGroup(int id, String newGroup) async {
    if (_selectedClass == null) return;
    await updateStudentInClass(_selectedClass!, id, group: newGroup);
  }

  Future<void> updateStudentGender(int id, String newGender) async {
    if (_selectedClass == null) return;
    await updateStudentInClass(_selectedClass!, id, gender: newGender);
  }

  Future<void> deleteStudent(int id) async {
    if (_selectedClass == null) return;
    await deleteStudentFromClass(_selectedClass!, id);
  }

  Future<BatchImportResult> batchImportStudents(
    String className, {
    required List<String> names,
    required List<String> genders,
    required List<String> groups,
    bool exist = true,
    int batchSize = 100,
    Function(int current, int total)? onProgress,
  }) async {
    final normalizedClass = className.trim();
    if (normalizedClass.isEmpty) {
      return BatchImportResult(successCount: 0, failCount: names.length);
    }

    if (!_groups.contains(normalizedClass)) {
      _groups.add(normalizedClass);
      _groups.sort();
    }

    int successCount = 0;
    int failCount = 0;
    int newId = 1;
    final classStudents = _allStudents
        .where((s) => s.className == normalizedClass)
        .toList();
    if (classStudents.isNotEmpty) {
      newId = classStudents.map((s) => s.id).reduce((a, b) => a > b ? a : b) + 1;
    }

    final totalStudents = names.length;
    final isLargeBatch = totalStudents > 1000;

    for (int i = 0; i < names.length; i++) {
      final name = names[i].trim();
      if (name.isEmpty) {
        failCount++;
        continue;
      }

      String gender = '未知';
      if (i < genders.length) {
        final g = genders[i].trim();
        if (g == '男' || g == '女') {
          gender = g;
        }
      }

      String group = '1';
      if (i < groups.length) {
        final grp = groups[i].trim();
        if (grp.isNotEmpty) {
          group = grp;
        }
      }

      _allStudents.add(
        Student(
          id: newId,
          name: name,
          gender: gender,
          group: group,
          className: normalizedClass,
          exist: exist,
        ),
      );
      newId++;
      successCount++;

      if (isLargeBatch && i % batchSize == 0 && onProgress != null) {
        onProgress(i + 1, totalStudents);
        await Future.delayed(Duration.zero);
      }
    }

    await _dataService.saveStudents(_allStudents);
    _markCloudDirty();
    _resetRemaining();
    await _saveConfig();
    notifyListeners();

    return BatchImportResult(successCount: successCount, failCount: failCount);
  }

  Future<void> clearHistory({String? className}) async {
    if (className != null) {
      _history = _history.where((record) => record.className != className).toList();
    } else {
      _history = [];
      await _cloudSyncService.markCleared('rollcall', DateTime.now());
    }
    await _dataService.clearHistoryRecords(className: className);
    _markCloudDirty();
    notifyListeners();
  }

  Future<void> startRollCall() async {
    if (_isRolling) return;

    _rollCallSessionId++;
    final sessionId = _rollCallSessionId;
    _isRolling = true;
    _notifyIfActive();

    if (_rollcallAnimationMode == AnimationMode.none) {
      await finalizeRollCall(sessionId: sessionId);
      return;
    }

    if (_rollcallAnimationMode == AnimationMode.manualStop) {
      return;
    }

    await Future.delayed(const Duration(seconds: 1));
    if (_isDisposed || sessionId != _rollCallSessionId) {
      return;
    }

    await stopRollCall();
  }

  Future<void> stopRollCall() async {
    if (!_isRolling || _isFinalizingRollCall) return;
    await finalizeRollCall(sessionId: _rollCallSessionId);
  }

  Future<void> finalizeRollCall({int? sessionId}) async {
    final activeSessionId = sessionId ?? _rollCallSessionId;
    if (!_isRolling || _isFinalizingRollCall || activeSessionId != _rollCallSessionId) {
      return;
    }

    _isFinalizingRollCall = true;

    try {
      if (_nonRepeatEnabled && _remainingStudents.length < _selectCount) {
        _resetRemaining();
      }

      final className = _selectedClass ?? '1';
      final picked = _pickRollCallStudents(className);
      _currentSelection = picked;

      if (_nonRepeatEnabled) {
        for (final student in picked) {
          _remainingStudents.removeWhere((remaining) => remaining.id == student.id);
        }
      }

      final record = await _buildRollCallRecord(className, picked);
      _history.insert(0, record);

      // 更新本机贡献与合并视图
      for (final student in picked) {
        _ownRollcallStats.increment(student.name);
        _rollcallStats.increment(student.name);
      }
      await _persistOwnStats();

      await _dataService.addHistoryRecord(record);
      await _cloudSyncService.enqueueRecord('rollcall', record.toJson());

      // 标记云端待推送（防抖统一冲洗 outbox）
      _markCloudDirty();
    } finally {
      if (activeSessionId == _rollCallSessionId) {
        _isRolling = false;
      }
      _isFinalizingRollCall = false;
      _notifyIfActive();
    }
  }

  List<Student> _pickRollCallStudents(String className) {
    final drawCandidates = _nonRepeatEnabled
        ? _remainingStudents
        : _filteredStudents();

    List<Student> picked;
    if (_fairDrawEnabled) {
      picked = _fairDrawService.draw(
        candidates: drawCandidates,
        stats: _rollcallStats,
        count: _selectCount,
      );
      if (picked.isEmpty) {
        picked = _randomService.pickRandomStudents(
          drawCandidates,
          _selectCount,
        );
      }
    } else {
      picked = _randomService.pickRandomStudents(
        drawCandidates,
        _selectCount,
      );
    }
    return picked;
  }

  Future<HistoryRecord> _buildRollCallRecord(String className, List<Student> picked) async {
    final now = DateTime.now();
    final timeStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} "
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

    final newId = _history.isEmpty ? 1 : (_history.first.id + 1);
    final seq = await _cloudSyncService.nextSeq('rollcall');
    final nameStr = picked.map((student) => student.name).join(',');

    return HistoryRecord(
      id: newId,
      uid: newRecordUid(_deviceId ?? 'unknown', seq),
      name: nameStr,
      drawMethod: _fairDrawEnabled ? 2 : 1,
      drawTime: timeStr,
      drawPeopleNumbers: picked.length,
      drawGroup: _selectedGroup ?? '所有小组',
      drawGender: _selectedGender ?? '所有性别',
      className: className,
    );
  }

  // ── 云同步 ──────────────────────────────────────────────

  bool get cloudSyncEnabled => _cloudSyncEnabled;

  /// 登录态下发（由 main.dart 监听 AuthProvider 转发）
  ///
  /// false→true：执行一次 pull-merge + push 初始同步；
  /// true→false：取消防抖与重试，保留脏标记。
  void setAuthState(bool loggedIn) {
    if (loggedIn == _isLoggedIn) return;
    _isLoggedIn = loggedIn;
    if (loggedIn) {
      unawaited(_initialSyncAfterLogin());
    } else {
      _cloudDebounceTimer?.cancel();
      _cloudSyncService.cancelRetries();
    }
    _notifyIfActive();
  }

  bool get _canSync => !_isDisposed && _cloudSyncEnabled && _isLoggedIn;

  /// 旧记录补 uid；首次上线时把既有本地历史一次性加入 outbox
  Future<void> _migrateLegacySyncData(LocalSyncState syncState) async {
    var changed = false;
    final history = _history;
    for (var i = 0; i < history.length; i++) {
      if (history[i].uid == null) {
        history[i] = history[i].copyWithUid(deriveLegacyHistoryUid(history[i]));
        changed = true;
      }
    }
    if (changed) await _dataService.saveHistory(history);

    final lottery = await _dataService.loadLotteryRecords();
    var lotteryChanged = false;
    for (var i = 0; i < lottery.length; i++) {
      if (lottery[i].uid == null) {
        lottery[i] = lottery[i].copyWithUid(deriveLegacyLotteryUid(lottery[i]));
        lotteryChanged = true;
      }
    }
    if (lotteryChanged) {
      await _dataService.saveLotteryRecords(lottery);
    }

    if (!syncState.legacyUploaded) {
      if (syncState.ownRollcallStats.isEmpty && history.isNotEmpty) {
        _ownRollcallStats = DrawStats.fromHistoryNames(history.map((r) => r.name));
        _rollcallStats = DrawStats(_ownRollcallStats.toMap());
        syncState.ownRollcallStats
          ..clear()
          ..addAll(_ownRollcallStats.toMap());
      }
      if (syncState.ownLotteryStats.isEmpty && lottery.isNotEmpty) {
        _ownLotteryStats = DrawStats.fromLotteryRecords(lottery);
        _lotteryStats = DrawStats(_ownLotteryStats.toMap());
        syncState.ownLotteryStats
          ..clear()
          ..addAll(_ownLotteryStats.toMap());
      }
      await _cloudSyncService.enqueueAll('rollcall', history.map((r) => r.toJson()));
      await _cloudSyncService.enqueueAll('lottery', lottery.map((r) => r.toJson()));
      syncState.legacyUploaded = true;
      await _cloudSyncService.saveState();
    }
  }

  Future<void> _initialSyncAfterLogin() async {
    if (!_cloudSyncEnabled || _isDisposed) return;

    bool cloudHasData;
    try {
      cloudHasData = await _cloudSyncService.cloudHasAnyData();
    } catch (e) {
      // 无法判断云端状态（网络/鉴权异常）：既不覆盖本地也不上传，留待下次同步
      logger.w('登录初始同步：检查云端数据失败，本次跳过', error: e);
      return;
    }
    if (_isDisposed) return;

    final localHistory = await _dataService.loadHistory();
    final localLottery = await _dataService.loadLotteryRecords();
    final syncState = await _cloudSyncService.loadState();
    final outbox = await _cloudSyncService.loadOutbox();
    if (_isDisposed || !_isLoggedIn) return;
    final hasBaseline = _hasLocalDataBaseline(
      syncState,
      localHistory,
      localLottery,
      outbox,
    );

    if (!cloudHasData) {
      // 云端为空：本地是唯一数据源，把完整本地历史补传。
      await _enqueueAllLocalHistory(localHistory, localLottery);
      await _pushAfterInitialSync();
      return;
    }

    if (!hasBaseline) {
      // 新设备首次登录：云端快照作为本地数据基线，此时才严格覆盖。
      await _initializeLocalBaselineFromCloud();
      return;
    }

    // 已有本地基线：本地与云端按 uid 并集合并，本地独有记录补传。
    final merged = await _mergeLocalWithCloudSnapshot();
    if (merged) {
      await _pushAfterInitialSync();
    }
  }

  /// 本地是否已经有一份数据基线。
  ///
  /// 只有完全没有本地历史、outbox 与同步状态的新设备，才允许用云端快照
  /// 严格覆盖本地；否则必须走并集合并，避免丢掉本地独有记录。
  bool _hasLocalDataBaseline(
    LocalSyncState state,
    List<HistoryRecord> history,
    List<LotteryRecord> lottery,
    SyncOutbox outbox,
  ) {
    if (history.isNotEmpty || lottery.isNotEmpty) return true;
    if (outbox.rollcall.isNotEmpty || outbox.lottery.isNotEmpty) return true;
    return state.baselineInitialized ||
        state.ownSeq.isNotEmpty ||
        state.clearedAt.isNotEmpty ||
        state.pulled.isNotEmpty ||
        state.ownRollcallStats.isNotEmpty ||
        state.ownLotteryStats.isNotEmpty;
  }

  Future<void> _pushAfterInitialSync() async {
    final ok = await pushToCloud();
    if (_isDisposed) return;
    if (ok) {
      _cloudDirty = false;
    } else {
      _cloudDirty = true;
      _scheduleCloudPush();
    }
  }

  /// 新设备首次登录：用云端完整快照初始化本地数据基线
  ///
  /// 只在本地没有任何数据基线时调用，此时才严格覆盖本地：学生名单、
  /// 点名历史、抽奖记录与抽取统计全部以云端为准。随后重置同步状态：
  /// ownSeq 取已有与云端本机最大序号的较大值以避免 uid 复用，清空拉取
  /// 游标、clearedAt 与 outbox，并置 legacyUploaded 防止旧记录被再次灌入。
  ///
  /// 期间置 [_overwriteInProgress] 防止并发推送/拉取；数据写入失败时保留
  /// outbox 与旧状态（不清空），使本次覆盖可视为未发生，避免半覆盖后丢失
  /// 待上传数据。
  Future<bool> _initializeLocalBaselineFromCloud() async {
    if (_isDisposed) return false;
    _overwriteInProgress = true;
    try {
      // 与服务端 pushAll/flushOutbox 用同一 deviceId，避免降级到 'unknown'
      // 导致 own 统计/ownSeq 与真实流前缀错配。
      final deviceId = await _cloudSyncService.resolveDeviceId();

      final snapshot = await _cloudSyncService.pullFullSnapshot();
      if (snapshot == null || _isDisposed) return false;

      // 1. 点名历史：整体替换（写盘后重载，保证内存与磁盘一致）
      final cloudHistory = snapshot.rollcallRecords
          .map((json) => HistoryRecord.fromJson(json))
          .toList()
        ..sort((a, b) => b.id.compareTo(a.id));
      // 2. 抽奖记录：整体替换
      final cloudLottery = snapshot.lotteryRecords
          .map((json) => LotteryRecord.fromJson(json))
          .toList();

      // 先在内存/磁盘落地数据，全部成功后才重置同步状态（outbox/游标），
      // 保证"覆盖失败=本地不变"，不会清掉待上传队列。
      _allStudents = snapshot.students;
      await _dataService.saveStudents(_allStudents);
      await _dataService.saveHistory(cloudHistory);
      _history = await _dataService.loadHistory();
      await _dataService.saveLotteryRecords(cloudLottery);

      // 3. 统计：总视图=全部设备贡献求和；own=本机在云端的贡献
      _rollcallStats =
          _mergeStats(DrawStats(), snapshot.rollcallContributions.values);
      _lotteryStats =
          _mergeStats(DrawStats(), snapshot.lotteryContributions.values);
      _ownRollcallStats =
          DrawStats(snapshot.rollcallContributions[deviceId] ?? const {});
      _ownLotteryStats =
          DrawStats(snapshot.lotteryContributions[deviceId] ?? const {});

      // 4. 同步状态一次性落盘（数据已成功写入，此时才清 outbox/游标）
      final state = await _cloudSyncService.loadState();
      for (final kind in const ['rollcall', 'lottery']) {
        final records = kind == 'rollcall'
            ? snapshot.rollcallRecords
            : snapshot.lotteryRecords;
        final maxSeq = _maxOwnSeq(records, deviceId);
        if (maxSeq > (state.ownSeq[kind] ?? 0)) {
          state.ownSeq[kind] = maxSeq;
        }
      }
      state.ownRollcallStats
        ..clear()
        ..addAll(_ownRollcallStats.toMap());
      state.ownLotteryStats
        ..clear()
        ..addAll(_ownLotteryStats.toMap());
      state.pulled.clear(); // 本地已等于云端，下次增量拉取按 uid 去重即可
      // 覆盖是"以云端为准"，本地此前的清空语义不再适用：保留 clearedAt 会让
      // 后续增量拉取过滤掉刚被覆盖进来的云端旧记录，与覆盖结果矛盾，故清空。
      state.clearedAt.clear();
      state.legacyUploaded = true;
      state.baselineInitialized = true;
      await _cloudSyncService.saveState();
      await _cloudSyncService.clearOutbox();

      // 5. 应用名单到班级/筛选状态，清除待推送脏标记（本地已等于云端）
      await _applyPulledStudents();
      _cloudDirty = false;

      _notifyIfActive();
      return true;
    } catch (e) {
      // 任何一步失败：不清理 outbox/游标，本地视为未覆盖；记为同步错误
      logger.e('云端本地基线初始化失败，已保留本地待上传数据', error: e);
      return false;
    } finally {
      _overwriteInProgress = false;
    }
  }

  /// 已有本地基线时：本地与云端按 uid 并集合并，并把本地独有记录补入 outbox。
  Future<bool> _mergeLocalWithCloudSnapshot() async {
    if (_isDisposed) return false;
    _overwriteInProgress = true;
    try {
      final deviceId = await _cloudSyncService.resolveDeviceId();
      final localHistory =
          await _ensureHistoryUids(await _dataService.loadHistory());
      final localLottery =
          await _ensureLotteryUids(await _dataService.loadLotteryRecords());
      final localStudents = _allStudents;
      final state = await _cloudSyncService.loadState();

      final snapshot = await _cloudSyncService.pullFullSnapshot();
      if (snapshot == null || _isDisposed) return false;

      final allCloudHistory = snapshot.rollcallRecords
          .map((json) => HistoryRecord.fromJson(json))
          .where((record) => record.uid != null && record.uid!.isNotEmpty)
          .toList();
      final allCloudLottery = snapshot.lotteryRecords
          .map((json) => LotteryRecord.fromJson(json))
          .where((record) => record.uid != null && record.uid!.isNotEmpty)
          .toList();

      final cloudHistoryUids = allCloudHistory.map((r) => r.uid!).toSet();
      final cloudLotteryUids = allCloudLottery.map((r) => r.uid!).toSet();

      // clearedAt 是本机的清空语义：云端里比清空时间更早的记录不合并回来。
      final visibleCloudHistory = allCloudHistory
          .where((record) => _isAfterClear(
                'rollcall',
                state,
                DateTime.tryParse(record.drawTime),
              ))
          .toList();
      final visibleCloudLottery = allCloudLottery
          .where((record) =>
              _isAfterClear('lottery', state, record.drawTime))
          .toList();

      final localOnlyHistory = localHistory
          .where((record) => !cloudHistoryUids.contains(record.uid))
          .toList();
      final localOnlyLottery = localLottery
          .where((record) => !cloudLotteryUids.contains(record.uid))
          .toList();

      final mergedHistory = <String, HistoryRecord>{
        for (final record in visibleCloudHistory) record.uid!: record,
        for (final record in localHistory) record.uid!: record,
      }.values.toList()
        ..sort((a, b) => b.drawTime.compareTo(a.drawTime));
      final mergedLottery = <String, LotteryRecord>{
        for (final record in visibleCloudLottery) record.uid!: record,
        for (final record in localLottery) record.uid!: record,
      }.values.toList()
        ..sort((a, b) => b.drawTime.compareTo(a.drawTime));

      await _dataService.saveHistory(mergedHistory);
      _history = await _dataService.loadHistory();
      await _dataService.saveLotteryRecords(mergedLottery);

      // 名单仍以云端优先；云端没有名单时保留本地，随本次 push 上传。
      if (snapshot.students.isNotEmpty) {
        _allStudents = snapshot.students;
        await _dataService.saveStudents(_allStudents);
      } else {
        _allStudents = localStudents;
      }

      // 统计：云端总视图 + 本机贡献 max(本地, 云端)，保留本地独有记录贡献。
      final ownRollcall = DrawStats(
        snapshot.rollcallContributions[deviceId] ?? const {},
      )..mergeMax(_ownRollcallStats);
      final ownLottery = DrawStats(
        snapshot.lotteryContributions[deviceId] ?? const {},
      )..mergeMax(_ownLotteryStats);
      _ownRollcallStats = ownRollcall;
      _ownLotteryStats = ownLottery;
      _rollcallStats = _mergeStats(
        _ownRollcallStats,
        snapshot.rollcallContributions.entries
            .where((entry) => entry.key != deviceId)
            .map((entry) => entry.value),
      );
      _lotteryStats = _mergeStats(
        _ownLotteryStats,
        snapshot.lotteryContributions.entries
            .where((entry) => entry.key != deviceId)
            .map((entry) => entry.value),
      );

      for (final kind in const ['rollcall', 'lottery']) {
        final records = kind == 'rollcall'
            ? snapshot.rollcallRecords
            : snapshot.lotteryRecords;
        final maxSeq = _maxOwnSeq(records, deviceId);
        if (maxSeq > (state.ownSeq[kind] ?? 0)) {
          state.ownSeq[kind] = maxSeq;
        }
      }
      state.ownRollcallStats
        ..clear()
        ..addAll(_ownRollcallStats.toMap());
      state.ownLotteryStats
        ..clear()
        ..addAll(_ownLotteryStats.toMap());
      state.pulled.clear();
      state.legacyUploaded = true;
      state.baselineInitialized = true;
      await _cloudSyncService.saveState();

      // 云端已有的记录从 outbox 移除；本地独有记录补入 outbox。
      await _cloudSyncService.removeFromOutbox('rollcall', cloudHistoryUids);
      await _cloudSyncService.removeFromOutbox('lottery', cloudLotteryUids);
      await _cloudSyncService.enqueueAll(
        'rollcall',
        localOnlyHistory.map((record) => record.toJson()),
      );
      await _cloudSyncService.enqueueAll(
        'lottery',
        localOnlyLottery.map((record) => record.toJson()),
      );

      await _applyPulledStudents();
      _notifyIfActive();
      return true;
    } catch (e, st) {
      logger.e('云端历史合并失败，已保留本地数据', error: e, stackTrace: st);
      return false;
    } finally {
      _overwriteInProgress = false;
    }
  }

  bool _isAfterClear(String kind, LocalSyncState state, DateTime? time) {
    final clearedAt = state.clearedAt[kind];
    if (clearedAt == null) return true;
    return time == null || !time.isBefore(clearedAt);
  }

  Future<List<HistoryRecord>> _ensureHistoryUids(
    List<HistoryRecord> records,
  ) async {
    var changed = false;
    final result = <HistoryRecord>[];
    for (final record in records) {
      if (record.uid == null || record.uid!.isEmpty) {
        result.add(record.copyWithUid(deriveLegacyHistoryUid(record)));
        changed = true;
      } else {
        result.add(record);
      }
    }
    if (changed) await _dataService.saveHistory(result);
    return result;
  }

  Future<List<LotteryRecord>> _ensureLotteryUids(
    List<LotteryRecord> records,
  ) async {
    var changed = false;
    final result = <LotteryRecord>[];
    for (final record in records) {
      if (record.uid == null || record.uid!.isEmpty) {
        result.add(record.copyWithUid(deriveLegacyLotteryUid(record)));
        changed = true;
      } else {
        result.add(record);
      }
    }
    if (changed) await _dataService.saveLotteryRecords(result);
    return result;
  }

  /// 云端为空时，把完整本地历史/抽奖记录补入 outbox。
  Future<void> _enqueueAllLocalHistory(
    List<HistoryRecord> history,
    List<LotteryRecord> lottery,
  ) async {
    final historyWithUid = await _ensureHistoryUids(history);
    final lotteryWithUid = await _ensureLotteryUids(lottery);
    _history = [...historyWithUid]
      ..sort((a, b) => b.drawTime.compareTo(a.drawTime));

    if (_ownRollcallStats.toMap().isEmpty && historyWithUid.isNotEmpty) {
      _ownRollcallStats =
          DrawStats.fromHistoryNames(historyWithUid.map((r) => r.name));
      _rollcallStats = DrawStats(_ownRollcallStats.toMap());
    }
    if (_ownLotteryStats.toMap().isEmpty && lotteryWithUid.isNotEmpty) {
      _ownLotteryStats = DrawStats.fromLotteryRecords(lotteryWithUid);
      _lotteryStats = DrawStats(_ownLotteryStats.toMap());
    }

    await _cloudSyncService.enqueueAll(
      'rollcall',
      historyWithUid.map((record) => record.toJson()),
    );
    await _cloudSyncService.enqueueAll(
      'lottery',
      lotteryWithUid.map((record) => record.toJson()),
    );

    final state = await _cloudSyncService.loadState();
    state.ownRollcallStats
      ..clear()
      ..addAll(_ownRollcallStats.toMap());
    state.ownLotteryStats
      ..clear()
      ..addAll(_ownLotteryStats.toMap());
    state.legacyUploaded = true;
    state.baselineInitialized = true;
    await _cloudSyncService.saveState();
  }

  /// 把本地独有的历史/抽奖记录补传云端（导入、云备份恢复后调用）。
  ///
  /// 不覆盖本地数据；云端已有的记录按 uid 跳过。
  Future<bool> syncLocalHistoryToCloud() async {
    if (!_isLoggedIn || _isDisposed || _overwriteInProgress) return false;
    try {
      final history =
          await _ensureHistoryUids(await _dataService.loadHistory());
      final lottery =
          await _ensureLotteryUids(await _dataService.loadLotteryRecords());
      _history = [...history]
        ..sort((a, b) => b.drawTime.compareTo(a.drawTime));

      final snapshot = await _cloudSyncService.pullFullSnapshot();
      if (snapshot == null) {
        logger.w('补传本地历史失败：云端快照不完整');
        return false;
      }
      final cloudHistoryUids = snapshot.rollcallRecords
          .map((json) => ensureHistoryUid(json))
          .toSet();
      final cloudLotteryUids = snapshot.lotteryRecords
          .map((json) => ensureLotteryUid(json))
          .toSet();

      await _cloudSyncService.removeFromOutbox('rollcall', cloudHistoryUids);
      await _cloudSyncService.removeFromOutbox('lottery', cloudLotteryUids);

      final missingHistory = history
          .where((record) => !cloudHistoryUids.contains(record.uid))
          .toList();
      final missingLottery = lottery
          .where((record) => !cloudLotteryUids.contains(record.uid))
          .toList();
      await _cloudSyncService.enqueueAll(
        'rollcall',
        missingHistory.map((record) => record.toJson()),
      );
      await _cloudSyncService.enqueueAll(
        'lottery',
        missingLottery.map((record) => record.toJson()),
      );

      final ok = await pushToCloud();
      if (ok) {
        _cloudDirty = false;
      } else {
        _cloudDirty = true;
        _scheduleCloudPush();
      }
      return ok;
    } catch (e, st) {
      logger.e('补传本地历史失败', error: e, stackTrace: st);
      return false;
    }
  }

  /// 本机（[deviceId]）在历史记录里的最大本地序号，用于覆盖后推进 ownSeq
  ///
  /// uid 形如 `<deviceId>:<seq>`；只统计属于本机的记录，避免拉低已有序号。
  int _maxOwnSeq(Iterable<Map<String, dynamic>> records, String deviceId) {
    var max = 0;
    final prefix = '$deviceId:';
    for (final record in records) {
      final uid = record['uid'] as String? ?? '';
      if (!uid.startsWith(prefix)) continue;
      final seq = int.tryParse(uid.substring(prefix.length));
      if (seq != null && seq > max) max = seq;
    }
    return max;
  }

  void setCloudSyncEnabled(bool enabled) {
    _cloudSyncEnabled = enabled;
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setBool(_kAutoSyncPrefKey, enabled),
      ),
    );
    if (enabled && _cloudDirty) {
      _scheduleCloudPush();
    } else if (!enabled) {
      _cloudDebounceTimer?.cancel();
      _cloudSyncService.cancelRetries();
    }
    _notifyIfActive();
  }

  /// 标记数据已变更，防抖后自动推送
  ///
  /// 关闭/未登录时只记脏标记不调度网络；重新开启后由
  /// [setCloudSyncEnabled] 补推。
  void _markCloudDirty() {
    _cloudDirty = true;
    if (!_cloudSyncEnabled || !_isLoggedIn) return;
    _scheduleCloudPush();
  }

  void _scheduleCloudPush() {
    _cloudDebounceTimer?.cancel();
    _cloudDebounceTimer = Timer(_cloudDebounceDelay, () {
      if (_cloudDirty && _cloudSyncEnabled && _isLoggedIn && !_isDisposed) {
        _autoPushToCloud();
      }
    });
  }

  Future<void> _autoPushToCloud() async {
    if (!_cloudSyncEnabled || !_isLoggedIn || _isDisposed || _overwriteInProgress) {
      return;
    }
    final ok = await _runPushAttempt();
    if (!ok && _isLoggedIn && _cloudSyncEnabled) {
      // 失败后调度指数退避重试
      _cloudSyncService.scheduleRetry(_retryPushCloud);
    }
  }

  /// 单次推送尝试：发起前清脏标记，失败回置（保证放弃重试后状态不丢失）
  Future<bool> _runPushAttempt() async {
    _cloudDirty = false;
    try {
      final ok = await pushToCloud();
      if (!ok) _cloudDirty = true;
      return ok;
    } catch (e) {
      logger.w('自动推送失败', error: e);
      _cloudDirty = true;
      return false;
    }
  }

  /// 重试用：已登出/已关闭时返回 true 停止退避循环
  Future<bool> _retryPushCloud() async {
    if (!_isLoggedIn || !_cloudSyncEnabled) return true;
    return _runPushAttempt();
  }

  /// 把本机统计贡献持久化到 sync_state
  Future<void> _persistOwnStats() async {
    final state = await _cloudSyncService.loadState();
    state.ownRollcallStats
      ..clear()
      ..addAll(_ownRollcallStats.toMap());
    state.ownLotteryStats
      ..clear()
      ..addAll(_ownLotteryStats.toMap());
    await _cloudSyncService.saveState();
  }

  /// 抽奖中奖记录落盘后的同步钩子：统计 + 入 outbox + 防抖推送
  void onLotteryRecordSaved(LotteryRecord record) {
    _ownLotteryStats.addLotteryRecord(record);
    _lotteryStats.addLotteryRecord(record);
    unawaited(_persistOwnStats());
    unawaited(_cloudSyncService.enqueueRecord('lottery', record.toJson()));
    _markCloudDirty();
    _notifyIfActive();
  }

  /// 保存前给抽奖记录分配 uid
  Future<LotteryRecord> prepareLotteryRecord(LotteryRecord record) async {
    if (record.uid != null) return record;
    final seq = await _cloudSyncService.nextSeq('lottery');
    return record.copyWith(uid: newRecordUid(_deviceId ?? 'unknown', seq));
  }

  /// 抽奖历史清空后的本地语义：清 own 贡献 + 记 clearedAt + 清 outbox
  Future<void> markLotteryCleared() async {
    _ownLotteryStats = DrawStats();
    _lotteryStats = DrawStats();
    await _cloudSyncService.markCleared('lottery', DateTime.now());
    await _persistOwnStats();
    _notifyIfActive();
  }

  /// 从云端拉取点名历史并合并到本地（新管线），返回新增条数
  Future<int> loadHistoryFromCloud({int limit = 500}) async {
    if (!_isLoggedIn) return 0;
    await pullFromCloud();
    return _lastPullNewRecords;
  }

  /// 从云端拉取抽奖历史并合并到本地（新管线），返回新增条数
  Future<int> loadLotteryHistoryFromCloud({int limit = 500}) async {
    if (!_isLoggedIn) return 0;
    await pullFromCloud();
    return _lastPullNewRecords;
  }

  /// 历史页下拉刷新：已登录且开启云同步时立即拉取云端，
  /// 之后（含未登录、拉取失败）一律从磁盘重载本地记录。
  ///
  /// 本地是 Source of Truth：云端拉取先落盘，重载保证内存与磁盘一致，
  /// 因此失败回退时展示的仍是完整本地数据。
  Future<HistoryRefreshResult> refreshHistory() async {
    if (_isDisposed) return const HistoryRefreshResult(fromCloud: false);

    var fromCloud = false;
    var newRecords = 0;
    String? errorMessage;

    if (_isLoggedIn && _cloudSyncEnabled) {
      bool ok;
      try {
        ok = await pullFromCloud();
      } catch (e) {
        logger.w('下拉刷新拉取云端失败', error: e);
        ok = false;
      }
      if (ok) {
        fromCloud = true;
        newRecords = _lastPullNewRecords;
      } else {
        // 离线、网络异常或服务端错误都落到这里：提示失败并回退本地
        errorMessage = '云端同步失败，已刷新本地记录';
      }
    }

    if (_isDisposed) return const HistoryRefreshResult(fromCloud: false);
    _history = await _dataService.loadHistory();
    _notifyIfActive();
    return HistoryRefreshResult(
      fromCloud: fromCloud,
      newRecords: newRecords,
      errorMessage: errorMessage,
    );
  }

  /// 推送：冲洗 outbox + own 统计贡献 + 学生名单
  ///
  /// 未登录时静默跳过（不写 lastError）；覆盖进行中跳过，避免把半覆盖状态推上云。
  Future<bool> pushToCloud() async {
    if (!_isLoggedIn || _overwriteInProgress) return false;
    final future = _cloudSyncService.pushAll(
      ownRollcall: _ownRollcallStats.toMap(),
      ownLottery: _ownLotteryStats.toMap(),
      students: _allStudents,
    );
    _notifyIfActive();
    final ok = await future;
    _notifyIfActive();
    return ok;
  }

  /// 拉取并合并：历史按 uid 去重、统计贡献求和、名单云端优先
  ///
  /// 未登录时静默跳过（不写 lastError）；覆盖进行中跳过，避免与覆盖写盘交错。
  Future<bool> pullFromCloud() async {
    if (!_isLoggedIn || _overwriteInProgress) return false;
    final future = _cloudSyncService.pullAll(
      existingUids: (kind) async {
        if (kind == 'rollcall') {
          final records = await _dataService.loadHistory();
          return records
              .map((r) => r.uid ?? deriveLegacyHistoryUid(r))
              .toSet();
        }
        final records = await _dataService.loadLotteryRecords();
        return records
            .map((r) => r.uid ?? deriveLegacyLotteryUid(r))
            .toSet();
      },
      onNewRecord: (kind, json) async {
        if (kind == 'rollcall') {
          final record = HistoryRecord.fromJson(json);
          await _dataService.addHistoryRecord(record);
          _history.add(record);
        } else {
          final record = LotteryRecord.fromJson(json);
          await _dataService.addLotteryRecord(record);
        }
      },
    );
    _notifyIfActive();
    final result = await future;
    if (result == null) {
      _notifyIfActive();
      return false;
    }

    _lastPullNewRecords = result.newRecords;
    _rollcallStats =
        _mergeStats(_ownRollcallStats, result.rollcallContributions.values);
    _lotteryStats =
        _mergeStats(_ownLotteryStats, result.lotteryContributions.values);
    _history.sort((a, b) => b.id.compareTo(a.id));

    if (result.students.isNotEmpty) {
      _allStudents = result.students;
      await _dataService.saveStudents(_allStudents);
      await _applyPulledStudents();
    }
    _notifyIfActive();
    return true;
  }

  DrawStats _mergeStats(DrawStats own, Iterable<Map<String, int>> contributions) {
    final merged = DrawStats(own.toMap());
    for (final map in contributions) {
      merged.mergeSum(DrawStats(map));
    }
    return merged;
  }

  /// 立即同步：先拉后推
  Future<bool> syncNow() async {
    if (!_isLoggedIn || !_cloudSyncEnabled || _overwriteInProgress) return false;
    final pulled = await pullFromCloud();
    if (!_canSync) return pulled;
    final pushed = await pushToCloud();
    _lastForegroundSyncAt = DateTime.now();
    return pulled || pushed;
  }

  /// 应用回到前台时调用（5 分钟节流）
  void onAppResumed() {
    if (!_isLoggedIn || !_cloudSyncEnabled || _overwriteInProgress) return;
    final last = _lastForegroundSyncAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 5)) {
      return;
    }
    unawaited(syncNow());
  }

  /// 组装完整快照并上传到云文件存储（手动备份）
  Future<bool> uploadBackupToCloud() async {
    if (!_isLoggedIn) return false;
    final snapshot = <String, dynamic>{
      'version': 1,
      'device_id': _deviceId,
      'created_at': DateTime.now().toIso8601String(),
      'students': _allStudents.map((s) => s.toJson()).toList(),
      'history':
          (await _dataService.loadHistory()).map((r) => r.toJson()).toList(),
      'lottery': (await _dataService.loadLotteryRecords())
          .map((r) => r.toJson())
          .toList(),
    };
    final ok = await _cloudSyncService.uploadBackup(snapshot);
    _notifyIfActive();
    return ok;
  }

  /// 下载最近备份并按 uid 并集合并；返回合并条数，无备份返回 -1
  ///
  /// ponytail: 恢复只合并历史与名单，不重算抽取统计；灾难恢复后
  /// 如需精确权重，可清空 sync_state 让统计从本地历史重建。
  Future<int> restoreFromCloudBackup() async {
    if (!_isLoggedIn) return -1;
    final snapshot = await _cloudSyncService.downloadLatestBackup();
    if (snapshot == null) return -1;

    var merged = 0;

    final historyJson = _jsonMaps(snapshot['history']);
    if (historyJson.isNotEmpty) {
      final existing = (await _dataService.loadHistory())
          .map((r) => r.uid)
          .whereType<String>()
          .toSet();
      for (final json in historyJson) {
        final uid = ensureHistoryUid(json);
        if (existing.contains(uid)) continue;
        final record = HistoryRecord.fromJson(json);
        await _dataService.addHistoryRecord(record);
        _history.add(record);
        existing.add(uid);
        merged++;
      }
      _history.sort((a, b) => b.drawTime.compareTo(a.drawTime));
    }

    final lotteryJson = _jsonMaps(snapshot['lottery']);
    if (lotteryJson.isNotEmpty) {
      final existing = (await _dataService.loadLotteryRecords())
          .map((r) => r.uid)
          .whereType<String>()
          .toSet();
      for (final json in lotteryJson) {
        final uid = ensureLotteryUid(json);
        if (existing.contains(uid)) continue;
        await _dataService.addLotteryRecord(LotteryRecord.fromJson(json));
        existing.add(uid);
        merged++;
      }
    }

    final students = _jsonMaps(snapshot['students'])
        .map((e) => Student.fromJson(e))
        .toList();
    if (students.isNotEmpty) {
      _allStudents = students;
      await _dataService.saveStudents(_allStudents);
      await _applyPulledStudents();
    }

    // 恢复出来的记录只在本地；登录态下立即补传云端，避免再次形成单向数据。
    if (merged > 0) {
      await syncLocalHistoryToCloud();
    }

    _notifyIfActive();
    return merged;
  }

  List<Map<String, dynamic>> _jsonMaps(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _cloudDebounceTimer?.cancel();
    _rollCallSessionId++;
    super.dispose();
  }
}

class BatchImportResult {
  final int successCount;
  final int failCount;

  const BatchImportResult({
    required this.successCount,
    required this.failCount,
  });

  int get totalCount => successCount + failCount;
}

/// 历史下拉刷新结果
class HistoryRefreshResult {
  const HistoryRefreshResult({
    required this.fromCloud,
    this.newRecords = 0,
    this.errorMessage,
  });

  /// 是否成功从云端拉取
  final bool fromCloud;

  /// 云端新增条数（fromCloud 为 true 时有效）
  final int newRecords;

  /// 失败提示：云端拉取失败、已回退本地刷新时非空
  final String? errorMessage;
}




