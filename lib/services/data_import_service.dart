import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../models/history_record.dart';
import '../models/lottery_record.dart';
import '../models/app_config.dart';
import '../models/student.dart';
import '../models/prize.dart';
import '../models/prize_pool.dart';
import 'data_service.dart';
import 'lottery_service.dart';

/// 合并策略
enum MergeStrategy {
  merge,    // 合并：保留已有数据，添加新数据（不覆盖重复项）
  overwrite, // 覆盖：用导入的数据完全替换原有数据
  cancel,   // 取消：不导入，保留原有数据
}

/// 冲突类型
enum ConflictType {
  history,   // 点名历史
  lottery,   // 抽奖历史
  students,  // 学生名单
  prizes,    // 奖品名单
}

/// 班级学生信息
class ClassStudentInfo {
  final String className;
  final int existingCount;
  final int importCount;

  ClassStudentInfo({
    required this.className,
    required this.existingCount,
    required this.importCount,
  });
}

/// 冲突信息
class ConflictInfo {
  final ConflictType type;
  final String? poolName; // 仅奖品冲突时使用
  final int existingCount;
  final int importCount;
  final List<ClassStudentInfo>? classStudents; // 仅学生冲突时使用，按班级分组

  ConflictInfo({
    required this.type,
    this.poolName,
    required this.existingCount,
    required this.importCount,
    this.classStudents,
  });

  bool get hasConflict => existingCount > 0;

  String get description {
    switch (type) {
      case ConflictType.history:
        return '已有 $existingCount 条，导入 $importCount 条';
      case ConflictType.lottery:
        return '已有 $existingCount 条，导入 $importCount 条';
      case ConflictType.students:
        return '已有 $existingCount 人，导入 $importCount 人';
      case ConflictType.prizes:
        return '已有 $existingCount 个，导入 $importCount 个';
    }
  }
}

/// 导入结果
class ImportResult {
  final List<HistoryRecord>? historyRecords;
  final List<LotteryRecord>? lotteryRecords;
  final AppConfig? config;
  final List<Student>? students;
  final Map<String, List<Prize>>? prizePools; // 奖池名称 -> 奖品列表
  final List<String> errors;
  final List<String> warnings;

  ImportResult({
    this.historyRecords,
    this.lotteryRecords,
    this.config,
    this.students,
    this.prizePools,
    this.errors = const [],
    this.warnings = const [],
  });

  bool get hasData => 
    (historyRecords != null && historyRecords!.isNotEmpty) ||
    (lotteryRecords != null && lotteryRecords!.isNotEmpty) ||
    config != null ||
    (students != null && students!.isNotEmpty) ||
    (prizePools != null && prizePools!.isNotEmpty);

  bool get hasErrors => errors.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;

  /// 获取导入数据摘要
  String get summary {
    final parts = <String>[];
    if (historyRecords != null && historyRecords!.isNotEmpty) {
      parts.add('点名历史: ${historyRecords!.length}条');
    }
    if (lotteryRecords != null && lotteryRecords!.isNotEmpty) {
      parts.add('抽奖历史: ${lotteryRecords!.length}条');
    }
    if (config != null) {
      parts.add('配置文件');
    }
    if (students != null && students!.isNotEmpty) {
      parts.add('学生名单: ${students!.length}人');
    }
    if (prizePools != null && prizePools!.isNotEmpty) {
      final totalPrizes = prizePools!.values.fold<int>(0, (sum, prizes) => sum + prizes.length);
      parts.add('奖品名单: ${prizePools!.length}个奖池, $totalPrizes个奖品');
    }
    return parts.join(', ');
  }
}

/// 数据导入服务
class DataImportService {
  final DataService _dataService = DataService();
  final LotteryService _lotteryService = LotteryService();

  /// 从文件导入数据（桌面/移动平台）
  /// 
  /// [filePath] 文件路径（支持.json和.zip格式）
  /// 
  /// 返回导入结果
  Future<ImportResult> importFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return ImportResult(errors: ['文件不存在: $filePath']);
    }

    final extension = filePath.split('.').last.toLowerCase();
    
    switch (extension) {
      case 'json':
        return await _importFromJson(file);
      case 'zip':
        return await _importFromZip(file);
      default:
        return ImportResult(errors: ['不支持的文件格式: .$extension，支持.json和.zip']);
    }
  }

  /// 从文件内容导入数据（Web 平台）
  /// 
  /// [bytes] 文件内容
  /// [fileName] 文件名（用于判断格式）
  /// 
  /// 返回导入结果
  Future<ImportResult> importFromBytes(Uint8List bytes, String fileName) async {
    final extension = fileName.split('.').last.toLowerCase();
    
    switch (extension) {
      case 'json':
        return await _importFromJsonBytes(bytes);
      case 'zip':
        return await _importFromZipBytes(bytes);
      default:
        return ImportResult(errors: ['不支持的文件格式: .$extension，支持.json和.zip']);
    }
  }

  /// 从JSON文件导入
  Future<ImportResult> _importFromJson(File file) async {
    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      
      return _parseExportData(json);
    } catch (e) {
      return ImportResult(errors: ['JSON解析失败: $e']);
    }
  }

  /// 从JSON文件内容导入（Web平台）
  Future<ImportResult> _importFromJsonBytes(Uint8List bytes) async {
    try {
      final content = utf8.decode(bytes);
      final json = jsonDecode(content) as Map<String, dynamic>;
      
      return _parseExportData(json);
    } catch (e) {
      return ImportResult(errors: ['JSON解析失败: $e']);
    }
  }

  /// 从ZIP文件导入
  Future<ImportResult> _importFromZip(File file) async {
    try {
      final bytes = await file.readAsBytes();
      return await _importFromZipBytes(bytes);
    } catch (e) {
      return ImportResult(errors: ['ZIP解压失败: $e']);
    }
  }

  /// 从ZIP文件内容导入（Web平台）
  Future<ImportResult> _importFromZipBytes(Uint8List bytes) async {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      
      List<HistoryRecord>? historyRecords;
      List<LotteryRecord>? lotteryRecords;
      AppConfig? config;
      List<Student>? students;
      Map<String, List<Prize>>? prizePools;
      final errors = <String>[];
      final warnings = <String>[];
      
      for (final archiveFile in archive) {
        if (archiveFile.isFile) {
          final content = utf8.decode(archiveFile.content as List<int>);
          final fileName = archiveFile.name;
          
          try {
            final json = jsonDecode(content) as Map<String, dynamic>;
            final result = _parseExportData(json);
            
            // 合并结果
            if (result.historyRecords != null) {
              historyRecords = result.historyRecords;
            }
            if (result.lotteryRecords != null) {
              lotteryRecords = result.lotteryRecords;
            }
            if (result.config != null) {
              config = result.config;
            }
            if (result.students != null) {
              students = result.students;
            }
            if (result.prizePools != null) {
              prizePools = result.prizePools;
            }
            errors.addAll(result.errors);
            warnings.addAll(result.warnings);
          } catch (e) {
            errors.add('文件 $fileName 解析失败: $e');
          }
        }
      }
      
      return ImportResult(
        historyRecords: historyRecords,
        lotteryRecords: lotteryRecords,
        config: config,
        students: students,
        prizePools: prizePools,
        errors: errors,
        warnings: warnings,
      );
    } catch (e) {
      return ImportResult(errors: ['ZIP解压失败: $e']);
    }
  }

  /// 解析导出数据
  ImportResult _parseExportData(Map<String, dynamic> json) {
    final errors = <String>[];
    final warnings = <String>[];
    
    // 验证版本
    final version = json['version'] as String?;
    if (version == null) {
      warnings.add('缺少版本信息，可能不兼容');
    }
    
    // 获取数据
    final data = json['data'] as Map<String, dynamic>?;
    if (data == null) {
      return ImportResult(errors: ['缺少data字段']);
    }
    
    List<HistoryRecord>? historyRecords;
    List<LotteryRecord>? lotteryRecords;
    AppConfig? config;
    List<Student>? students;
    
    // 解析历史记录
    if (data.containsKey('records')) {
      try {
        final recordsList = data['records'] as List<dynamic>;
        historyRecords = recordsList
            .map((r) => HistoryRecord.fromJson(r as Map<String, dynamic>))
            .toList();
      } catch (e) {
        errors.add('历史记录解析失败: $e');
      }
    }
    
    // 解析抽奖记录
    if (data.containsKey('lotteryRecords')) {
      try {
        final recordsList = data['lotteryRecords'] as List<dynamic>;
        lotteryRecords = recordsList
            .map((r) => LotteryRecord.fromJson(r as Map<String, dynamic>))
            .toList();
      } catch (e) {
        errors.add('抽奖记录解析失败: $e');
      }
    }
    
    // 解析配置
    if (data.containsKey('theme_mode') || data.containsKey('config')) {
      try {
        final configData = data.containsKey('config') 
            ? data['config'] as Map<String, dynamic>
            : data;
        config = AppConfig.fromJson(configData);
      } catch (e) {
        errors.add('配置解析失败: $e');
      }
    }
    
    // 解析学生名单
    if (data.containsKey('students')) {
      try {
        final studentsList = data['students'] as List<dynamic>;
        students = studentsList
            .map((s) => Student.fromJson(s as Map<String, dynamic>))
            .toList();
      } catch (e) {
        errors.add('学生名单解析失败: $e');
      }
    }
    
    // 解析奖品名单
    Map<String, List<Prize>>? prizePools;
    if (data.containsKey('prizePools')) {
      try {
        final poolsData = data['prizePools'] as Map<String, dynamic>;
        prizePools = {};
        for (final entry in poolsData.entries) {
          final poolName = entry.key;
          final poolData = entry.value as Map<String, dynamic>;
          final prizesList = poolData['prizes'] as List<dynamic>;
          prizePools[poolName] = prizesList
              .map((p) => Prize.fromJson(p as Map<String, dynamic>))
              .toList();
        }
      } catch (e) {
        errors.add('奖品名单解析失败: $e');
      }
    }
    
    return ImportResult(
      historyRecords: historyRecords,
      lotteryRecords: lotteryRecords,
      config: config,
      students: students,
      prizePools: prizePools,
      errors: errors,
      warnings: warnings,
    );
  }

  /// 检查是否存在冲突
  /// 
  /// [result] 导入结果
  /// 
  /// 返回冲突信息列表
  Future<List<ConflictInfo>> checkConflicts(ImportResult result) async {
    final conflicts = <ConflictInfo>[];
    
    // 检查历史记录冲突
    if (result.historyRecords != null && result.historyRecords!.isNotEmpty) {
      final existingHistory = await _dataService.loadHistory();
      if (existingHistory.isNotEmpty) {
        conflicts.add(ConflictInfo(
          type: ConflictType.history,
          existingCount: existingHistory.length,
          importCount: result.historyRecords!.length,
        ));
      }
    }
    
    // 检查抽奖记录冲突
    if (result.lotteryRecords != null && result.lotteryRecords!.isNotEmpty) {
      final existingRecords = await _dataService.loadLotteryRecords();
      if (existingRecords.isNotEmpty) {
        conflicts.add(ConflictInfo(
          type: ConflictType.lottery,
          existingCount: existingRecords.length,
          importCount: result.lotteryRecords!.length,
        ));
      }
    }
    
    // 检查学生名单冲突
    if (result.students != null && result.students!.isNotEmpty) {
      final existingStudents = await _dataService.loadStudents();
      if (existingStudents.isNotEmpty) {
        // 按班级分组统计
        final existingByClass = <String, int>{};
        for (final s in existingStudents) {
          existingByClass[s.className] = (existingByClass[s.className] ?? 0) + 1;
        }
        final importByClass = <String, int>{};
        for (final s in result.students!) {
          importByClass[s.className] = (importByClass[s.className] ?? 0) + 1;
        }
        
        // 合并所有班级
        final allClasses = {...existingByClass.keys, ...importByClass.keys};
        final classStudents = allClasses.map((className) => ClassStudentInfo(
          className: className,
          existingCount: existingByClass[className] ?? 0,
          importCount: importByClass[className] ?? 0,
        )).toList();
        
        conflicts.add(ConflictInfo(
          type: ConflictType.students,
          existingCount: existingStudents.length,
          importCount: result.students!.length,
          classStudents: classStudents,
        ));
      }
    }
    
    // 检查奖品名单冲突
    if (result.prizePools != null && result.prizePools!.isNotEmpty) {
      for (final entry in result.prizePools!.entries) {
        final poolName = entry.key;
        final existingPrizes = await _lotteryService.loadPrizes(poolName);
        if (existingPrizes.isNotEmpty) {
          conflicts.add(ConflictInfo(
            type: ConflictType.prizes,
            poolName: poolName,
            existingCount: existingPrizes.length,
            importCount: entry.value.length,
          ));
        }
      }
    }
    
    return conflicts;
  }

  /// 应用导入数据
  /// 
  /// [result] 导入结果
  /// [options] 导入选项
  /// 
  /// 返回是否成功
  Future<bool> applyImport(ImportResult result, ImportOptions options) async {
    // 如果是取消策略，直接返回成功
    if (options.mergeStrategy == MergeStrategy.cancel) {
      return true;
    }

    try {
      // 导入历史记录
      if (options.importHistory && result.historyRecords != null) {
        if (options.mergeStrategy == MergeStrategy.overwrite) {
          // 覆盖模式：直接保存导入的数据
          await _dataService.saveHistory(result.historyRecords!);
        } else {
          // 合并模式：保留已有数据，添加新数据
          final existingHistory = await _dataService.loadHistory();
          final mergedHistory = _mergeHistoryRecords(existingHistory, result.historyRecords!);
          await _dataService.saveHistory(mergedHistory);
        }
      }
      
      // 导入抽奖记录
      if (options.importLottery && result.lotteryRecords != null) {
        if (options.mergeStrategy == MergeStrategy.overwrite) {
          // 覆盖模式：先清空再添加
          await _dataService.clearAllLotteryRecords();
          for (final record in result.lotteryRecords!) {
            await _dataService.addLotteryRecord(record);
          }
        } else {
          // 合并模式：添加新记录
          for (final record in result.lotteryRecords!) {
            await _dataService.addLotteryRecord(record);
          }
        }
      }
      
      // 导入配置
      if (options.importConfig && result.config != null) {
        await _dataService.saveConfig(result.config!);
      }
      
      // 导入学生名单
      if (options.importStudents && result.students != null) {
        if (options.mergeStrategy == MergeStrategy.overwrite) {
          // 覆盖模式：直接保存导入的数据
          await _dataService.saveStudents(result.students!);
        } else {
          // 合并模式：保留已有数据，添加新数据
          final existingStudents = await _dataService.loadStudents();
          final mergedStudents = _mergeStudents(existingStudents, result.students!);
          await _dataService.saveStudents(mergedStudents);
        }
      }
      
      // 导入奖品名单
      if (options.importPrizes && result.prizePools != null) {
        for (final entry in result.prizePools!.entries) {
          final poolName = entry.key;
          final prizes = entry.value;
          
          if (options.mergeStrategy == MergeStrategy.overwrite) {
            // 覆盖模式：直接保存导入的数据
            final newPool = PrizePool(name: poolName);
            await _lotteryService.savePrizePool(newPool);
            await _lotteryService.savePrizes(poolName, prizes);
          } else {
            // 合并模式：保留已有数据，添加新数据
            final existingPool = await _lotteryService.loadPrizePool(poolName);
            if (existingPool == null) {
              final newPool = PrizePool(name: poolName);
              await _lotteryService.savePrizePool(newPool);
            }
            
            final existingPrizes = await _lotteryService.loadPrizes(poolName);
            final mergedPrizes = _mergePrizes(existingPrizes, prizes);
            await _lotteryService.savePrizes(poolName, mergedPrizes);
          }
        }
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 合并历史记录（避免重复）
  List<HistoryRecord> _mergeHistoryRecords(
    List<HistoryRecord> existing,
    List<HistoryRecord> imported,
  ) {
    final existingIds = existing.map((r) => r.id).toSet();
    final merged = List<HistoryRecord>.from(existing);
    
    for (final record in imported) {
      if (!existingIds.contains(record.id)) {
        merged.add(record);
        existingIds.add(record.id);
      }
    }
    
    // 按时间排序
    merged.sort((a, b) => b.drawTime.compareTo(a.drawTime));
    
    return merged;
  }

  /// 合并学生名单（避免重复）
  List<Student> _mergeStudents(
    List<Student> existing,
    List<Student> imported,
  ) {
    final existingKeys = existing
        .map((s) => '${s.className}_${s.id}')
        .toSet();
    final merged = List<Student>.from(existing);
    
    for (final student in imported) {
      final key = '${student.className}_${student.id}';
      if (!existingKeys.contains(key)) {
        merged.add(student);
        existingKeys.add(key);
      }
    }
    
    return merged;
  }

  /// 合并奖品名单（避免重复）
  List<Prize> _mergePrizes(
    List<Prize> existing,
    List<Prize> imported,
  ) {
    final existingIds = existing.map((p) => p.id).toSet();
    final merged = List<Prize>.from(existing);
    
    for (final prize in imported) {
      if (!existingIds.contains(prize.id)) {
        merged.add(prize);
        existingIds.add(prize.id);
      }
    }
    
    return merged;
  }
}

/// 导入选项
class ImportOptions {
  final bool importHistory;
  final bool importLottery;
  final bool importConfig;
  final bool importStudents;
  final bool importPrizes;
  final MergeStrategy mergeStrategy;

  const ImportOptions({
    this.importHistory = true,
    this.importLottery = true,
    this.importConfig = true,
    this.importStudents = true,
    this.importPrizes = true,
    this.mergeStrategy = MergeStrategy.merge,
  });
}
