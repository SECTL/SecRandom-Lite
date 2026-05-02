import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import 'package:universal_html/html.dart' as html;
import 'data_service.dart';
import 'lottery_service.dart';

/// 导出结果
class ExportResult {
  final String fileName;
  final Uint8List bytes;

  ExportResult({required this.fileName, required this.bytes});
}

/// 数据导出类型
enum ExportType {
  history, // 点名历史记录
  lottery, // 抽奖历史记录
  config, // 配置文件
  students, // 学生名单
  prizes, // 奖品名单
}

/// 数据导出服务
class DataExportService {
  final DataService _dataService = DataService();
  final LotteryService _lotteryService = LotteryService();

  /// 导出数据（桌面/移动平台）
  /// 
  /// [types] 要导出的数据类型集合
  /// [savePath] 保存路径
  /// 
  /// 返回导出文件的完整路径
  Future<String> exportData(Set<ExportType> types, String savePath) async {
    if (types.isEmpty) {
      throw ArgumentError('至少选择一种数据类型');
    }

    final timestamp = _getTimestamp();
    
    // 单类型导出为JSON文件
    if (types.length == 1) {
      return await _exportSingleType(types.first, savePath, timestamp);
    }
    
    // 多类型导出为ZIP文件
    return await _exportMultipleTypes(types, savePath, timestamp);
  }

  /// 导出数据并返回文件内容（Web平台）
  /// 
  /// [types] 要导出的数据类型集合
  /// 
  /// 返回导出文件的内容和文件名
  Future<ExportResult> exportDataAsBytes(Set<ExportType> types) async {
    if (types.isEmpty) {
      throw ArgumentError('至少选择一种数据类型');
    }

    final timestamp = _getTimestamp();
    
    // 单类型导出为JSON文件
    if (types.length == 1) {
      final type = types.first;
      final fileName = '${type.name}_$timestamp.json';
      final data = await _collectData(type);
      final exportJson = _wrapExportData(data);
      final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(exportJson));
      return ExportResult(fileName: fileName, bytes: Uint8List.fromList(bytes));
    }
    
    // 多类型导出为ZIP文件
    final fileName = 'secrandom_backup_$timestamp.zip';
    final archive = Archive();
    
    for (final type in types) {
      final data = await _collectData(type);
      final exportJson = _wrapExportData(data);
      final jsonBytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(exportJson));
      
      final archiveFile = ArchiveFile('${type.name}.json', jsonBytes.length, jsonBytes);
      archive.addFile(archiveFile);
    }
    
    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw Exception('ZIP编码失败');
    }
    
    return ExportResult(fileName: fileName, bytes: Uint8List.fromList(zipBytes));
  }

  /// 在Web平台下载文件
  void downloadFile(String fileName, Uint8List bytes) {
    if (!kIsWeb) {
      throw UnsupportedError('downloadFile 仅支持 Web 平台');
    }
    
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  /// 导出单个类型为JSON文件
  Future<String> _exportSingleType(ExportType type, String savePath, String timestamp) async {
    final fileName = '${type.name}_$timestamp.json';
    final filePath = path.join(savePath, fileName);
    
    final data = await _collectData(type);
    final exportJson = _wrapExportData(data);
    
    final file = File(filePath);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(exportJson));
    
    return filePath;
  }

  /// 导出多个类型为ZIP文件
  Future<String> _exportMultipleTypes(Set<ExportType> types, String savePath, String timestamp) async {
    final fileName = 'secrandom_backup_$timestamp.zip';
    final filePath = path.join(savePath, fileName);
    
    final archive = Archive();
    
    for (final type in types) {
      final data = await _collectData(type);
      final exportJson = _wrapExportData(data);
      final jsonBytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(exportJson));
      
      final archiveFile = ArchiveFile('${type.name}.json', jsonBytes.length, jsonBytes);
      archive.addFile(archiveFile);
    }
    
    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw Exception('ZIP编码失败');
    }
    
    final file = File(filePath);
    await file.writeAsBytes(zipBytes);
    
    return filePath;
  }

  /// 收集指定类型的数据
  Future<Map<String, dynamic>> _collectData(ExportType type) async {
    switch (type) {
      case ExportType.history:
        final history = await _dataService.loadHistory();
        return {
          'records': history.map((r) => r.toJson()).toList(),
        };
        
      case ExportType.lottery:
        final lotteryRecords = await _dataService.loadLotteryRecords();
        return {
          'records': lotteryRecords.map((r) => r.toJson()).toList(),
        };
        
      case ExportType.config:
        final config = await _dataService.loadConfig();
        return config.toJson();
        
      case ExportType.students:
        final students = await _dataService.loadStudents();
        return {
          'students': students.map((s) => s.toJson()).toList(),
        };
        
      case ExportType.prizes:
        final pools = await _lotteryService.loadPrizePools();
        final Map<String, dynamic> prizesData = {};
        for (final pool in pools) {
          final prizes = await _lotteryService.loadPrizes(pool.name);
          prizesData[pool.name] = {
            'pool': pool.toJson(),
            'prizes': prizes.map((p) => p.toJson()).toList(),
          };
        }
        return {'prizePools': prizesData};
    }
  }

  /// 包装导出数据
  Map<String, dynamic> _wrapExportData(Map<String, dynamic> data) {
    return {
      'version': '1.0',
      'exportTime': DateTime.now().toIso8601String(),
      'appVersion': '1.0.1',
      'data': data,
    };
  }

  /// 获取时间戳字符串
  String _getTimestamp() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
  }
}
