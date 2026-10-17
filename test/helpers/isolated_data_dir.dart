import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:secrandom_lite/services/data_service.dart';

/// 给当前测试文件单独一个临时数据目录，整个文件跑完后回收。
///
/// `DataService` 默认把数据写在 `Platform.resolvedExecutable` 同级的 `data/`
/// 下，而 `flutter test` 里那个值指向 Flutter SDK 内部的测试引擎——于是 13 个
/// 构造 `AppProvider` 或直接使用 `DataService` 的测试文件全部读写同一个真实
/// 目录。靠各文件在 setUp 里删目录来清理是补不住的：删完之后，上一个测试遗留
/// 的异步写入随时可能再落盘，计数就在预期值上下漂移。CI 上失败项每次都不一样，
/// 正是这个原因——取决于排在前面跑完的是哪个文件。
///
/// **在 main() 或 group() 顶层调用一次**：
///
/// ```dart
/// void main() {
///   TestWidgetsFlutterBinding.ensureInitialized();
///   isolateDataServiceDir();
///   ...
/// }
/// ```
///
/// 两个生命周期钩子都必须在这一层注册：`tearDownAll()` 只能在测试开始前注册，
/// 写在 `setUpAll` 内部会抛 "Can't call tearDownAll() once tests have begun
/// running."，临时目录由闭包在两者之间共享。
///
/// 也不能用 `setUp`/`addTearDown`：那会在**每个测试结束时**把覆盖点清掉，而
/// `AppProvider` 的配置保存与云同步 outbox 都是延迟写入——它们在 tearDown
/// 之后才落地时就会穿透覆盖点写回默认目录。整个文件期间保持覆盖点有效，
/// 才能堵住这条路。
///
/// 附带的好处是不再往 Flutter SDK 安装目录里写业务文件：同机器上其他 Flutter
/// 项目也在那个目录下跑测试。
void isolateDataServiceDir() {
  Directory? dir;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('secrandom_test_');
    DataService.debugDataDirOverride = dir!.path;
  });

  tearDownAll(() {
    // 留到文件末尾才清：期间任何迟到的写入都只会落在这个临时目录里，
    // 而不是回落到 SDK 目录。
    DataService.debugDataDirOverride = null;
    if (dir != null && dir!.existsSync()) {
      dir!.deleteSync(recursive: true);
    }
  });
}
