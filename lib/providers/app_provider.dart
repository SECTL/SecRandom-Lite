import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_config.dart';
import '../models/draw_stats.dart';
import '../models/history_record.dart';
import '../models/student.dart';
import '../services/auth/token_manager.dart';
import '../services/cloud/cloud_sync_service.dart';
import '../services/cloud/student_sync.dart';
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

  bool _isRolling = false;
  bool _isDisposed = false;
  bool _isFinalizingRollCall = false;
  ThemeMode _themeMode = ThemeMode.system;
  AnimationMode _rollcallAnimationMode = AnimationMode.auto;
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

  // 账号工作区
  Future<void>? _loadFuture;
  String _workspaceKey = DataService.guestWorkspace;
  String? _authUserId;
  int _workspaceEpoch = 0;
  bool _workspaceReady = true;
  Future<void> _authChange = Future<void>.value();

  // 学生同步状态
  int _studentClock = 0;
  int _studentSeq = 0;
  bool _studentsDirty = false;
  Map<String, StudentTombstone> _studentTombstones = {};
  bool _clearsDirty = false;
  DateTime? _clearedRollcallAll;
  Map<String, Map<String, DateTime>> _clearedClasses = {};

  int _selectCount = 1;
  bool _nonRepeatEnabled = true;
  double _rollcallResultFontSize = 48;
  String? _selectedClass;
  String? _selectedGroup;
  String? _selectedGender;

  List<Student> get allStudents => _allStudents;
  List<Student> get currentSelection => _currentSelection;
  bool get isRolling => _isRolling;
  ThemeMode get themeMode => _themeMode;
  AnimationMode get rollcallAnimationMode => _rollcallAnimationMode;
  int get selectCount => _selectCount;
  int get remainingCount => _remainingStudents.length;
  int get totalCount => _filteredStudents().length;
  bool get nonRepeatEnabled => _nonRepeatEnabled;
  double get rollcallResultFontSize => _rollcallResultFontSize;
  String? get selectedClass => _selectedClass;
  String? get selectedGroup => _selectedGroup;
  String? get selectedGender => _selectedGender;
  List<HistoryRecord> get history => _history;
  List<Student> get filteredStudents => _filteredStudents();
  List<String> get groups => _groups;
  DrawStats get rollcallStats => _rollcallStats;
  CloudSyncService get cloudSyncService => _cloudSyncService;
  bool get cloudLoggedIn => _isLoggedIn;

  AppProvider({CloudSyncService? cloudSyncService})
    : _cloudSyncService = cloudSyncService ?? CloudSyncService() {
    _startLoad();
  }

  /// 首次本地数据加载完成；测试和 UI 用它替代轮询 [totalCount]。
  Future<void> get ready => _loadFuture ?? Future<void>.value();

  void _startLoad() {
    _loadFuture = _loadData();
  }

  /// 重新加载所有数据（用于导入后刷新）
  Future<void> reloadData() async {
    await _loadData();
  }

  Future<void> _loadData() async {
    _workspaceKey = DataService.currentWorkspace;
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
    if (_deviceId == null || _deviceId!.isEmpty) {
      // 测试或安全存储不可用时，与服务层保持同一设备 ID，避免学生 uid 落到 unknown。
      try {
        _deviceId = await _cloudSyncService.resolveDeviceId();
      } catch (_) {
        // 仍不可用：保留 null，后续按 'unknown' 处理。
      }
    }
    final syncState = await _cloudSyncService.loadState();
    _ownRollcallStats = DrawStats(syncState.ownRollcallStats);
    _rollcallStats = DrawStats(syncState.ownRollcallStats);
    _studentClock = syncState.studentClock;
    _studentSeq = syncState.studentSeq;
    _studentsDirty = syncState.studentsDirty;
    _studentTombstones = Map<String, StudentTombstone>.from(
      syncState.studentTombstones,
    );
    _clearsDirty = syncState.clearsDirty;
    _clearedRollcallAll = syncState.clearedAt['rollcall'];
    _clearedClasses = {
      for (final entry in syncState.clearedClasses.entries)
        entry.key: Map<String, DateTime>.from(entry.value),
    };
    await _migrateLegacySyncData(syncState);

    final config = await _dataService.loadConfig();
    _themeMode = _parseThemeMode(config.themeMode);
    _selectCount = 1;
    _nonRepeatEnabled = config.nonRepeatEnabled;
    _rollcallResultFontSize = config.rollcallResultFontSize;
    _rollcallAnimationMode = config.rollcallAnimationMode;
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
      nonRepeatEnabled: _nonRepeatEnabled,
      rollcallResultFontSize: _rollcallResultFontSize,
      rollcallAnimationMode: _rollcallAnimationMode,
    );

    _pendingConfigSave = _pendingConfigSave
        .catchError((_) {})
        .then((_) => _dataService.saveConfig(config));

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
        updated.add(_touchStudent(s.copyWith(group: newName)));
        changed = true;
      } else {
        updated.add(s);
      }
    }

    if (changed) {
      _allStudents = updated;
      await _dataService.saveStudents(_allStudents);
      _markStudentsChanged();
      await _persistStudentSyncState();
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
        updated.add(_touchStudent(s.copyWith(group: '1')));
        changed = true;
      } else {
        updated.add(s);
      }
    }

    if (changed) {
      _allStudents = updated;
      await _dataService.saveStudents(_allStudents);
      _markStudentsChanged();
      await _persistStudentSyncState();
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
        updated.add(_touchStudent(s.copyWith(className: normalized)));
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
      _markStudentsChanged();
      await _persistStudentSyncState();
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

    final removed = _allStudents
        .where((s) => s.className == className)
        .toList();
    for (final student in removed) {
      _tombstoneStudent(student);
    }
    _allStudents.removeWhere((s) => s.className == className);
    await _dataService.saveStudents(_allStudents);
    _markStudentsChanged();
    await _persistStudentSyncState();
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
  /// 否则点名页面仍按 "1" 筛选，看起来像名单没刷新。
  String get _deviceIdOrUnknown => _deviceId ?? 'unknown';

  String _nextStudentUid() {
    _studentSeq += 1;
    return '$_deviceIdOrUnknown:s$_studentSeq';
  }

  Student _touchStudent(Student student) {
    _studentClock += 1;
    return student.copyWith(rev: _studentClock, revBy: _deviceIdOrUnknown);
  }

  void _tombstoneStudent(Student student) {
    if (student.uid.isEmpty) return;
    _studentClock += 1;
    _studentTombstones[student.uid] = StudentTombstone(
      rev: _studentClock,
      by: _deviceIdOrUnknown,
      at: DateTime.now(),
    );
  }

  /// 学生修订/序号/墓碑/脏标记落盘到 sync_state.json。
  Future<void> _persistStudentSyncState() async {
    final state = await _cloudSyncService.loadState();
    state.studentClock = _studentClock;
    state.studentSeq = _studentSeq;
    state.studentsDirty = _studentsDirty;
    state.studentTombstones
      ..clear()
      ..addAll(_studentTombstones);
    await _cloudSyncService.saveState();
  }

  void _markStudentsChanged() {
    _studentsDirty = true;
    _markCloudDirty();
  }

  CloudClearState _localClearState() => CloudClearState(
    rollcallAll: _clearedRollcallAll,
    rollcallClasses: _clearedClasses['rollcall'] ?? const {},
  );

  Future<void> _persistClearSyncState() async {
    final state = await _cloudSyncService.loadState();
    state.clearsDirty = _clearsDirty;
    _localClearState().applyTo(state);
    await _cloudSyncService.saveState();
  }

  void _setLocalClears(CloudClearState merged) {
    _clearedRollcallAll = merged.rollcallAll;
    _clearedClasses['rollcall'] = Map<String, DateTime>.from(
      merged.rollcallClasses,
    );
  }

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

  void setRollcallAnimationMode(AnimationMode mode) {
    _rollcallAnimationMode = mode;
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
      _touchStudent(
        Student(
          id: newId,
          uid: _nextStudentUid(),
          name: normalizedName,
          gender: gender,
          group: normalizedGroup,
          className: normalizedClass,
          exist: exist,
        ),
      ),
    );

    await _dataService.saveStudents(_allStudents);
    _markStudentsChanged();
    await _persistStudentSyncState();
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

    _allStudents[index] = _touchStudent(
      old.copyWith(
        name: nextName,
        gender: gender ?? old.gender,
        group: nextGroup,
        exist: exist ?? old.exist,
      ),
    );

    await _dataService.saveStudents(_allStudents);
    _markStudentsChanged();
    await _persistStudentSyncState();
    _resetRemaining();
    notifyListeners();
  }

  Future<void> deleteStudentFromClass(String className, int id) async {
    final removed = _allStudents
        .where((s) => s.className == className && s.id == id)
        .toList();
    for (final student in removed) {
      _tombstoneStudent(student);
    }
    _allStudents.removeWhere((s) => s.className == className && s.id == id);
    await _dataService.saveStudents(_allStudents);
    _markStudentsChanged();
    await _persistStudentSyncState();
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
      newId =
          classStudents.map((s) => s.id).reduce((a, b) => a > b ? a : b) + 1;
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
        _touchStudent(
          Student(
            id: newId,
            uid: _nextStudentUid(),
            name: name,
            gender: gender,
            group: group,
            className: normalizedClass,
            exist: exist,
          ),
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
    if (successCount > 0) {
      _markStudentsChanged();
      await _persistStudentSyncState();
    }
    _resetRemaining();
    await _saveConfig();
    notifyListeners();

    return BatchImportResult(successCount: successCount, failCount: failCount);
  }

  Future<void> clearHistory({String? className}) async {
    final now = DateTime.now();
    if (className != null) {
      _history = _history
          .where((record) => record.className != className)
          .toList();
      (_clearedClasses['rollcall'] ??= {})[className] = now;
      await _cloudSyncService.removeFromOutboxWhere(
        'rollcall',
        (record) => record['class_name']?.toString() == className,
      );
    } else {
      _history = [];
      _clearedRollcallAll = now;
      await _cloudSyncService.markCleared('rollcall', now);
    }
    await _dataService.clearHistoryRecords(className: className);
    _clearsDirty = true;
    await _persistClearSyncState();
    _markCloudDirty();
    await _trySyncClears();
    notifyListeners();
  }

  /// 同步清空文档；离线/未登录时保留 [clearsDirty]，下一次推送重试。
  Future<void> _trySyncClears() async {
    if (!_isLoggedIn ||
        !_clearsDirty ||
        _isDisposed ||
        !_workspaceReady ||
        _overwriteInProgress) {
      return;
    }
    try {
      final merged = await _cloudSyncService.syncClears(_localClearState());
      if (_isDisposed) return;
      _setLocalClears(merged);
      _clearsDirty = false;
      await _persistClearSyncState();
    } catch (e) {
      logger.w('清空文档同步失败，保留待推送标记', error: e);
    }
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
    if (!_isRolling ||
        _isFinalizingRollCall ||
        activeSessionId != _rollCallSessionId) {
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
          _remainingStudents.removeWhere(
            (remaining) => remaining.id == student.id,
          );
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

    List<Student> picked = _fairDrawService.draw(
      candidates: drawCandidates,
      stats: _rollcallStats,
      count: _selectCount,
    );
    if (picked.isEmpty) {
      picked = _randomService.pickRandomStudents(drawCandidates, _selectCount);
    }
    return picked;
  }

  Future<HistoryRecord> _buildRollCallRecord(
    String className,
    List<Student> picked,
  ) async {
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
      drawMethod: 2,
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
  /// 未登录 → guest 工作区；已登录且 [userId] 非空 → 该账号的工作区；
  /// 已登录但 [userId] 为空 → 保留当前工作区（测试/旧调用兼容）。
  ///
  /// 工作区切换串行执行：切到新账号时先建目录、加载空数据，再决定从云端
  /// 克隆还是初始化空基线；克隆完成前 [_workspaceReady] 为 false，推送/拉取
  /// 会被拒绝，避免把空工作区覆盖到真实云端数据上。
  Future<void> setAuthState(bool loggedIn, {String? userId}) {
    final normalizedUser =
        loggedIn && userId != null && userId.trim().isNotEmpty
        ? userId.trim()
        : null;
    final future = _authChange
        .catchError((_) {})
        .then((_) => _performAuthChange(loggedIn, normalizedUser));
    _authChange = future;
    return future;
  }

  Future<void> _performAuthChange(bool loggedIn, String? userId) async {
    if (_isDisposed) return;

    final targetWorkspace = !loggedIn
        ? DataService.guestWorkspace
        : (userId == null
              ? _workspaceKey
              : DataService.workspaceKeyForUser(userId));

    final unchanged =
        loggedIn == _isLoggedIn &&
        userId == _authUserId &&
        targetWorkspace == _workspaceKey &&
        targetWorkspace == DataService.currentWorkspace;
    if (unchanged) return;

    _cloudDebounceTimer?.cancel();
    _cloudDebounceTimer = null;
    _cloudSyncService.cancelRetries();

    try {
      await ready;
    } catch (_) {
      // 初次加载失败也要允许切换工作区。
    }
    try {
      await waitForPendingConfigSave();
    } catch (_) {
      // 配置保存失败不应阻塞账号切换。
    }
    if (_isDisposed) return;

    _workspaceEpoch++;
    final epoch = _workspaceEpoch;

    final switchingWorkspace = targetWorkspace != DataService.currentWorkspace;
    var isNewWorkspace = false;

    if (switchingWorkspace) {
      if (targetWorkspace != DataService.guestWorkspace) {
        isNewWorkspace = !await DataService.workspaceExists(targetWorkspace);
        if (isNewWorkspace) {
          await DataService.ensureWorkspace(targetWorkspace);
        }
      }
      if (_isDisposed || epoch != _workspaceEpoch) return;

      DataService.setWorkspace(targetWorkspace);
      _cloudSyncService.resetWorkspaceState();
      // 新工作区在克隆完成前不可同步；已有工作区加载后即可用。
      _workspaceReady = !isNewWorkspace;
    } else {
      _workspaceReady = true;
    }

    _isLoggedIn = loggedIn;
    _authUserId = userId;
    _cloudDirty = false;

    await _loadData();
    if (_isDisposed || epoch != _workspaceEpoch) return;

    if (!loggedIn) {
      _workspaceReady = true;
      _notifyIfActive();
      return;
    }

    if (isNewWorkspace) {
      final ok = await _initializeWorkspaceFromCloud();
      if (_isDisposed || epoch != _workspaceEpoch) return;
      _workspaceReady = ok;
      _notifyIfActive();
      return;
    }

    _workspaceReady = true;
    await _initialSyncAfterLogin();
    _notifyIfActive();
  }

  /// 新账号工作区首次初始化。
  ///
  /// 云端有数据时严格克隆；云端为空时只写空基线，绝不上传 guest 数据。
  /// 失败时保留 `baselineInitialized = false`，等待下次登录或手动同步重试。
  Future<bool> _initializeWorkspaceFromCloud() async {
    if (_isDisposed) return false;

    bool cloudHasData;
    try {
      cloudHasData = await _cloudSyncService.cloudHasAnyData();
    } catch (e) {
      logger.w('账号工作区初始化：检查云端数据失败，稍后重试', error: e);
      return false;
    }
    if (_isDisposed) return false;

    if (!cloudHasData) {
      _overwriteInProgress = true;
      try {
        final state = await _cloudSyncService.loadState();
        state.baselineInitialized = true;
        state.legacyUploaded = true;
        await _cloudSyncService.saveState();
        await _cloudSyncService.clearOutbox();
        _cloudDirty = false;
        return true;
      } catch (e) {
        logger.e('账号工作区空基线写入失败', error: e);
        return false;
      } finally {
        _overwriteInProgress = false;
      }
    }

    return _initializeLocalBaselineFromCloud();
  }

  /// 首次登录失败后，手动同步/回前台时重试工作区初始化。
  Future<bool> _retryWorkspaceInitialization() async {
    if (_workspaceReady) return true;
    final ok = await _initializeWorkspaceFromCloud();
    if (_isDisposed) return false;
    _workspaceReady = ok;
    _notifyIfActive();
    return ok;
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

    if (!syncState.legacyUploaded) {
      if (syncState.ownRollcallStats.isEmpty && history.isNotEmpty) {
        _ownRollcallStats = DrawStats.fromHistoryNames(
          history.map((r) => r.name),
        );
        _rollcallStats = DrawStats(_ownRollcallStats.toMap());
        syncState.ownRollcallStats
          ..clear()
          ..addAll(_ownRollcallStats.toMap());
      }
      await _cloudSyncService.enqueueAll(
        'rollcall',
        history.map((r) => r.toJson()),
      );
      syncState.legacyUploaded = true;
      await _cloudSyncService.saveState();
    }

    // 升级迁移：本地名单不是旧版默认 40 人占位，就视为用户数据，首次登录
    // 必须走并集合并，不能被云端空/新快照直接覆盖。
    if (!_studentsDirty &&
        _studentClock == 0 &&
        _allStudents.isNotEmpty &&
        !_isLegacyDefaultRoster(_allStudents)) {
      _studentsDirty = true;
      syncState.studentsDirty = true;
      await _cloudSyncService.saveState();
    }
  }

  bool _isLegacyDefaultRoster(List<Student> students) {
    if (students.length != 40) return false;
    for (var index = 0; index < 40; index++) {
      final id = index + 1;
      final student = students[index];
      if (student.id != id ||
          student.name != '学生 $id' ||
          student.gender != (index % 2 == 0 ? '男' : '女') ||
          student.group != '1' ||
          student.className != '1' ||
          !student.exist) {
        return false;
      }
    }
    return true;
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
    final syncState = await _cloudSyncService.loadState();
    final outbox = await _cloudSyncService.loadOutbox();
    if (_isDisposed || !_isLoggedIn) return;
    final hasBaseline = _hasLocalDataBaseline(syncState, localHistory, outbox);

    if (!cloudHasData) {
      // 云端为空：本地是唯一数据源，把完整本地历史与名单补传。
      await _enqueueAllLocalHistory(localHistory);
      if (_allStudents.isNotEmpty) {
        _studentsDirty = true;
        await _persistStudentSyncState();
      }
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
    SyncOutbox outbox,
  ) {
    if (history.isNotEmpty) return true;
    if (outbox.rollcall.isNotEmpty) return true;
    return state.baselineInitialized ||
        state.ownSeq.isNotEmpty ||
        state.clearedAt.isNotEmpty ||
        state.pulled.isNotEmpty ||
        state.ownRollcallStats.isNotEmpty ||
        state.studentsDirty ||
        state.studentClock > 0 ||
        state.studentTombstones.isNotEmpty ||
        state.clearsDirty ||
        state.clearedClasses.isNotEmpty;
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
  /// 点名历史与抽取统计全部以云端为准。随后重置同步状态：
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
      final cloudHistory = _filterHistoryByClears(
        snapshot.rollcallRecords
            .map((json) => HistoryRecord.fromJson(json))
            .toList(),
        snapshot.clearState,
      )..sort((a, b) => b.id.compareTo(a.id));

      // 先在内存/磁盘落地数据，全部成功后才重置同步状态（outbox/游标），
      // 保证"覆盖失败=本地不变"，不会清掉待上传队列。
      _allStudents = snapshot.students;
      _studentTombstones = Map<String, StudentTombstone>.from(
        snapshot.studentTombstones,
      );
      _studentClock = _maxStudentClock(
        _studentClock,
        snapshot.students,
        snapshot.studentTombstones,
      );
      _studentsDirty = false;
      _setLocalClears(snapshot.clearState);
      _clearsDirty = false;
      await _dataService.saveStudents(_allStudents);
      await _dataService.saveHistory(cloudHistory);
      _history = await _dataService.loadHistory();

      // 3. 统计：总视图=全部设备贡献求和；own=本机在云端的贡献
      _rollcallStats = _mergeStats(
        DrawStats(),
        snapshot.rollcallContributions.values,
      );
      _ownRollcallStats = DrawStats(
        snapshot.rollcallContributions[deviceId] ?? const {},
      );

      // 4. 同步状态一次性落盘（数据已成功写入，此时才清 outbox/游标）
      final state = await _cloudSyncService.loadState();
      final maxSeq = _maxOwnSeq(snapshot.rollcallRecords, deviceId);
      if (maxSeq > (state.ownSeq['rollcall'] ?? 0)) {
        state.ownSeq['rollcall'] = maxSeq;
      }
      state.ownRollcallStats
        ..clear()
        ..addAll(_ownRollcallStats.toMap());
      state.pulled.clear(); // 本地已等于云端，下次增量拉取按 uid 去重即可
      // 覆盖是"以云端为准"：清空文档同样以云端为准。
      state.studentClock = _studentClock;
      state.studentsDirty = false;
      state.studentTombstones
        ..clear()
        ..addAll(_studentTombstones);
      state.clearsDirty = false;
      snapshot.clearState.applyTo(state);
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
      final localHistory = await _ensureHistoryUids(
        await _dataService.loadHistory(),
      );
      final localStudents = _allStudents;
      final state = await _cloudSyncService.loadState();

      final snapshot = await _cloudSyncService.pullFullSnapshot();
      if (snapshot == null || _isDisposed) return false;

      final mergedClears = mergeClearStates(
        _localClearState(),
        snapshot.clearState,
      );

      final allCloudHistory = snapshot.rollcallRecords
          .map((json) => HistoryRecord.fromJson(json))
          .where((record) => record.uid != null && record.uid!.isNotEmpty)
          .toList();

      final cloudHistoryUids = allCloudHistory.map((r) => r.uid!).toSet();

      final visibleCloudHistory = _filterHistoryByClears(
        allCloudHistory,
        mergedClears,
      );
      final visibleLocalHistory = _filterHistoryByClears(
        localHistory,
        mergedClears,
      );

      final localOnlyHistory = visibleLocalHistory
          .where((record) => !cloudHistoryUids.contains(record.uid))
          .toList();

      final mergedHistory = <String, HistoryRecord>{
        for (final record in visibleCloudHistory) record.uid!: record,
        for (final record in visibleLocalHistory) record.uid!: record,
      }.values.toList()..sort((a, b) => b.drawTime.compareTo(a.drawTime));

      await _dataService.saveHistory(mergedHistory);
      _history = await _dataService.loadHistory();

      // 名单按 uid/修订合并；本地独有学生保留，随本次 push 上传。
      final studentMerge = mergeStudents(
        local: localStudents,
        localTombstones: _studentTombstones,
        cloud: snapshot.students,
        cloudTombstones: snapshot.studentTombstones,
        deviceId: deviceId,
        studentClock: _studentClock,
      );
      _studentClock = studentMerge.studentClock;
      _studentTombstones = Map<String, StudentTombstone>.from(
        studentMerge.tombstones,
      );
      _allStudents = studentMerge.students;
      if (studentMerge.changed) {
        await _dataService.saveStudents(_allStudents);
      }
      _studentsDirty = studentMerge.needsPush;
      _setLocalClears(mergedClears);
      _clearsDirty = !mergedClears.semanticallyEquals(snapshot.clearState);

      // 统计：云端总视图 + 本机贡献 max(本地, 云端)，保留本地独有记录贡献。
      final ownRollcall = DrawStats(
        snapshot.rollcallContributions[deviceId] ?? const {},
      )..mergeMax(_ownRollcallStats);
      _ownRollcallStats = ownRollcall;
      _rollcallStats = _mergeStats(
        _ownRollcallStats,
        snapshot.rollcallContributions.entries
            .where((entry) => entry.key != deviceId)
            .map((entry) => entry.value),
      );

      final maxSeq = _maxOwnSeq(snapshot.rollcallRecords, deviceId);
      if (maxSeq > (state.ownSeq['rollcall'] ?? 0)) {
        state.ownSeq['rollcall'] = maxSeq;
      }
      state.ownRollcallStats
        ..clear()
        ..addAll(_ownRollcallStats.toMap());
      state.pulled.clear();
      state.studentClock = _studentClock;
      state.studentsDirty = _studentsDirty;
      state.studentTombstones
        ..clear()
        ..addAll(_studentTombstones);
      state.clearsDirty = _clearsDirty;
      mergedClears.applyTo(state);
      state.legacyUploaded = true;
      state.baselineInitialized = true;
      await _cloudSyncService.saveState();

      // 云端已有的记录从 outbox 移除；本地独有记录补入 outbox。
      await _cloudSyncService.removeFromOutbox('rollcall', cloudHistoryUids);
      await _pruneOutboxByClears(mergedClears);
      await _cloudSyncService.enqueueAll(
        'rollcall',
        localOnlyHistory.map((record) => record.toJson()),
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

  /// 云端为空时，把完整本地历史补入 outbox。
  Future<void> _enqueueAllLocalHistory(List<HistoryRecord> history) async {
    final historyWithUid = await _ensureHistoryUids(history);
    _history = [...historyWithUid]
      ..sort((a, b) => b.drawTime.compareTo(a.drawTime));

    if (_ownRollcallStats.toMap().isEmpty && historyWithUid.isNotEmpty) {
      _ownRollcallStats = DrawStats.fromHistoryNames(
        historyWithUid.map((r) => r.name),
      );
      _rollcallStats = DrawStats(_ownRollcallStats.toMap());
    }

    await _cloudSyncService.enqueueAll(
      'rollcall',
      historyWithUid.map((record) => record.toJson()),
    );

    final state = await _cloudSyncService.loadState();
    state.ownRollcallStats
      ..clear()
      ..addAll(_ownRollcallStats.toMap());
    state.legacyUploaded = true;
    state.baselineInitialized = true;
    await _cloudSyncService.saveState();
  }

  /// 把本地独有的历史记录补传云端（导入、云备份恢复后调用）。
  ///
  /// 不覆盖本地数据；云端已有的记录按 uid 跳过。
  Future<bool> syncLocalHistoryToCloud() async {
    if (!_isLoggedIn || _isDisposed || _overwriteInProgress) return false;
    try {
      final history = await _ensureHistoryUids(
        await _dataService.loadHistory(),
      );
      _history = [...history]..sort((a, b) => b.drawTime.compareTo(a.drawTime));

      final snapshot = await _cloudSyncService.pullFullSnapshot();
      if (snapshot == null) {
        logger.w('补传本地历史失败：云端快照不完整');
        return false;
      }
      final cloudHistoryUids = snapshot.rollcallRecords
          .map((json) => ensureHistoryUid(json))
          .toSet();

      await _cloudSyncService.removeFromOutbox('rollcall', cloudHistoryUids);

      final missingHistory = history
          .where((record) => !cloudHistoryUids.contains(record.uid))
          .toList();
      await _cloudSyncService.enqueueAll(
        'rollcall',
        missingHistory.map((record) => record.toJson()),
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
    if (!_cloudSyncEnabled ||
        !_isLoggedIn ||
        _isDisposed ||
        _overwriteInProgress) {
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
    await _cloudSyncService.saveState();
  }

  /// 从云端拉取点名历史并合并到本地（新管线），返回新增条数
  Future<int> loadHistoryFromCloud({int limit = 500}) async {
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

  /// 推送：冲洗 outbox + own 统计贡献 + 学生名单（仅脏时）+ 清空文档（仅脏时）
  ///
  /// 未登录时静默跳过（不写 lastError）；覆盖进行中跳过，避免把半覆盖状态推上云。
  Future<bool> pushToCloud() async {
    if (!_isLoggedIn || _overwriteInProgress || !_workspaceReady) return false;
    var ok = true;
    try {
      ok = await _cloudSyncService.pushAll(
        ownRollcall: _ownRollcallStats.toMap(),
      );
      if (_studentsDirty) {
        ok = await _pushStudents() && ok;
      }
      if (_clearsDirty) {
        ok = await _pushClears() && ok;
      }
    } catch (e) {
      logger.w('推送云端失败', error: e);
      ok = false;
    }
    _notifyIfActive();
    return ok;
  }

  /// 先读云端 → 合并 → 写回学生名单；本地独有学生不会被整包覆盖。
  Future<bool> _pushStudents() async {
    if (!_studentsDirty) return true;
    try {
      final deviceId = await _cloudSyncService.resolveDeviceId();
      final result = await _cloudSyncService.syncStudents(
        local: _allStudents,
        localTombstones: _studentTombstones,
        deviceId: deviceId,
        clock: _studentClock,
      );
      if (_isDisposed) return false;

      _studentClock = result.studentClock;
      _studentTombstones = Map<String, StudentTombstone>.from(
        result.tombstones,
      );
      _allStudents = result.students;
      if (result.changed) {
        await _dataService.saveStudents(_allStudents);
        await _applyPulledStudents();
      }
      _studentsDirty = false;
      await _persistStudentSyncState();
      return true;
    } catch (e) {
      logger.w('学生名单同步失败，保留待推送标记', error: e);
      return false;
    }
  }

  Future<bool> _pushClears() async {
    if (!_clearsDirty) return true;
    try {
      final merged = await _cloudSyncService.syncClears(_localClearState());
      if (_isDisposed) return false;
      _setLocalClears(merged);
      _clearsDirty = false;
      await _persistClearSyncState();
      return true;
    } catch (e) {
      logger.w('清空文档同步失败，保留待推送标记', error: e);
      return false;
    }
  }

  /// 拉取并合并：历史按 uid 去重、统计贡献求和、名单云端优先
  ///
  /// 未登录时静默跳过（不写 lastError）；覆盖进行中跳过，避免与覆盖写盘交错。
  Future<bool> pullFromCloud() async {
    if (!_isLoggedIn || _overwriteInProgress || !_workspaceReady) return false;
    final future = _cloudSyncService.pullAll(
      existingUids: (kind) async {
        final records = await _dataService.loadHistory();
        return records.map((r) => r.uid ?? deriveLegacyHistoryUid(r)).toSet();
      },
      onNewRecord: (kind, json) async {
        final record = HistoryRecord.fromJson(json);
        await _dataService.addHistoryRecord(record);
        _history.add(record);
      },
    );
    _notifyIfActive();
    final result = await future;
    if (result == null) {
      _notifyIfActive();
      return false;
    }

    _lastPullNewRecords = result.newRecords;
    _rollcallStats = _mergeStats(
      _ownRollcallStats,
      result.rollcallContributions.values,
    );
    _history.sort((a, b) => b.id.compareTo(a.id));

    if (result.students.isNotEmpty || result.studentTombstones.isNotEmpty) {
      await _mergePulledStudents(result);
    }
    await _applyCloudClears(result.clearState);
    _notifyIfActive();
    return true;
  }

  List<HistoryRecord> _filterHistoryByClears(
    List<HistoryRecord> records,
    CloudClearState clears,
  ) => records.where((record) {
    final at = clears.rollcallClearedAt(record.className);
    if (at == null) return true;
    final time = DateTime.tryParse(record.drawTime);
    return time == null || !time.isBefore(at);
  }).toList();

  int _maxStudentClock(
    int current,
    List<Student> students,
    Map<String, StudentTombstone> tombstones,
  ) {
    var clock = current;
    for (final student in students) {
      if (student.rev > clock) clock = student.rev;
    }
    for (final tombstone in tombstones.values) {
      if (tombstone.rev > clock) clock = tombstone.rev;
    }
    return clock;
  }

  /// 把云端学生/墓碑与本地合并；本地独有学生保留并等待下一次推送。
  Future<void> _mergePulledStudents(PullResult result) async {
    final deviceId = await _cloudSyncService.resolveDeviceId();
    final merge = mergeStudents(
      local: _allStudents,
      localTombstones: _studentTombstones,
      cloud: result.students,
      cloudTombstones: result.studentTombstones,
      deviceId: deviceId,
      studentClock: _studentClock,
    );

    _studentClock = merge.studentClock;
    _studentTombstones = Map<String, StudentTombstone>.from(merge.tombstones);
    _allStudents = merge.students;
    if (merge.changed) {
      await _dataService.saveStudents(_allStudents);
      await _applyPulledStudents();
    }

    if (merge.needsPush) {
      _studentsDirty = true;
      _markCloudDirty();
    } else {
      _studentsDirty = false;
    }
    await _persistStudentSyncState();
  }

  /// 删除 outbox 中已被清空文档覆盖的记录。
  Future<void> _pruneOutboxByClears(CloudClearState clears) async {
    await _cloudSyncService.removeFromOutboxWhere('rollcall', (record) {
      final className = record['class_name']?.toString() ?? '1';
      final at = clears.rollcallClearedAt(className);
      if (at == null) return false;
      final time = DateTime.tryParse(record['draw_time']?.toString() ?? '');
      return time == null || time.isBefore(at);
    });
  }

  /// 应用云端清空文档：删除本地早于清空时间的记录，并清理同范围 outbox。
  Future<void> _applyCloudClears(CloudClearState cloud) async {
    final local = _localClearState();
    if (cloud.isEmpty && local.isEmpty) return;

    final merged = mergeClearStates(local, cloud);
    final needsPush = !merged.semanticallyEquals(cloud);
    _setLocalClears(merged);
    _clearsDirty = needsPush;
    final state = await _cloudSyncService.loadState();
    state.clearsDirty = needsPush;
    merged.applyTo(state);
    await _cloudSyncService.saveState();

    final keptHistory = _history.where((record) {
      final at = merged.rollcallClearedAt(record.className);
      if (at == null) return true;
      final time = DateTime.tryParse(record.drawTime);
      return time == null || !time.isBefore(at);
    }).toList();
    if (keptHistory.length != _history.length) {
      _history = keptHistory;
      await _dataService.saveHistory(_history);
    }

    await _pruneOutboxByClears(merged);
    if (needsPush) {
      _markCloudDirty();
    }
  }

  DrawStats _mergeStats(
    DrawStats own,
    Iterable<Map<String, int>> contributions,
  ) {
    final merged = DrawStats(own.toMap());
    for (final map in contributions) {
      merged.mergeSum(DrawStats(map));
    }
    return merged;
  }

  /// 立即同步：先拉后推
  Future<bool> syncNow() async {
    if (!_isLoggedIn || !_cloudSyncEnabled || _overwriteInProgress) {
      return false;
    }
    if (!_workspaceReady) {
      final initialized = await _retryWorkspaceInitialization();
      if (!initialized) return false;
    }
    final pulled = await pullFromCloud();
    if (!_canSync) {
      return pulled;
    }
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
      'history': (await _dataService.loadHistory())
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

    final students = _jsonMaps(
      snapshot['students'],
    ).map((e) => Student.fromJson(e)).toList();
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
