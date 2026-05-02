import 'package:flutter_test/flutter_test.dart';
import 'package:secrandom_lite/services/data_import_service.dart';
import 'package:secrandom_lite/services/data_export_service.dart';
import 'package:secrandom_lite/services/data_service.dart';
import 'package:secrandom_lite/models/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DataImportService Tests', () {
    late DataImportService importService;
    late DataExportService exportService;
    late DataService dataService;
    late String tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      importService = DataImportService();
      exportService = DataExportService();
      dataService = DataService();
      
      // 创建临时目录
      tempDir = path.join(Directory.current.path, 'test_temp_import');
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

    test('importFromFile should return error for non-existent file', () async {
      final result = await importService.importFromFile('/non/existent/file.json');
      
      expect(result.hasErrors, true);
      expect(result.errors.first, contains('文件不存在'));
    });

    test('importFromFile should return error for unsupported format', () async {
      // 创建一个测试文件
      final testFile = File(path.join(tempDir, 'test.txt'));
      await testFile.writeAsString('test content');
      
      final result = await importService.importFromFile(testFile.path);
      
      expect(result.hasErrors, true);
      expect(result.errors.first, contains('不支持的文件格式'));
    });

    test('importFromFile should import JSON config file', () async {
      // 先导出配置
      final exportPath = await exportService.exportData(
        {ExportType.config},
        tempDir,
      );
      
      // 再导入
      final result = await importService.importFromFile(exportPath);
      
      expect(result.hasErrors, false);
      expect(result.config, isNotNull);
    });

    test('importFromFile should import JSON students file', () async {
      // 先保存一些测试数据
      await dataService.saveStudents([]);
      
      // 导出
      final exportPath = await exportService.exportData(
        {ExportType.students},
        tempDir,
      );
      
      // 导入
      final result = await importService.importFromFile(exportPath);
      
      expect(result.hasErrors, false);
      expect(result.students, isNotNull);
    });

    test('importFromFile should import ZIP file', () async {
      // 先导出多个类型
      final exportPath = await exportService.exportData(
        {ExportType.config, ExportType.students},
        tempDir,
      );
      
      // 再导入
      final result = await importService.importFromFile(exportPath);
      
      expect(result.hasErrors, false);
      expect(result.hasData, true);
    });

    test('importFromFile should handle invalid JSON', () async {
      // 创建一个无效的JSON文件
      final testFile = File(path.join(tempDir, 'invalid.json'));
      await testFile.writeAsString('invalid json content');
      
      final result = await importService.importFromFile(testFile.path);
      
      expect(result.hasErrors, true);
      expect(result.errors.first, contains('JSON解析失败'));
    });

    test('ImportResult should correctly report hasData', () {
      final emptyResult = ImportResult();
      expect(emptyResult.hasData, false);
      
      final configResult = ImportResult(config: AppConfig.defaultConfig());
      expect(configResult.hasData, true);
    });

    test('ImportResult should correctly report hasErrors', () {
      final noErrorsResult = ImportResult();
      expect(noErrorsResult.hasErrors, false);
      
      final withErrorsResult = ImportResult(errors: ['error1']);
      expect(withErrorsResult.hasErrors, true);
    });

    test('ImportResult should generate correct summary', () {
      final result = ImportResult(
        config: AppConfig.defaultConfig(),
        students: [],
        historyRecords: [],
      );
      
      final summary = result.summary;
      expect(summary, contains('配置文件'));
    });

    test('ImportOptions should have correct defaults', () {
      const options = ImportOptions();
      
      expect(options.importHistory, true);
      expect(options.importLottery, true);
      expect(options.importConfig, true);
      expect(options.importStudents, true);
    });

    test('applyImport should return true for successful import', () async {
      final result = ImportResult(
        config: AppConfig.defaultConfig(),
      );
      
      const options = ImportOptions(importConfig: true);
      
      final success = await importService.applyImport(result, options);
      expect(success, true);
    });
  });
}
