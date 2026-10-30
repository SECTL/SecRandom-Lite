import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;
import '../models/student.dart';
import '../models/history_record.dart';
import '../models/app_config.dart';
import '../models/lottery_record.dart';
import '../utils/logger.dart';
import 'cloud/sync_identity.dart';

class DataService {
  /// 测试用：覆盖数据目录。
  ///
  /// 默认目录由 `Platform.resolvedExecutable` 推导，而 `flutter test` 下该值
  /// 指向 Flutter SDK 内部的测试引擎，于是所有测试文件共用同一个真实目录、
  /// 互相污染。测试在 setUp 里把它指向各自的临时目录即可隔离；置 null 回落
  /// 到默认推导，正常运行时不受影响。
  static String? debugDataDirOverride;

  static const String guestWorkspace = 'guest';
  static const String _dataDirName = 'data';
  static const String _accountsDirName = 'accounts';
  static const String _workspaceMarkerFileName = 'workspace.json';
  static const String _studentsFileName = 'students.json';
  static const String _historyFileName = 'history.json';
  static const String _syncStateFileName = 'sync_state.json';
  static const String _syncOutboxFileName = 'sync_outbox.json';
  static const String _configFileName = 'config.json';
  static const String _configLockFileName = 'config.lock';
  static const String _rootKey = 'class_name';
  static const String _configRootKey = 'config';

  static const List<String> _workspaceDataFileNames = [
    _studentsFileName,
    _historyFileName,
    _syncStateFileName,
    _syncOutboxFileName,
    _configFileName,
    'lottery_records.json',
  ];

  static String _currentWorkspace = guestWorkspace;

  static String get currentWorkspace => _currentWorkspace;

  static bool get _isWeb => kIsWeb;

  /// 账号工作区 key：只保留 userId 哈希前 24 位，不把邮箱/原始 ID 写进路径。
  static String workspaceKeyForUser(String userId) {
    final trimmed = userId.trim();
    if (trimmed.isEmpty) return guestWorkspace;
    final digest = sha256.convert(utf8.encode(trimmed)).toString();
    return 'acct_${digest.substring(0, 24)}';
  }

  static void setWorkspace(String key) {
    _validateWorkspaceKey(key);
    _currentWorkspace = key;
  }

  static void resetWorkspaceToGuest() {
    _currentWorkspace = guestWorkspace;
  }

  /// Web 存储 key：guest 保持旧版无前缀 key，账号使用 `<key>:` 前缀。
  static String webStorageKeyFor(String fileName, String workspace) {
    _validateWorkspaceKey(workspace);
    return workspace == guestWorkspace ? fileName : '$workspace:$fileName';
  }

  static void _validateWorkspaceKey(String key) {
    if (key == guestWorkspace) return;
    if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(key)) {
      throw ArgumentError.value(key, 'workspace', '非法工作区 key');
    }
  }

  static Future<bool> workspaceExists(String key) async {
    _validateWorkspaceKey(key);
    if (key == guestWorkspace) return true;

    if (_isWeb) {
      if (_getWebStorageRaw(webStorageKeyFor(_workspaceMarkerFileName, key)) !=
          null) {
        return true;
      }
      for (final name in _workspaceDataFileNames) {
        if (_getWebStorageRaw(webStorageKeyFor(name, key)) != null) {
          return true;
        }
      }
      return false;
    }

    final base = await _baseDataDirPath();
    if (base == null) return false;
    final dir = Directory(path.join(base, _accountsDirName, key));
    if (!await dir.exists()) return false;
    if (await File(path.join(dir.path, _workspaceMarkerFileName)).exists()) {
      return true;
    }
    for (final name in _workspaceDataFileNames) {
      if (await File(path.join(dir.path, name)).exists()) return true;
    }
    return false;
  }

  static Future<void> ensureWorkspace(String key) async {
    _validateWorkspaceKey(key);
    if (key == guestWorkspace) return;

    final marker = jsonEncode({
      'version': 1,
      'created_at': DateTime.now().toIso8601String(),
    });

    if (_isWeb) {
      final markerKey = webStorageKeyFor(_workspaceMarkerFileName, key);
      if (_getWebStorageRaw(markerKey) == null) {
        _setWebStorageRaw(markerKey, marker);
      }
      return;
    }

    final base = await _baseDataDirPath();
    if (base == null) {
      throw UnsupportedError('File system not available on web platform');
    }
    final dir = Directory(path.join(base, _accountsDirName, key));
    await dir.create(recursive: true);
    final markerFile = File(path.join(dir.path, _workspaceMarkerFileName));
    if (!await markerFile.exists()) {
      await markerFile.writeAsString(marker);
    }
  }

  static Future<String?> _baseDataDirPath() async {
    if (_isWeb) return null;

    final override = debugDataDirOverride;
    if (override != null) {
      final dataDir = Directory(override);
      if (!await dataDir.exists()) {
        await dataDir.create(recursive: true);
      }
      return dataDir.path;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      final appDocDir = await getApplicationDocumentsDirectory();
      final dataDir = Directory(path.join(appDocDir.path, _dataDirName));

      if (!await dataDir.exists()) {
        await dataDir.create(recursive: true);
      }
      return dataDir.path;
    } else if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      final String rootPath = path.dirname(Platform.resolvedExecutable);
      final dataDir = Directory(path.join(rootPath, _dataDirName));

      if (!await dataDir.exists()) {
        await dataDir.create(recursive: true);
      }
      return dataDir.path;
    } else {
      return null;
    }
  }

  Future<String?> _getDataDirPath([String? workspace]) async {
    if (_isWeb) return null;
    final base = await _baseDataDirPath();
    if (base == null) return null;
    final ws = workspace ?? _currentWorkspace;
    if (ws == guestWorkspace) return base;
    final dataDir = Directory(path.join(base, _accountsDirName, ws));
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }
    return dataDir.path;
  }

  static void _setWebStorageRaw(String key, String value) {
    if (_isWeb) {
      try {
        html.window.localStorage[key] = value;
      } catch (e) {
        logger.e('保存到localStorage失败', error: e);
      }
    }
  }

  static String? _getWebStorageRaw(String key) {
    if (_isWeb) {
      try {
        return html.window.localStorage[key];
      } catch (e) {
        logger.e('从localStorage读取失败', error: e);
        return null;
      }
    }
    return null;
  }

  void _setWebStorage(String key, String value) =>
      _setWebStorageRaw(key, value);

  String? _getWebStorage(String key) => _getWebStorageRaw(key);

  Future<Map<String, dynamic>> _readDataJson(String fileName) async {
    final ws = _currentWorkspace;
    try {
      if (!_isWeb) {
        final dirPath = await _getDataDirPath(ws);
        if (dirPath == null) return {};
        final file = File(path.join(dirPath, fileName));
        if (!await file.exists()) return {};
        final data = await file.readAsString();
        if (data.isEmpty) return {};
        return json.decode(data) as Map<String, dynamic>;
      }
      final data = _getWebStorage(webStorageKeyFor(fileName, ws));
      if (data == null || data.isEmpty) return {};
      return json.decode(data) as Map<String, dynamic>;
    } catch (e) {
      logger.e('读取 $fileName 失败', error: e);
      return {};
    }
  }

  Future<void> _writeDataJson(
    String fileName,
    Map<String, dynamic> data,
  ) async {
    final ws = _currentWorkspace;
    final encoded = const JsonEncoder.withIndent('  ').convert(data);
    if (!_isWeb) {
      final dirPath = await _getDataDirPath(ws);
      if (dirPath == null) {
        throw UnsupportedError('File system not available on web platform');
      }
      final file = File(path.join(dirPath, fileName));
      await file.writeAsString(encoded);
    } else {
      if (encoded.length > 1000000) {
        logger.w('$fileName 数据量较大 (${encoded.length} 字符)');
      }
      _setWebStorage(webStorageKeyFor(fileName, ws), encoded);
    }
  }

  Future<Map<String, dynamic>> loadSyncState() =>
      _readDataJson(_syncStateFileName);

  Future<void> saveSyncState(Map<String, dynamic> data) =>
      _writeDataJson(_syncStateFileName, data);

  Future<Map<String, dynamic>> loadSyncOutbox() =>
      _readDataJson(_syncOutboxFileName);

  Future<void> saveSyncOutbox(Map<String, dynamic> data) =>
      _writeDataJson(_syncOutboxFileName, data);

  Future<File> _getStudentsFile([String? workspace]) async {
    final dirPath = await _getDataDirPath(workspace);
    if (dirPath == null) {
      throw UnsupportedError('File system not available on web platform');
    }
    return File(path.join(dirPath, _studentsFileName));
  }

  Future<File> _getHistoryFile([String? workspace]) async {
    final dirPath = await _getDataDirPath(workspace);
    if (dirPath == null) {
      throw UnsupportedError('File system not available on web platform');
    }
    return File(path.join(dirPath, _historyFileName));
  }

  String _encodeConfig(AppConfig config) {
    final Map<String, dynamic> dataMap = {_configRootKey: config.toJson()};
    return const JsonEncoder.withIndent('  ').convert(dataMap);
  }

  Future<T> _withConfigFileLock<T>(
    Future<T> Function(String dirPath) action,
  ) async {
    final dirPath = await _getDataDirPath(_currentWorkspace);
    if (dirPath == null) {
      throw UnsupportedError('File system not available on web platform');
    }

    final lockFile = File(path.join(dirPath, _configLockFileName));
    final lockHandle = await lockFile.open(mode: FileMode.writeOnlyAppend);

    try {
      await lockHandle.lock(FileLock.exclusive);
      return await action(dirPath);
    } finally {
      await lockHandle.unlock();
      await lockHandle.close();
    }
  }

  Future<void> saveStudents(List<Student> students) async {
    final ws = _currentWorkspace;
    try {
      final Map<String, List<Map<String, dynamic>>> dataMap = {};
      for (final student in students) {
        final json = student.toJson();
        json.remove('class_name');
        (dataMap[student.className] ??= []).add(json);
      }
      final encoded = const JsonEncoder.withIndent('  ').convert(dataMap);

      if (!_isWeb) {
        final file = await _getStudentsFile(ws);
        await file.writeAsString(encoded);
      } else {
        if (encoded.length > 1000000) {
          logger.w('学生数据量较大 (${encoded.length} 字符)，可能影响性能');
        }
        _setWebStorage(webStorageKeyFor(_studentsFileName, ws), encoded);
      }
    } catch (e) {
      logger.e('保存学生数据失败', error: e);
      rethrow;
    }
  }

  Future<List<Student>> loadStudents() async {
    final ws = _currentWorkspace;
    try {
      String? data;
      if (!_isWeb) {
        final file = await _getStudentsFile(ws);
        if (!await file.exists()) return [];
        data = await file.readAsString();
      } else {
        data = _getWebStorage(webStorageKeyFor(_studentsFileName, ws));
      }
      if (data == null || data.isEmpty) return [];

      final Map<String, dynamic> jsonMap =
          json.decode(data) as Map<String, dynamic>;
      final List<Student> allStudents = [];

      if (jsonMap.containsKey(_rootKey)) {
        final jsonList = jsonMap[_rootKey];
        if (jsonList is List) {
          for (final json in jsonList) {
            if (json is Map<String, dynamic>) {
              final mutableJson = Map<String, dynamic>.from(json);
              mutableJson['class_name'] = '1';
              allStudents.add(Student.fromJson(mutableJson));
            }
          }
        }
      } else {
        jsonMap.forEach((className, studentsList) {
          if (studentsList is List) {
            for (final studentJson in studentsList) {
              if (studentJson is Map<String, dynamic>) {
                final mutableJson = Map<String, dynamic>.from(studentJson);
                mutableJson['class_name'] = className;
                allStudents.add(Student.fromJson(mutableJson));
              }
            }
          }
        });
      }

      var changed = false;
      final normalized = <Student>[];
      for (final student in allStudents) {
        if (student.uid.isEmpty) {
          normalized.add(
            student.copyWith(uid: deriveLegacyStudentUid(student)),
          );
          changed = true;
        } else {
          normalized.add(student);
        }
      }
      if (changed) await saveStudents(normalized);
      return normalized;
    } catch (e) {
      logger.e('读取学生数据失败', error: e);
      return [];
    }
  }

  // Helper method to get class names from students file without parsing everything
  Future<List<String>> loadClassNames() async {
    final ws = _currentWorkspace;
    try {
      String? data;
      if (!_isWeb) {
        final file = await _getStudentsFile(ws);
        if (!await file.exists()) return ['1'];
        data = await file.readAsString();
      } else {
        data = _getWebStorage(webStorageKeyFor(_studentsFileName, ws));
      }
      if (data == null || data.isEmpty) return ['1'];

      final Map<String, dynamic> jsonMap = json.decode(data);
      if (jsonMap.containsKey(_rootKey)) {
        return ['1'];
      }
      return jsonMap.keys.toList();
    } catch (e) {
      return ['1'];
    }
  }

  Future<void> saveHistory(List<HistoryRecord> history) async {
    final ws = _currentWorkspace;
    try {
      final Map<String, dynamic> dataMap = {};
      for (final record in history) {
        final className = record.className;
        (dataMap[className] ??= []).add(record.toJson());
      }
      final encoded = const JsonEncoder.withIndent('  ').convert(dataMap);

      if (!_isWeb) {
        final file = await _getHistoryFile(ws);
        await file.writeAsString(encoded);
      } else {
        if (encoded.length > 1000000) {
          logger.w('历史数据量较大 (${encoded.length} 字符)，可能影响性能');
        }
        _setWebStorage(webStorageKeyFor(_historyFileName, ws), encoded);
      }
    } catch (e) {
      logger.e('保存历史记录失败', error: e);
      rethrow;
    }
  }

  Future<List<HistoryRecord>> loadHistory() async {
    final ws = _currentWorkspace;
    try {
      String? data;
      if (!_isWeb) {
        final file = await _getHistoryFile(ws);
        if (!await file.exists()) return [];
        data = await file.readAsString();
      } else {
        data = _getWebStorage(webStorageKeyFor(_historyFileName, ws));
      }
      if (data == null || data.isEmpty) return [];

      final Map<String, dynamic> jsonMap = json.decode(data);
      final List<HistoryRecord> result = [];

      if (jsonMap.containsKey(_rootKey)) {
        final List<dynamic> jsonList = jsonMap[_rootKey];
        return jsonList.map((json) => HistoryRecord.fromJson(json)).toList();
      }

      for (final className in jsonMap.keys) {
        final List<dynamic> jsonList = jsonMap[className];
        for (final json in jsonList) {
          result.add(HistoryRecord.fromJson(json, className: className));
        }
      }

      return result;
    } catch (e) {
      return [];
    }
  }

  Future<void> addHistoryRecord(HistoryRecord record) async {
    final ws = _currentWorkspace;
    try {
      Map<String, dynamic> dataMap = {};
      if (!_isWeb) {
        final file = await _getHistoryFile(ws);
        if (await file.exists()) {
          final data = await file.readAsString();
          if (data.isNotEmpty) {
            try {
              dataMap = json.decode(data) as Map<String, dynamic>;
            } catch (e) {
              dataMap = {};
            }
          }
        }

        final className = record.className;
        (dataMap[className] ??= []).add(record.toJson());
        await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(dataMap),
        );
      } else {
        final existingData = _getWebStorage(
          webStorageKeyFor(_historyFileName, ws),
        );
        if (existingData != null && existingData.isNotEmpty) {
          try {
            dataMap = json.decode(existingData) as Map<String, dynamic>;
          } catch (e) {
            dataMap = {};
          }
        }

        final className = record.className;
        (dataMap[className] ??= []).add(record.toJson());
        final jsonData = const JsonEncoder.withIndent('  ').convert(dataMap);
        if (jsonData.length > 1000000) {
          logger.w('历史数据量较大 (${jsonData.length} 字符)，可能影响性能');
        }
        _setWebStorage(webStorageKeyFor(_historyFileName, ws), jsonData);
      }
    } catch (e) {
      logger.e('添加历史记录失败', error: e);
      rethrow;
    }
  }

  Future<void> clearHistoryRecords({String? className}) async {
    final ws = _currentWorkspace;
    try {
      if (!_isWeb) {
        final file = await _getHistoryFile(ws);
        if (className == null) {
          if (await file.exists()) {
            await file.writeAsString('{}');
          }
          return;
        }

        Map<String, dynamic> dataMap = {};
        if (await file.exists()) {
          final String data = await file.readAsString();
          if (data.isNotEmpty) {
            try {
              dataMap = json.decode(data) as Map<String, dynamic>;
            } catch (e) {
              dataMap = {};
            }
          }
        }

        dataMap.remove(className);
        await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(dataMap),
        );
      } else {
        final historyKey = webStorageKeyFor(_historyFileName, ws);
        if (className == null) {
          _setWebStorage(historyKey, '{}');
          return;
        }

        Map<String, dynamic> dataMap = {};
        final String? existingData = _getWebStorage(historyKey);
        if (existingData != null && existingData.isNotEmpty) {
          try {
            dataMap = json.decode(existingData) as Map<String, dynamic>;
          } catch (e) {
            dataMap = {};
          }
        }

        dataMap.remove(className);
        final String jsonData = const JsonEncoder.withIndent(
          '  ',
        ).convert(dataMap);
        if (jsonData.length > 1000000) {
          logger.w('历史数据量较大 (${jsonData.length} 字符)，可能影响性能');
        }
        _setWebStorage(historyKey, jsonData);
      }
    } catch (e) {
      logger.e('清除历史记录失败', error: e);
      rethrow;
    }
  }

  Future<void> saveConfig(AppConfig config) async {
    final ws = _currentWorkspace;
    try {
      if (!_isWeb) {
        final encodedConfig = _encodeConfig(config);
        await _withConfigFileLock((dirPath) async {
          final file = File(path.join(dirPath, _configFileName));
          await file.writeAsString(encodedConfig);
        });
      } else {
        final String jsonData = _encodeConfig(config);
        if (jsonData.length > 1000000) {
          logger.w('配置数据量较大 (${jsonData.length} 字符)，可能影响性能');
        }
        _setWebStorage(webStorageKeyFor(_configFileName, ws), jsonData);
      }
    } catch (e) {
      logger.e('保存配置失败', error: e);
      rethrow;
    }
  }

  Future<AppConfig> loadConfig() async {
    final ws = _currentWorkspace;
    try {
      if (!_isWeb) {
        return await _withConfigFileLock((dirPath) async {
          final file = File(path.join(dirPath, _configFileName));
          if (!await file.exists()) {
            final defaultConfig = AppConfig.defaultConfig();
            await file.writeAsString(_encodeConfig(defaultConfig));
            return defaultConfig;
          }

          final String data = await file.readAsString();
          if (data.isEmpty) return AppConfig.defaultConfig();

          final Map<String, dynamic> jsonMap = json.decode(data);
          if (jsonMap.containsKey(_configRootKey)) {
            return AppConfig.fromJson(jsonMap[_configRootKey]);
          }

          return AppConfig.defaultConfig();
        });
      } else {
        final String? jsonData = _getWebStorage(
          webStorageKeyFor(_configFileName, ws),
        );
        if (jsonData == null || jsonData.isEmpty) {
          final defaultConfig = AppConfig.defaultConfig();
          await saveConfig(defaultConfig);
          return defaultConfig;
        }

        final Map<String, dynamic> jsonMap = json.decode(jsonData);
        if (jsonMap.containsKey(_configRootKey)) {
          return AppConfig.fromJson(jsonMap[_configRootKey]);
        }

        return AppConfig.defaultConfig();
      }
    } catch (e) {
      return AppConfig.defaultConfig();
    }
  }

  Future<void> savePrizePoolData(
    String poolName,
    Map<String, dynamic> poolData,
  ) async {
    final ws = _currentWorkspace;
    try {
      final jsonData = const JsonEncoder.withIndent('  ').convert(poolData);
      if (!_isWeb) {
        final file = await _getPrizeFile(poolName, ws);
        await file.writeAsString(jsonData);
      } else {
        if (jsonData.length > 1000000) {
          logger.w('奖池数据量较大 (${jsonData.length} 字符)，可能影响性能');
        }
        _setWebStorage(webStorageKeyFor('prize_$poolName.json', ws), jsonData);
      }
    } catch (e) {
      logger.e('保存奖池数据失败', error: e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> loadPrizePoolData(String poolName) async {
    final ws = _currentWorkspace;
    try {
      if (!_isWeb) {
        final file = await _getPrizeFile(poolName, ws);
        if (!await file.exists()) {
          return {};
        }
        final String data = await file.readAsString();
        if (data.isEmpty) return {};

        return json.decode(data) as Map<String, dynamic>;
      } else {
        final String? jsonData = _getWebStorage(
          webStorageKeyFor('prize_$poolName.json', ws),
        );
        if (jsonData == null || jsonData.isEmpty) {
          return {};
        }

        return json.decode(jsonData) as Map<String, dynamic>;
      }
    } catch (e) {
      logger.e('加载奖池数据失败', error: e);
      return {};
    }
  }

  Future<void> deletePrizePoolData(String poolName) async {
    final ws = _currentWorkspace;
    try {
      if (!_isWeb) {
        final file = await _getPrizeFile(poolName, ws);
        if (await file.exists()) {
          await file.delete();
        }
      } else {
        _setWebStorage(webStorageKeyFor('prize_$poolName.json', ws), '');
      }
    } catch (e) {
      logger.e('删除奖池数据失败', error: e);
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> loadAllPrizePools() async {
    final ws = _currentWorkspace;
    try {
      if (!_isWeb) {
        final dirPath = await _getDataDirPath(ws);
        if (dirPath == null) {
          return [];
        }

        final dir = Directory(dirPath);
        if (!await dir.exists()) {
          return [];
        }

        final List<Map<String, dynamic>> pools = [];
        await for (var entity in dir.list()) {
          if (entity is File) {
            final file = entity;
            final fileName = file.path.split(Platform.pathSeparator).last;
            if (fileName.startsWith('prize_') && fileName.endsWith('.json')) {
              try {
                final data = await file.readAsString();
                if (data.isNotEmpty) {
                  final poolData = json.decode(data) as Map<String, dynamic>;
                  pools.add(poolData);
                }
              } catch (e) {
                logger.e('加载奖池文件失败: $fileName', error: e);
              }
            }
          }
        }

        return pools;
      } else {
        final List<Map<String, dynamic>> pools = [];
        try {
          final prefix = ws == guestWorkspace ? 'prize_' : '$ws:prize_';
          final storage = html.window.localStorage;
          for (int i = 0; i < storage.length; i++) {
            final key = storage.keys.elementAt(i);
            if (key.startsWith(prefix) && key.endsWith('.json')) {
              try {
                final jsonData = storage[key];
                if (jsonData != null && jsonData.isNotEmpty) {
                  final poolData =
                      json.decode(jsonData) as Map<String, dynamic>;
                  pools.add(poolData);
                }
              } catch (e) {
                logger.e('加载奖池数据失败: $key', error: e);
              }
            }
          }
        } catch (e) {
          logger.e('从localStorage加载奖池数据失败', error: e);
        }

        return pools;
      }
    } catch (e) {
      logger.e('加载所有奖池数据失败', error: e);
      return [];
    }
  }

  Future<File> _getPrizeFile(String poolName, [String? workspace]) async {
    final dirPath = await _getDataDirPath(workspace);
    if (dirPath == null) {
      throw UnsupportedError('File system not available on web platform');
    }
    return File(path.join(dirPath, 'prize_$poolName.json'));
  }

  Future<void> addLotteryRecord(LotteryRecord record) async {
    try {
      final dataMap = await _readDataJson('lottery_records.json');
      (dataMap[record.poolName] ??= <dynamic>[]).add(record.toJson());
      await _writeDataJson('lottery_records.json', dataMap);
    } catch (e) {
      logger.e('添加抽奖记录失败', error: e);
      rethrow;
    }
  }

  Future<List<LotteryRecord>> loadLotteryRecords() async {
    try {
      final jsonMap = await _readDataJson('lottery_records.json');
      final List<LotteryRecord> result = [];
      for (final poolName in jsonMap.keys) {
        final jsonList = jsonMap[poolName];
        if (jsonList is List) {
          for (final json in jsonList) {
            if (json is Map<String, dynamic>) {
              result.add(LotteryRecord.fromJson(json));
            }
          }
        }
      }
      return result;
    } catch (e) {
      logger.e('加载抽奖记录失败', error: e);
      return [];
    }
  }

  /// 整体覆写抽奖记录（uid 迁移/合并后落盘）
  Future<void> saveLotteryRecords(List<LotteryRecord> records) async {
    final dataMap = <String, dynamic>{};
    for (final record in records) {
      (dataMap[record.poolName] ??= <dynamic>[]).add(record.toJson());
    }
    await _writeDataJson('lottery_records.json', dataMap);
  }

  Future<void> clearLotteryRecords(String poolName) async {
    try {
      final dataMap = await _readDataJson('lottery_records.json');
      dataMap.remove(poolName);
      await _writeDataJson('lottery_records.json', dataMap);
    } catch (e) {
      logger.e('清除抽奖记录失败', error: e);
      rethrow;
    }
  }

  Future<void> clearAllLotteryRecords() async {
    try {
      await _writeDataJson('lottery_records.json', {});
    } catch (e) {
      logger.e('清除所有抽奖记录失败', error: e);
      rethrow;
    }
  }
}
