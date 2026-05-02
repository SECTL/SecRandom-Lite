import 'package:flutter_test/flutter_test.dart';
import 'package:secrandom_lite/services/data_export_service.dart';
import 'package:secrandom_lite/services/data_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DataExportService Tests', () {
    late DataExportService exportService;
    late DataService dataService;
    late String tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      exportService = DataExportService();
      dataService = DataService();
      
      // 创建临时目录
      tempDir = path.join(Directory.current.path, 'test_temp');
      final dir = Directory(tempDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    });

    tearDown(() async {
      // 清理临时目录
      final dir = Directory(tempDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    test('exportData should throw ArgumentError for empty types', () async {
      expect(
        () => exportService.exportData({}, tempDir),
        throwsArgumentError,
      );
    });

    test('exportData should export config to JSON file', () async {
      final filePath = await exportService.exportData(
        {ExportType.config},
        tempDir,
      );
      
      expect(filePath, endsWith('.json'));
      expect(filePath, contains('config'));
      
      final file = File(filePath);
      expect(await file.exists(), true);
      
      final content = await file.readAsString();
      expect(content, contains('"version"'));
      expect(content, contains('"exportTime"'));
      expect(content, contains('"data"'));
    });

    test('exportData should export students to JSON file', () async {
      // 先保存一些测试数据
      await dataService.saveStudents([]);
      
      final filePath = await exportService.exportData(
        {ExportType.students},
        tempDir,
      );
      
      expect(filePath, endsWith('.json'));
      expect(filePath, contains('students'));
      
      final file = File(filePath);
      expect(await file.exists(), true);
    });

    test('exportData should export history to JSON file', () async {
      final filePath = await exportService.exportData(
        {ExportType.history},
        tempDir,
      );
      
      expect(filePath, endsWith('.json'));
      expect(filePath, contains('history'));
      
      final file = File(filePath);
      expect(await file.exists(), true);
    });

    test('exportData should export multiple types to ZIP file', () async {
      final filePath = await exportService.exportData(
        {ExportType.config, ExportType.students, ExportType.history},
        tempDir,
      );
      
      expect(filePath, endsWith('.zip'));
      expect(filePath, contains('secrandom_backup'));
      
      final file = File(filePath);
      expect(await file.exists(), true);
      
      // 验证文件大小大于0
      final fileSize = await file.length();
      expect(fileSize, greaterThan(0));
    });

    test('exportData should export all types to ZIP file', () async {
      final filePath = await exportService.exportData(
        {ExportType.history, ExportType.lottery, ExportType.config, ExportType.students},
        tempDir,
      );
      
      expect(filePath, endsWith('.zip'));
      
      final file = File(filePath);
      expect(await file.exists(), true);
    });

    test('ExportType enum should have correct values', () {
      expect(ExportType.values.length, 5);
      expect(ExportType.values, contains(ExportType.history));
      expect(ExportType.values, contains(ExportType.lottery));
      expect(ExportType.values, contains(ExportType.config));
      expect(ExportType.values, contains(ExportType.students));
      expect(ExportType.values, contains(ExportType.prizes));
    });
  });
}
