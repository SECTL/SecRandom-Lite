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
  final CloudSyncService _cloudSyncService = CloudSyncService();
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

  AppProvider() {
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
    notifyListeners();
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
      if (_history.length > 50) {
        _history.removeLast();
      }

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
    // 先拉后推：本地空数据不覆盖云端
    await syncNow();
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
    if (!_cloudSyncEnabled || !_isLoggedIn || _isDisposed) return;
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

  /// 推送：冲洗 outbox + own 统计贡献 + 学生名单
  ///
  /// 未登录时静默跳过（不写 lastError）。
  Future<bool> pushToCloud() async {
    if (!_isLoggedIn) return false;
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
  /// 未登录时静默跳过（不写 lastError）。
  Future<bool> pullFromCloud() async {
    if (!_isLoggedIn) return false;
    final future = _cloudSyncService.pullAll(
      existingUids: (kind) async {
        if (kind == 'rollcall') {
          final records = await _dataService.loadHistory();
          return records.map((r) => r.uid).whereType<String>().toSet();
        }
        final records = await _dataService.loadLotteryRecords();
        return records.map((r) => r.uid).whereType<String>().toSet();
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
    if (!_isLoggedIn || !_cloudSyncEnabled) return false;
    final pulled = await pullFromCloud();
    if (!_canSync) return pulled;
    final pushed = await pushToCloud();
    _lastForegroundSyncAt = DateTime.now();
    return pulled || pushed;
  }

  /// 应用回到前台时调用（5 分钟节流）
  void onAppResumed() {
    if (!_isLoggedIn || !_cloudSyncEnabled) return;
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
        final uid = json['uid'] as String?;
        if (uid == null || existing.contains(uid)) continue;
        final record = HistoryRecord.fromJson(json);
        await _dataService.addHistoryRecord(record);
        _history.add(record);
        existing.add(uid);
        merged++;
      }
      _history.sort((a, b) => b.id.compareTo(a.id));
    }

    final lotteryJson = _jsonMaps(snapshot['lottery']);
    if (lotteryJson.isNotEmpty) {
      final existing = (await _dataService.loadLotteryRecords())
          .map((r) => r.uid)
          .whereType<String>()
          .toSet();
      for (final json in lotteryJson) {
        final uid = json['uid'] as String?;
        if (uid == null || existing.contains(uid)) continue;
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




