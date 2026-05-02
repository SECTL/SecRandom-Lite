import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart';

/// Excel/TXT 文件导入服务
/// 支持智能表头匹配，自动识别姓名、性别、小组列
class ExcelImportService {
  // 智能表头匹配常量（参考 Wanderer 项目 GlobalConstants.cs）
  static const List<String> _nameHeaders = ['姓名', '名字', 'name', '学生', '人员'];
  static const List<String> _genderHeaders = ['性别', 'sex', 'gender'];
  static const List<String> _groupHeaders = ['小组', '分组', 'group', '组', '班级'];

  // 奖品表头匹配常量
  static const List<String> _prizeNameHeaders = ['奖品', '名称', 'name', 'prize', '奖品名称'];
  static const List<String> _prizeWeightHeaders = ['权重', 'weight', '概率'];
  static const List<String> _prizeCountHeaders = ['数量', 'count', '个数', '份数'];

  // 性别值映射
  static const List<String> _maleValues = ['男', 'male', 'boy', 'man', '1'];
  static const List<String> _femaleValues = ['女', 'female', 'girl', 'woman', '0'];

  /// 解析 Excel 文件 (.xlsx)
  static Future<ImportResult> parseExcel(Uint8List bytes) async {
    try {
      final excel = Excel.decodeBytes(bytes);

      if (excel.tables.isEmpty) {
        return ImportResult(
          names: [],
          genders: [],
          groups: [],
          errors: ['Excel 文件中没有工作表'],
        );
      }

      // 使用第一个工作表
      final sheet = excel.tables.values.first;
      if (sheet.rows.isEmpty) {
        return ImportResult(
          names: [],
          genders: [],
          groups: [],
          errors: ['工作表中没有数据'],
        );
      }

      // 解析表头（第一行）
      final headerRow = sheet.rows.first;
      final headers = headerRow
          .map((cell) => cell?.value?.toString().toLowerCase().trim() ?? '')
          .toList();

      // 智能匹配列索引
      final nameIndex = _findColumnIndex(headers, _nameHeaders);
      final genderIndex = _findColumnIndex(headers, _genderHeaders);
      final groupIndex = _findColumnIndex(headers, _groupHeaders);

      // 如果没有找到姓名列，尝试使用第一列
      final effectiveNameIndex = nameIndex >= 0 ? nameIndex : 0;

      // 解析数据行（跳过表头）
      final List<String> names = [];
      final List<String> genders = [];
      final List<String> groups = [];
      final List<String> errors = [];

      for (int i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        if (row.isEmpty) continue;

        // 获取姓名
        final name = _getCellValue(row, effectiveNameIndex);
        if (name.isEmpty) {
          errors.add('第 ${i + 1} 行：姓名为空');
          continue;
        }

        // 获取性别
        String gender = '未知';
        if (genderIndex >= 0) {
          final genderValue = _getCellValue(row, genderIndex);
          gender = _normalizeGender(genderValue);
        }

        // 获取小组
        String group = '1';
        if (groupIndex >= 0) {
          final groupValue = _getCellValue(row, groupIndex);
          if (groupValue.isNotEmpty) {
            group = groupValue;
          }
        }

        names.add(name);
        genders.add(gender);
        groups.add(group);
      }

      return ImportResult(
        names: names,
        genders: genders,
        groups: groups,
        errors: errors,
      );
    } catch (e) {
      return ImportResult(
        names: [],
        genders: [],
        groups: [],
        errors: ['解析 Excel 文件失败: ${e.toString()}'],
      );
    }
  }

  /// 解析 TXT 文件（每行一个姓名）
  static Future<ImportResult> parseTxt(String content) async {
    try {
      final lines = const LineSplitter()
          .convert(content)
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      if (lines.isEmpty) {
        return ImportResult(
          names: [],
          genders: [],
          groups: [],
          errors: ['TXT 文件为空'],
        );
      }

      // 检测是否是 CSV 格式（包含逗号或制表符）
      final firstLine = lines.first;
      final hasComma = firstLine.contains(',');
      final hasTab = firstLine.contains('\t');

      if (hasComma || hasTab) {
        // 按 CSV 格式解析
        return _parseCsvLikeLines(lines, hasComma ? ',' : '\t');
      }

      // 普通 TXT 格式：每行一个姓名
      final List<String> names = [];
      final List<String> genders = [];
      final List<String> groups = [];
      final List<String> errors = [];

      for (int i = 0; i < lines.length; i++) {
        final name = lines[i].trim();
        if (name.isEmpty) {
          errors.add('第 ${i + 1} 行：姓名为空');
          continue;
        }

        // 检查是否包含性别信息（如 "张三 男"）
        String gender = '未知';
        String actualName = name;

        final parts = name.split(RegExp(r'\s+'));
        if (parts.length >= 2) {
          final possibleGender = _normalizeGender(parts.last);
          if (possibleGender != '未知') {
            gender = possibleGender;
            actualName = parts.sublist(0, parts.length - 1).join(' ');
          }
        }

        names.add(actualName);
        genders.add(gender);
        groups.add('1');
      }

      return ImportResult(
        names: names,
        genders: genders,
        groups: groups,
        errors: errors,
      );
    } catch (e) {
      return ImportResult(
        names: [],
        genders: [],
        groups: [],
        errors: ['解析 TXT 文件失败: ${e.toString()}'],
      );
    }
  }

  /// 解析 CSV 格式的行
  static ImportResult _parseCsvLikeLines(List<String> lines, String separator) {
    final List<String> names = [];
    final List<String> genders = [];
    final List<String> groups = [];
    final List<String> errors = [];

    // 解析表头
    final headers = lines.first
        .split(separator)
        .map((h) => h.trim().toLowerCase())
        .toList();

    final nameIndex = _findColumnIndex(headers, _nameHeaders);
    final genderIndex = _findColumnIndex(headers, _genderHeaders);
    final groupIndex = _findColumnIndex(headers, _groupHeaders);

    final effectiveNameIndex = nameIndex >= 0 ? nameIndex : 0;

    // 解析数据行
    for (int i = 1; i < lines.length; i++) {
      final parts = lines[i]
          .split(separator)
          .map((p) => p.trim())
          .toList();

      if (parts.isEmpty || parts.every((p) => p.isEmpty)) {
        errors.add('第 ${i + 1} 行：数据为空');
        continue;
      }

      // 获取姓名
      String name = '';
      if (effectiveNameIndex < parts.length) {
        name = parts[effectiveNameIndex];
      }
      if (name.isEmpty) {
        errors.add('第 ${i + 1} 行：姓名为空');
        continue;
      }

      // 获取性别
      String gender = '未知';
      if (genderIndex >= 0 && genderIndex < parts.length) {
        gender = _normalizeGender(parts[genderIndex]);
      }

      // 获取小组
      String group = '1';
      if (groupIndex >= 0 && groupIndex < parts.length) {
        if (parts[groupIndex].isNotEmpty) {
          group = parts[groupIndex];
        }
      }

      names.add(name);
      genders.add(gender);
      groups.add(group);
    }

    return ImportResult(
      names: names,
      genders: genders,
      groups: groups,
      errors: errors,
    );
  }

  /// 智能匹配列索引
  static int _findColumnIndex(List<String> headers, List<String> keywords) {
    for (int i = 0; i < headers.length; i++) {
      final header = headers[i].toLowerCase().trim();
      if (keywords.any((k) => header.contains(k))) {
        return i;
      }
    }
    return -1;
  }

  /// 获取单元格值
  static String _getCellValue(List<Data?> row, int index) {
    if (index < 0 || index >= row.length) return '';
    final cell = row[index];
    if (cell == null || cell.value == null) return '';
    return cell.value.toString().trim();
  }

  /// 标准化性别值
  static String _normalizeGender(String? value) {
    if (value == null || value.isEmpty) return '未知';
    final lower = value.toLowerCase().trim();
    if (_maleValues.contains(lower)) return '男';
    if (_femaleValues.contains(lower)) return '女';
    return '未知';
  }

  /// 解析奖品 Excel 文件 (.xlsx)
  static Future<PrizeImportResult> parsePrizeExcel(Uint8List bytes) async {
    try {
      final excel = Excel.decodeBytes(bytes);

      if (excel.tables.isEmpty) {
        return PrizeImportResult(
          names: [],
          weights: [],
          counts: [],
          errors: ['Excel 文件中没有工作表'],
        );
      }

      // 使用第一个工作表
      final sheet = excel.tables.values.first;
      if (sheet.rows.isEmpty) {
        return PrizeImportResult(
          names: [],
          weights: [],
          counts: [],
          errors: ['工作表中没有数据'],
        );
      }

      // 解析表头（第一行）
      final headerRow = sheet.rows.first;
      final headers = headerRow
          .map((cell) => cell?.value?.toString().toLowerCase().trim() ?? '')
          .toList();

      // 智能匹配列索引
      final nameIndex = _findColumnIndex(headers, _prizeNameHeaders);
      final weightIndex = _findColumnIndex(headers, _prizeWeightHeaders);
      final countIndex = _findColumnIndex(headers, _prizeCountHeaders);

      // 如果没有找到名称列，尝试使用第一列
      final effectiveNameIndex = nameIndex >= 0 ? nameIndex : 0;

      // 解析数据行（跳过表头）
      final List<String> names = [];
      final List<double> weights = [];
      final List<int> counts = [];
      final List<String> errors = [];

      for (int i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        if (row.isEmpty) continue;

        // 获取奖品名称
        final name = _getCellValue(row, effectiveNameIndex);
        if (name.isEmpty) {
          errors.add('第 ${i + 1} 行：奖品名称为空');
          continue;
        }

        // 获取权重
        double weight = 1.0;
        if (weightIndex >= 0) {
          final weightStr = _getCellValue(row, weightIndex);
          if (weightStr.isNotEmpty) {
            final parsed = double.tryParse(weightStr);
            if (parsed != null && parsed > 0) {
              weight = parsed;
            } else {
              errors.add('第 ${i + 1} 行：权重值无效，使用默认值 1');
            }
          }
        }

        // 获取数量
        int count = 1;
        if (countIndex >= 0) {
          final countStr = _getCellValue(row, countIndex);
          if (countStr.isNotEmpty) {
            final parsed = int.tryParse(countStr);
            if (parsed != null && parsed > 0) {
              count = parsed;
            } else {
              errors.add('第 ${i + 1} 行：数量值无效，使用默认值 1');
            }
          }
        }

        names.add(name);
        weights.add(weight);
        counts.add(count);
      }

      return PrizeImportResult(
        names: names,
        weights: weights,
        counts: counts,
        errors: errors,
      );
    } catch (e) {
      return PrizeImportResult(
        names: [],
        weights: [],
        counts: [],
        errors: ['解析 Excel 文件失败: ${e.toString()}'],
      );
    }
  }

  /// 解析奖品 TXT 文件（每行一个奖品名称）
  static Future<PrizeImportResult> parsePrizeTxt(String content) async {
    try {
      final lines = const LineSplitter()
          .convert(content)
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      if (lines.isEmpty) {
        return PrizeImportResult(
          names: [],
          weights: [],
          counts: [],
          errors: ['TXT 文件为空'],
        );
      }

      // 检测是否是 CSV 格式（包含逗号或制表符）
      final firstLine = lines.first;
      final hasComma = firstLine.contains(',');
      final hasTab = firstLine.contains('\t');

      if (hasComma || hasTab) {
        // 按 CSV 格式解析
        return _parsePrizeCsvLikeLines(lines, hasComma ? ',' : '\t');
      }

      // 普通 TXT 格式：每行一个奖品名称
      final List<String> names = [];
      final List<double> weights = [];
      final List<int> counts = [];
      final List<String> errors = [];

      for (int i = 0; i < lines.length; i++) {
        final name = lines[i].trim();
        if (name.isEmpty) {
          errors.add('第 ${i + 1} 行：奖品名称为空');
          continue;
        }

        names.add(name);
        weights.add(1.0);
        counts.add(1);
      }

      return PrizeImportResult(
        names: names,
        weights: weights,
        counts: counts,
        errors: errors,
      );
    } catch (e) {
      return PrizeImportResult(
        names: [],
        weights: [],
        counts: [],
        errors: ['解析 TXT 文件失败: ${e.toString()}'],
      );
    }
  }

  /// 解析 CSV 格式的奖品行
  static PrizeImportResult _parsePrizeCsvLikeLines(List<String> lines, String separator) {
    final List<String> names = [];
    final List<double> weights = [];
    final List<int> counts = [];
    final List<String> errors = [];

    // 解析表头
    final headers = lines.first
        .split(separator)
        .map((h) => h.trim().toLowerCase())
        .toList();

    final nameIndex = _findColumnIndex(headers, _prizeNameHeaders);
    final weightIndex = _findColumnIndex(headers, _prizeWeightHeaders);
    final countIndex = _findColumnIndex(headers, _prizeCountHeaders);

    final effectiveNameIndex = nameIndex >= 0 ? nameIndex : 0;

    // 解析数据行
    for (int i = 1; i < lines.length; i++) {
      final parts = lines[i]
          .split(separator)
          .map((p) => p.trim())
          .toList();

      if (parts.isEmpty || parts.every((p) => p.isEmpty)) {
        errors.add('第 ${i + 1} 行：数据为空');
        continue;
      }

      // 获取奖品名称
      String name = '';
      if (effectiveNameIndex < parts.length) {
        name = parts[effectiveNameIndex];
      }
      if (name.isEmpty) {
        errors.add('第 ${i + 1} 行：奖品名称为空');
        continue;
      }

      // 获取权重
      double weight = 1.0;
      if (weightIndex >= 0 && weightIndex < parts.length) {
        final weightStr = parts[weightIndex];
        if (weightStr.isNotEmpty) {
          final parsed = double.tryParse(weightStr);
          if (parsed != null && parsed > 0) {
            weight = parsed;
          } else {
            errors.add('第 ${i + 1} 行：权重值无效，使用默认值 1');
          }
        }
      }

      // 获取数量
      int count = 1;
      if (countIndex >= 0 && countIndex < parts.length) {
        final countStr = parts[countIndex];
        if (countStr.isNotEmpty) {
          final parsed = int.tryParse(countStr);
          if (parsed != null && parsed > 0) {
            count = parsed;
          } else {
            errors.add('第 ${i + 1} 行：数量值无效，使用默认值 1');
          }
        }
      }

      names.add(name);
      weights.add(weight);
      counts.add(count);
    }

    return PrizeImportResult(
      names: names,
      weights: weights,
      counts: counts,
      errors: errors,
    );
  }
}

/// 导入结果
class ImportResult {
  final List<String> names;
  final List<String> genders;
  final List<String> groups;
  final List<String> errors;

  ImportResult({
    required this.names,
    required this.genders,
    required this.groups,
    this.errors = const [],
  });

  bool get hasData => names.isNotEmpty;
  bool get hasErrors => errors.isNotEmpty;
  int get validCount => names.length;
}

/// 奖品导入结果
class PrizeImportResult {
  final List<String> names;
  final List<double> weights;
  final List<int> counts;
  final List<String> errors;

  PrizeImportResult({
    required this.names,
    required this.weights,
    required this.counts,
    this.errors = const [],
  });

  bool get hasData => names.isNotEmpty;
  bool get hasErrors => errors.isNotEmpty;
  int get validCount => names.length;
}
