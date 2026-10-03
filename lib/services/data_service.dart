import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;
import '../models/student.dart';
import '../models/history_record.dart';
import '../models/app_config.dart';
import '../models/lottery_record.dart';
import '../utils/logger.dart';

class DataService {
  static const String _dataDirName = 'data';
  static const String _studentsFileName = 'students.json';
  static const String _historyFileName = 'history.json';
  static const String _syncStateFileName = 'sync_state.json';
  static const String _syncOutboxFileName = 'sync_outbox.json';
  static const String _configFileName = 'config.json';
  static const String _configLockFileName = 'config.lock';
  static const String _rootKey = 'class_name';
  static const String _configRootKey = 'config';

  static bool get _isWeb => kIsWeb;

  Future<String?> _getDataDirPath() async {
    if (_isWeb) {
      return null;
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

  void _setWebStorage(String key, String value) {
    if (_isWeb) {
      try {
        html.window.localStorage[key] = value;
      } catch (e) {
        logger.e('保存到localStorage失败', error: e);
      }
    }
  }

  String? _getWebStorage(String key) {
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

  Future<Map<String, dynamic>> _readDataJson(String fileName) async {
    try {
      if (!_isWeb) {
        final dirPath = await _getDataDirPath();
        if (dirPath == null) return {};
        final file = File(path.join(dirPath, fileName));
        if (!await file.exists()) return {};
        final data = await file.readAsString();
        if (data.isEmpty) return {};
        return json.decode(data) as Map<String, dynamic>;
      }
      final data = _getWebStorage(fileName);
      if (data == null || data.isEmpty) return {};
      return json.decode(data) as Map<String, dynamic>;
    } catch (e) {
      logger.e('读取 $fileName 失败', error: e);
      return {};
    }
  }

  Future<void> _writeDataJson(String fileName, Map<String, dynamic> data) async {
    final encoded = const JsonEncoder.withIndent('  ').convert(data);
    if (!_isWeb) {
      final dirPath = await _getDataDirPath();
      if (dirPath == null) {
        throw UnsupportedError('File system not available on web platform');
      }
      final file = File(path.join(dirPath, fileName));
      await file.writeAsString(encoded);
    } else {
      if (encoded.length > 1000000) {
        logger.w('$fileName 数据量较大 (${encoded.length} 字符)');
      }
      _setWebStorage(fileName, encoded);
    }
  }

  Future<Map<String, dynamic>> loadSyncState() => _readDataJson(_syncStateFileName);

  Future<void> saveSyncState(Map<String, dynamic> data) =>
      _writeDataJson(_syncStateFileName, data);

  Future<Map<String, dynamic>> loadSyncOutbox() => _readDataJson(_syncOutboxFileName);

  Future<void> saveSyncOutbox(Map<String, dynamic> data) =>
      _writeDataJson(_syncOutboxFileName, data);

  Future<File> _getStudentsFile() async {
    final dirPath = await _getDataDirPath();
    if (dirPath == null) {
      throw UnsupportedError('File system not available on web platform');
    }
    return File(path.join(dirPath, _studentsFileName));
  }

  Future<File> _getHistoryFile() async {
    final dirPath = await _getDataDirPath();
    if (dirPath == null) {
      throw UnsupportedError('File system not available on web platform');
    }
    return File(path.join(dirPath, _historyFileName));
  }

  String _encodeConfig(AppConfig config) {
    final Map<String, dynamic> dataMap = {
      _configRootKey: config.toJson(),
    };
    return const JsonEncoder.withIndent('  ').convert(dataMap);
  }

  Future<T> _withConfigFileLock<T>(Future<T> Function(String dirPath) action) async {
    final dirPath = await _getDataDirPath();
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
    try {
      if (!_isWeb) {
        final file = await _getStudentsFile();
        
        final Map<String, List<Map<String, dynamic>>> dataMap = {};
        
        for (var student in students) {
          if (!dataMap.containsKey(student.className)) {
            dataMap[student.className] = [];
          }
          final json = student.toJson();
          json.remove('class_name'); 
          dataMap[student.className]!.add(json);
        }

        final String data = const JsonEncoder.withIndent('  ').convert(dataMap);
        await file.writeAsString(data);
      } else {
        final Map<String, dynamic> dataMap = {};
        
        for (var student in students) {
          if (!dataMap.containsKey(student.className)) {
            dataMap[student.className] = [];
          }
          final json = student.toJson();
          json.remove('class_name'); 
          if (dataMap[student.className] is! List) {
            dataMap[student.className] = [];
          }
          (dataMap[student.className] as List).add(json);
        }
        
        final String jsonData = const JsonEncoder.withIndent('  ').convert(dataMap);
        
        if (jsonData.length > 1000000) {
          logger.w('学生数据量较大 (${jsonData.length} 字符)，可能影响性能');
        }
        
        _setWebStorage(_studentsFileName, jsonData);
      }
    } catch (e) {
      logger.e('保存学生数据失败', error: e);
      rethrow;
    }
  }

  Future<List<Student>> loadStudents() async {
    try {
      if (!_isWeb) {
        final file = await _getStudentsFile();
        if (!await file.exists()) {
          final initialData = _getInitialStudents();
          await saveStudents(initialData); 
          return initialData;
        }
        final String data = await file.readAsString();
        if (data.isEmpty) {
          final initialData = _getInitialStudents();
          await saveStudents(initialData);
          return initialData;
        }
        
        final Map<String, dynamic> jsonMap = json.decode(data);
        final List<Student> allStudents = [];

        if (jsonMap.containsKey(_rootKey)) {
          final List<dynamic> jsonList = jsonMap[_rootKey];
          return jsonList.map((json) {
              if (json is Map<String, dynamic>) {
                  json['class_name'] = '1';
              }
              return Student.fromJson(json);
          }).toList();
        }

        jsonMap.forEach((className, studentsList) {
          if (studentsList is List) {
            for (var studentJson in studentsList) {
              if (studentJson is Map<String, dynamic>) {
                 final mutableJson = Map<String, dynamic>.from(studentJson);
                 mutableJson['class_name'] = className;
                 allStudents.add(Student.fromJson(mutableJson));
              }
            }
          }
        });
        
        if (allStudents.isEmpty) {
          final initialData = _getInitialStudents();
          await saveStudents(initialData);
          return initialData;
        }
        
        return allStudents;
      } else {
        final String? jsonData = _getWebStorage(_studentsFileName);
        if (jsonData == null || jsonData.isEmpty) {
          final initialData = _getInitialStudents();
          await saveStudents(initialData);
          return initialData;
        }
        
        final Map<String, dynamic> jsonMap = json.decode(jsonData);
        final List<Student> allStudents = [];

        if (jsonMap.containsKey(_rootKey)) {
          final List<dynamic> jsonList = jsonMap[_rootKey];
          return jsonList.map((json) {
              if (json is Map<String, dynamic>) {
                  json['class_name'] = '1';
              }
              return Student.fromJson(json);
          }).toList();
        }

        jsonMap.forEach((className, studentsList) {
          if (studentsList is List) {
            for (var studentJson in studentsList) {
              if (studentJson is Map<String, dynamic>) {
                 final mutableJson = Map<String, dynamic>.from(studentJson);
                 mutableJson['class_name'] = className;
                 allStudents.add(Student.fromJson(mutableJson));
              }
            }
          }
        });
        
        if (allStudents.isEmpty) {
          final initialData = _getInitialStudents();
          await saveStudents(initialData);
          return initialData;
        }
        
        return allStudents;
      }
    } catch (e) {
      return _getInitialStudents();
    }
  }

  // Helper method to get class names from students file without parsing everything
  Future<List<String>> loadClassNames() async {
     try {
      if (!_isWeb) {
        final file = await _getStudentsFile();
        if (!await file.exists()) {
          return ['1'];
        }
        final String data = await file.readAsString();
        if (data.isEmpty) return ['1'];
        
        final Map<String, dynamic> jsonMap = json.decode(data);
        if (jsonMap.containsKey(_rootKey)) {
          return ['1'];
        }
        
        return jsonMap.keys.toList();
      } else {
        final String? jsonData = _getWebStorage(_studentsFileName);
        if (jsonData == null || jsonData.isEmpty) {
          return ['1'];
        }
        
        final Map<String, dynamic> jsonMap = json.decode(jsonData);
        if (jsonMap.containsKey(_rootKey)) {
          return ['1'];
        }
        
        return jsonMap.keys.toList();
      }
    } catch (e) {
      return ['1'];
    }
  }

  Future<void> saveHistory(List<HistoryRecord> history) async {
    try {
      if (!_isWeb) {
        final file = await _getHistoryFile();
        final Map<String, dynamic> dataMap = {};
        
        for (var record in history) {
          final className = record.className;
          if (!dataMap.containsKey(className)) {
            dataMap[className] = [];
          }
          (dataMap[className] as List).add(record.toJson());
        }
        
        await file.writeAsString(const JsonEncoder.withIndent('  ').convert(dataMap));
      } else {
        final Map<String, dynamic> dataMap = {};
        
        for (var record in history) {
          final className = record.className;
          if (!dataMap.containsKey(className)) {
            dataMap[className] = [];
          }
          (dataMap[className] as List).add(record.toJson());
        }
        
        final String jsonData = const JsonEncoder.withIndent('  ').convert(dataMap);
        
        if (jsonData.length > 1000000) {
          logger.w('历史数据量较大 (${jsonData.length} 字符)，可能影响性能');
        }
        
        _setWebStorage(_historyFileName, jsonData);
      }
    } catch (e) {
      logger.e('保存历史记录失败', error: e);
      rethrow;
    }
  }

  Future<List<HistoryRecord>> loadHistory() async {
    try {
      if (!_isWeb) {
        final file = await _getHistoryFile();
        if (!await file.exists()) {
          return [];
        }
        final String data = await file.readAsString();
        if (data.isEmpty) return [];
        
        final Map<String, dynamic> jsonMap = json.decode(data);
        final List<HistoryRecord> result = [];
        
        if (jsonMap.containsKey(_rootKey)) {
          final List<dynamic> jsonList = jsonMap[_rootKey];
          return jsonList.map((json) => HistoryRecord.fromJson(json)).toList();
        }
        
        for (var className in jsonMap.keys) {
          final List<dynamic> jsonList = jsonMap[className];
          for (var json in jsonList) {
            result.add(HistoryRecord.fromJson(json, className: className));
          }
        }
        
        return result;
      } else {
        final String? jsonData = _getWebStorage(_historyFileName);
        if (jsonData == null || jsonData.isEmpty) {
          return [];
        }
        
        final Map<String, dynamic> jsonMap = json.decode(jsonData);
        final List<HistoryRecord> result = [];
        
        if (jsonMap.containsKey(_rootKey)) {
          final List<dynamic> jsonList = jsonMap[_rootKey];
          return jsonList.map((json) => HistoryRecord.fromJson(json)).toList();
        }
        
        for (var className in jsonMap.keys) {
          final List<dynamic> jsonList = jsonMap[className];
          for (var json in jsonList) {
            result.add(HistoryRecord.fromJson(json, className: className));
          }
        }
        
        return result;
      }
    } catch (e) {
      return [];
    }
  }

  Future<void> addHistoryRecord(HistoryRecord record) async {
    try {
      if (!_isWeb) {
        final file = await _getHistoryFile();
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
        
        final className = record.className;
        if (!dataMap.containsKey(className)) {
          dataMap[className] = [];
        }
        (dataMap[className] as List).add(record.toJson());
        
        await file.writeAsString(const JsonEncoder.withIndent('  ').convert(dataMap));
      } else {
        Map<String, dynamic> dataMap = {};
        
        final String? existingData = _getWebStorage(_historyFileName);
        if (existingData != null && existingData.isNotEmpty) {
          try {
            dataMap = json.decode(existingData) as Map<String, dynamic>;
          } catch (e) {
            dataMap = {};
          }
        }
        
        final className = record.className;
        if (!dataMap.containsKey(className)) {
          dataMap[className] = [];
        }
        (dataMap[className] as List).add(record.toJson());
        
        final String jsonData = const JsonEncoder.withIndent('  ').convert(dataMap);
        
        if (jsonData.length > 1000000) {
          logger.w('历史数据量较大 (${jsonData.length} 字符)，可能影响性能');
        }
        
        _setWebStorage(_historyFileName, jsonData);
      }
    } catch (e) {
      logger.e('添加历史记录失败', error: e);
      rethrow;
    }
  }

  Future<void> clearHistoryRecords({String? className}) async {
    try {
      if (!_isWeb) {
        final file = await _getHistoryFile();
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
        await file.writeAsString(const JsonEncoder.withIndent('  ').convert(dataMap));
      } else {
        if (className == null) {
          _setWebStorage(_historyFileName, '{}');
          return;
        }

        Map<String, dynamic> dataMap = {};
        final String? existingData = _getWebStorage(_historyFileName);
        if (existingData != null && existingData.isNotEmpty) {
          try {
            dataMap = json.decode(existingData) as Map<String, dynamic>;
          } catch (e) {
            dataMap = {};
          }
        }

        dataMap.remove(className);
        final String jsonData = const JsonEncoder.withIndent('  ').convert(dataMap);

        if (jsonData.length > 1000000) {
          logger.w('历史数据量较大 (${jsonData.length} 字符)，可能影响性能');
        }

        _setWebStorage(_historyFileName, jsonData);
      }
    } catch (e) {
      logger.e('清除历史记录失败', error: e);
      rethrow;
    }
  }

  Future<void> saveConfig(AppConfig config) async {
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
        
        _setWebStorage(_configFileName, jsonData);
      }
    } catch (e) {
      logger.e('保存配置失败', error: e);
      rethrow;
    }
  }

  Future<AppConfig> loadConfig() async {
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
        final String? jsonData = _getWebStorage(_configFileName);
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

  List<Student> _getInitialStudents() {
    return List.generate(40, (index) {
      return Student(
        id: index + 1,
        name: '学生 ${index + 1}',
        gender: index % 2 == 0 ? '男' : '女',
        group: '1',
        className: '1', // Default class
        exist: true,
      );
    });
  }

  Future<void> savePrizePoolData(String poolName, Map<String, dynamic> poolData) async {
    try {
      if (!_isWeb) {
        final file = await _getPrizeFile(poolName);
        await file.writeAsString(const JsonEncoder.withIndent('  ').convert(poolData));
      } else {
        final String jsonData = const JsonEncoder.withIndent('  ').convert(poolData);
        
        if (jsonData.length > 1000000) {
          logger.w('奖池数据量较大 (${jsonData.length} 字符)，可能影响性能');
        }
        
        _setWebStorage('prize_$poolName.json', jsonData);
      }
    } catch (e) {
      logger.e('保存奖池数据失败', error: e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> loadPrizePoolData(String poolName) async {
    try {
      if (!_isWeb) {
        final file = await _getPrizeFile(poolName);
        if (!await file.exists()) {
          return {};
        }
        final String data = await file.readAsString();
        if (data.isEmpty) return {};
        
        return json.decode(data) as Map<String, dynamic>;
      } else {
        final String? jsonData = _getWebStorage('prize_$poolName.json');
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
    try {
      if (!_isWeb) {
        final file = await _getPrizeFile(poolName);
        if (await file.exists()) {
          await file.delete();
        }
      } else {
        _setWebStorage('prize_$poolName.json', '');
      }
    } catch (e) {
      logger.e('删除奖池数据失败', error: e);
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> loadAllPrizePools() async {
    try {
      if (!_isWeb) {
        final dirPath = await _getDataDirPath();
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
          final storage = html.window.localStorage;
          for (int i = 0; i < storage.length; i++) {
            final key = storage.keys.elementAt(i);
            if (key.startsWith('prize_') && key.endsWith('.json')) {
              try {
                final jsonData = storage[key];
                if (jsonData != null && jsonData.isNotEmpty) {
                  final poolData = json.decode(jsonData) as Map<String, dynamic>;
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

  Future<File> _getPrizeFile(String poolName) async {
    final dirPath = await _getDataDirPath();
    if (dirPath == null) {
      throw UnsupportedError('File system not available on web platform');
    }
    return File(path.join(dirPath, 'prize_$poolName.json'));
  }

  Future<void> addLotteryRecord(LotteryRecord record) async {
    try {
      if (!_isWeb) {
        final file = await _getLotteryRecordsFile();
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
        
        final poolName = record.poolName;
        if (!dataMap.containsKey(poolName)) {
          dataMap[poolName] = [];
        }
        (dataMap[poolName] as List).add(record.toJson());
        
        await file.writeAsString(const JsonEncoder.withIndent('  ').convert(dataMap));
      } else {
        Map<String, dynamic> dataMap = {};
        
        final String? existingData = _getWebStorage('lottery_records.json');
        if (existingData != null && existingData.isNotEmpty) {
          try {
            dataMap = json.decode(existingData) as Map<String, dynamic>;
          } catch (e) {
            dataMap = {};
          }
        }
        
        final poolName = record.poolName;
        if (!dataMap.containsKey(poolName)) {
          dataMap[poolName] = [];
        }
        (dataMap[poolName] as List).add(record.toJson());
        
        final String jsonData = const JsonEncoder.withIndent('  ').convert(dataMap);
        
        if (jsonData.length > 1000000) {
          logger.w('抽奖记录数据量较大 (${jsonData.length} 字符)，可能影响性能');
        }
        
        _setWebStorage('lottery_records.json', jsonData);
      }
    } catch (e) {
      logger.e('添加抽奖记录失败', error: e);
      rethrow;
    }
  }

  Future<List<LotteryRecord>> loadLotteryRecords() async {
    try {
      if (!_isWeb) {
        final file = await _getLotteryRecordsFile();
        if (!await file.exists()) {
          return [];
        }
        final String data = await file.readAsString();
        if (data.isEmpty) return [];
        
        final Map<String, dynamic> jsonMap = json.decode(data);
        final List<LotteryRecord> result = [];
        
        for (var poolName in jsonMap.keys) {
          final List<dynamic> jsonList = jsonMap[poolName];
          for (var json in jsonList) {
            result.add(LotteryRecord.fromJson(json));
          }
        }
        
        return result;
      } else {
        final String? jsonData = _getWebStorage('lottery_records.json');
        if (jsonData == null || jsonData.isEmpty) {
          return [];
        }
        
        final Map<String, dynamic> jsonMap = json.decode(jsonData);
        final List<LotteryRecord> result = [];
        
        for (var poolName in jsonMap.keys) {
          final List<dynamic> jsonList = jsonMap[poolName];
          for (var json in jsonList) {
            result.add(LotteryRecord.fromJson(json));
          }
        }
        
        return result;
      }
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
      if (!_isWeb) {
        final file = await _getLotteryRecordsFile();
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
        
        dataMap.remove(poolName);
        await file.writeAsString(const JsonEncoder.withIndent('  ').convert(dataMap));
      } else {
        Map<String, dynamic> dataMap = {};
        
        final String? existingData = _getWebStorage('lottery_records.json');
        if (existingData != null && existingData.isNotEmpty) {
          try {
            dataMap = json.decode(existingData) as Map<String, dynamic>;
          } catch (e) {
            dataMap = {};
          }
        }
        
        dataMap.remove(poolName);
        
        final String jsonData = const JsonEncoder.withIndent('  ').convert(dataMap);
        
        if (jsonData.length > 1000000) {
          logger.w('抽奖记录数据量较大 (${jsonData.length} 字符)，可能影响性能');
        }
        
        _setWebStorage('lottery_records.json', jsonData);
      }
    } catch (e) {
      logger.e('清除抽奖记录失败', error: e);
      rethrow;
    }
  }

  Future<void> clearAllLotteryRecords() async {
    try {
      if (!_isWeb) {
        final file = await _getLotteryRecordsFile();
        if (await file.exists()) {
          await file.writeAsString('{}');
        }
      } else {
        _setWebStorage('lottery_records.json', '{}');
      }
    } catch (e) {
      logger.e('清除所有抽奖记录失败', error: e);
      rethrow;
    }
  }

  Future<File> _getLotteryRecordsFile() async {
    final dirPath = await _getDataDirPath();
    if (dirPath == null) {
      throw UnsupportedError('File system not available on web platform');
    }
    return File(path.join(dirPath, 'lottery_records.json'));
  }
}
