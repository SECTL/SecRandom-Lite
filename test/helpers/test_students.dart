import 'dart:io';

import 'package:secrandom_lite/models/student.dart';
import 'package:secrandom_lite/services/data_service.dart';

/// 给需要学生数据的测试显式播种，不再依赖旧版内置的 40 人名单。
Future<void> seedTestStudents({int count = 40, String className = '1'}) async {
  await DataService().saveStudents(
    List.generate(count, (index) {
      final id = index + 1;
      return Student(
        id: id,
        uid: 'test:$className:s$id',
        name: '学生 $id',
        gender: id.isEven ? '女' : '男',
        group: '1',
        className: className,
        exist: true,
      );
    }),
  );
}

/// 清空当前测试数据目录（保留目录本身）。
void clearTestDataDir() {
  final dir = DataService.debugDataDirOverride;
  if (dir == null) return;
  final root = Directory(dir);
  if (!root.existsSync()) return;
  for (final entity in root.listSync()) {
    entity.deleteSync(recursive: true);
  }
}
