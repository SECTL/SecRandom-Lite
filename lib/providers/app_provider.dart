import 'package:flutter/material.dart';
import '../models/app_config.dart';
import '../models/history_record.dart';
import '../models/student.dart';
import '../services/data_service.dart';
import '../services/fair_draw_service.dart';
import '../services/random_service.dart';

class AppProvider with ChangeNotifier {
  final DataService _dataService = DataService();
  final RandomService _randomService = RandomService();
  final FairDrawService _fairDrawService = FairDrawService();

  List<Student> _allStudents = [];
  List<Student> _remainingStudents = [];
  List<Student> _currentSelection = [];
  List<HistoryRecord> _history = [];
  List<String> _groups = ['1'];
  Map<String, List<String>> _classGroups = {};

  bool _isRolling = false;
  bool _isDisposed = false;
  bool _isFinalizingRollCall = false;
  ThemeMode _themeMode = ThemeMode.system;
  AnimationMode _rollcallAnimationMode = AnimationMode.auto;
  AnimationMode _lotteryAnimationMode = AnimationMode.auto;
  int _rollCallSessionId = 0;

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

  AppProvider() {
    _loadData();
  }

  Future<void> _loadData() async {
    _allStudents = await _dataService.loadStudents();
    _history = await _dataService.loadHistory();

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
    await _dataService.saveConfig(config);
  }

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
    if (_groups.isEmpty) {
      _groups.add('1');
    }

    _allStudents.removeWhere((s) => s.className == className);
    await _dataService.saveStudents(_allStudents);
    _resetRemaining();

    _classGroups.remove(className);

    if (_selectedClass == className) {
      _selectedClass = _groups.first;
      _selectedGroup = null;
      _selectedGender = null;
    }

    await _saveConfig();
    notifyListeners();
  }

  void _resetRemaining() {
    _remainingStudents = List.from(_filteredStudents());
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
    _resetRemaining();
    notifyListeners();
  }

  Future<void> deleteStudentFromClass(String className, int id) async {
    _allStudents.removeWhere((s) => s.className == className && s.id == id);
    await _dataService.saveStudents(_allStudents);
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
    }
    await _dataService.clearHistoryRecords(className: className);
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

      final record = _buildRollCallRecord(className, picked);
      _history.insert(0, record);
      if (_history.length > 50) {
        _history.removeLast();
      }

      await _dataService.addHistoryRecord(record);
    } finally {
      if (activeSessionId == _rollCallSessionId) {
        _isRolling = false;
      }
      _isFinalizingRollCall = false;
      _notifyIfActive();
    }
  }

  List<Student> _pickRollCallStudents(String className) {
    final classHistory = _history
        .where((record) => record.className == className)
        .toList();
    final drawCandidates = _nonRepeatEnabled
        ? _remainingStudents
        : _filteredStudents();

    List<Student> picked;
    if (_fairDrawEnabled) {
      picked = _fairDrawService.draw(
        candidates: drawCandidates,
        classHistory: classHistory,
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

  HistoryRecord _buildRollCallRecord(String className, List<Student> picked) {
    final now = DateTime.now();
    final timeStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} "
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

    final newId = _history.isEmpty ? 1 : (_history.first.id + 1);
    final nameStr = picked.map((student) => student.name).join(',');

    return HistoryRecord(
      id: newId,
      name: nameStr,
      drawMethod: _fairDrawEnabled ? 2 : 1,
      drawTime: timeStr,
      drawPeopleNumbers: picked.length,
      drawGroup: _selectedGroup ?? '所有小组',
      drawGender: _selectedGender ?? '所有性别',
      className: className,
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
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




