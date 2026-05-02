# Excel 导入功能实现计划

## TL;DR
> **Summary**: 为 SecRandom 添加从 Excel/TXT 文件导入学生名单的功能，支持智能表头匹配
> **Deliverables**: 新增 Excel 解析服务、导入 UI 界面、智能列匹配
> **Effort**: Short (2-3 小时)
> **Parallel**: YES - 2 waves
> **Critical Path**: Task 1 → Task 2 → Task 3

## Context

### Original Request
为名单导入添加"从Excel表格导入"功能

### 参考实现
- `Wanderer/GlobalConstants.cs` - 智能表头匹配常量
- `Wanderer/Views/MainPages/ProfilePage.Import.cs` - 多格式导入架构

### Metis Review
- 需要处理 Web 平台的文件读取差异（bytes vs path）
- Excel 表头可能有多种写法，需要模糊匹配
- 大文件导入需要进度提示

## Work Objectives

### Core Objective
用户可以从本地选择 Excel/CSV/TXT 文件，自动识别姓名、性别、小组列，批量导入学生

### Deliverables
1. 新增依赖：`excel` + `file_picker`
2. 新增 `ExcelImportService` - 解析 Excel/CSV/TXT
3. 修改 `StudentImportScreen` - 添加文件导入入口
4. 智能表头匹配 - 自动识别列含义

### Definition of Done
- [ ] 用户点击"从文件导入"按钮，弹出文件选择器
- [ ] 支持 .xlsx、.txt 格式
- [ ] 自动识别"姓名/name"、"性别/sex"、"小组/group"列
- [ ] 导入前显示预览，确认后批量导入
- [ ] Web、Android、iOS、Windows、macOS、Linux 均可正常使用

### Must Have
- 智能表头匹配（支持中英文）
- 导入前预览
- 进度提示
- 错误处理

### Must NOT Have
- 不支持旧版 .xls 格式
- 不修改现有学生数据结构
- 不添加云端导入功能

## Verification Strategy

- Test decision: 测试后置（tests-after）
- QA policy: 每个任务都有手动验证场景
- Evidence: 截图 + 终端输出

## Execution Strategy

### Parallel Execution Waves

**Wave 1: 基础设施（并行）**
- Task 1: 添加依赖
- Task 2: 创建 ExcelImportService

**Wave 2: UI 集成（依赖 Wave 1）**
- Task 3: 修改 StudentImportScreen

### Dependency Matrix
```
Task 1 (依赖) ──┬──→ Task 3 (UI)
Task 2 (服务) ──┘
```

## TODOs

- [ ] 1. 添加依赖

  **What to do**:
  在 `pubspec.yaml` 的 `dependencies` 中添加：
  ```yaml
  excel: ^4.0.6
  file_picker: ^8.0.0
  ```

  **Must NOT do**:
  - 不要修改其他依赖版本
  - 不要运行 `flutter pub upgrade`

  **Recommended Agent Profile**:
  - Category: `quick` - 简单配置修改
  - Skills: [] - 无需特殊技能

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: [3] | Blocked By: []

  **References**:
  - 文件: `pubspec.yaml:9-24` - 当前依赖列表

  **Acceptance Criteria**:
  - [ ] `flutter pub get` 成功执行
  - [ ] `pubspec.lock` 中包含 `excel` 和 `file_picker`

  **QA Scenarios**:
  ```
  Scenario: 依赖安装成功
    Tool: Bash
    Steps: flutter pub get
    Expected: 退出码 0，无错误输出
    Evidence: .sisyphus/evidence/task-1-pub-get.txt
  ```

  **Commit**: YES | Message: `feat(deps): add excel and file_picker dependencies` | Files: [pubspec.yaml, pubspec.lock]

---

- [ ] 2. 创建 ExcelImportService

  **What to do**:
  创建 `lib/services/excel_import_service.dart`：

  ```dart
  import 'dart:typed_data';
  import 'package:excel/excel.dart';
  
  class ExcelImportService {
    // 智能表头匹配常量（参考 GlobalConstants.cs）
    static const List<String> _nameHeaders = ['姓名', '名字', 'name', '学生'];
    static const List<String> _genderHeaders = ['性别', 'sex', 'gender'];
    static const List<String> _groupHeaders = ['小组', '分组', 'group', '组'];
    
    static const List<String> _maleValues = ['男', 'male', 'boy', 'man', '1'];
    static const List<String> _femaleValues = ['女', 'female', 'girl', 'woman', '0'];
    
    /// 解析 Excel 文件
    static Future<ImportResult> parseExcel(Uint8List bytes) async {
      final excel = Excel.decodeBytes(bytes);
      // ... 解析逻辑
    }
    
    /// 解析 TXT 文件（每行一个姓名）
    static Future<ImportResult> parseTxt(String content) async {
      // ... TXT 解析
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
    
    /// 标准化性别值
    static String _normalizeGender(String? value) {
      if (value == null) return '未知';
      final lower = value.toLowerCase().trim();
      if (_maleValues.contains(lower)) return '男';
      if (_femaleValues.contains(lower)) return '女';
      return '未知';
    }
  }
  
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
  }
  ```

  **Must NOT do**:
  - 不要直接修改 AppProvider
  - 不要添加 UI 代码

  **Recommended Agent Profile**:
  - Category: `unspecified-low` - 纯业务逻辑
  - Skills: [] - 无需特殊技能

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: [3] | Blocked By: [1]

  **References**:
  - 参考: `J:\git file\Wanderer\Wanderer\GlobalConstants.cs:33-44` - 表头匹配常量
  - 参考: `J:\git file\Wanderer\Wanderer\Views\MainPages\ProfilePage.Import.cs:35-44` - Excel 解析
  - 模型: `lib/models/student.dart:1-39` - Student 数据结构

  **Acceptance Criteria**:
  - [ ] 文件创建成功，无语法错误
  - [ ] `parseExcel` 能正确解析 .xlsx 文件
  - [ ] `parseTxt` 能正确解析 TXT 文件（每行一个姓名）
  - [ ] 智能匹配能识别中英文表头
  - [ ] 性别值标准化正确（male→男，female→女）

  **QA Scenarios**:
  ```
  Scenario: Excel 解析正确
    Tool: Bash
    Steps: 创建测试文件 test/test_data.xlsx，调用 parseExcel
    Expected: 返回正确的 names/genders/groups 列表
    Evidence: .sisyphus/evidence/task-2-excel-parse.txt
  
  Scenario: 智能表头匹配
    Tool: Bash
    Steps: 使用表头 ["Name", "Sex", "Group"] 的 Excel 文件
    Expected: 正确识别为姓名、性别、小组列
    Evidence: .sisyphus/evidence/task-2-header-match.txt
  ```

  **Commit**: YES | Message: `feat(service): add ExcelImportService with smart header matching` | Files: [lib/services/excel_import_service.dart]

---

- [ ] 3. 修改 RollCallSettingsScreen 添加快速导入按钮和预览界面

  **What to do**:

  **3.1 修改 `lib/screens/settings/rollcall_settings_screen.dart`**

  在 `floatingActionButton` 区域添加"快速导入"按钮（在"新建班级"按钮上方）：

  ```dart
  floatingActionButton: Consumer<AppProvider>(
    builder: (context, provider, _) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 快速导入按钮（新增）
        FloatingActionButton.extended(
          heroTag: 'quick-import',
          onPressed: () => _showQuickImportDialog(context, provider),
          icon: const Icon(Icons.file_upload),
          label: const Text('快速导入'),
        ),
        const SizedBox(height: 12),
        // 新建班级按钮（原有）
        FloatingActionButton(
          heroTag: 'add-class',
          onPressed: () => _addClass(provider),
          tooltip: '新建班级',
          child: const Icon(Icons.add),
        ),
      ],
    ),
  ),
  ```

  **3.2 新增 `_showQuickImportDialog` 方法**

  弹出对话框让用户选择导入方式：
  - 从文件导入（Excel/TXT）
  - 取消

  ```dart
  Future<void> _showQuickImportDialog(BuildContext context, AppProvider provider) async {
    // 先让用户选择目标班级
    final selectedClass = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择导入到哪个班级'),
        children: [
          ...provider.groups.map((className) => SimpleDialogOption(
            onPressed: () => Navigator.pop(context, className),
            child: Text(className),
          )),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    
    if (selectedClass == null) return;
    
    // 选择文件
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'txt'],
      withData: true,
    );
    
    if (result == null) return;
    
    final file = result.files.single;
    final extension = file.name.split('.').last.toLowerCase();
    
    // 显示加载指示器
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    
    try {
      ImportResult importResult;
      switch (extension) {
        case 'xlsx':
          importResult = await ExcelImportService.parseExcel(file.bytes!);
          break;
        case 'txt':
          importResult = await ExcelImportService.parseTxt(
            utf8.decode(file.bytes!),
          );
          break;
        default:
          Navigator.pop(context); // 关闭加载指示器
          _showErrorDialog('不支持的文件格式，请使用 .xlsx 或 .txt 文件');
          return;
      }
      
      Navigator.pop(context); // 关闭加载指示器
      
      // 检查解析结果
      if (importResult.names.isEmpty) {
        _showErrorDialog('文件中没有找到有效的学生数据');
        return;
      }
      
      if (importResult.errors.isNotEmpty) {
        final proceed = await _showWarningDialog(
          '解析警告',
          '发现 ${importResult.errors.length} 条问题数据：\n'
          '${importResult.errors.take(5).join('\n')}'
          '${importResult.errors.length > 5 ? '\n...' : ''}\n\n'
          '是否继续导入有效的 ${importResult.names.length} 条数据？',
        );
        if (proceed != true) return;
      }
      
      // 导航到预览页面
      final importSuccess = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => FileImportPreviewScreen(
            className: selectedClass,
            importResult: importResult,
          ),
        ),
      );
      
      if (importSuccess == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('学生导入成功')),
        );
      }
    } catch (e) {
      Navigator.pop(context); // 关闭加载指示器（如果还在）
      _showErrorDialog('文件解析失败：${e.toString()}');
    }
  }
  
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error, color: Colors.red),
            SizedBox(width: 8),
            Text('错误'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
  
  Future<bool?> _showWarningDialog(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning, color: Colors.orange),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('继续导入'),
          ),
        ],
      ),
    );
  }
  ```

  **3.3 新增 `FileImportPreviewScreen` 预览页面**

  创建 `lib/screens/settings/file_import_preview_screen.dart`：

  ```dart
  import 'package:flutter/material.dart';
  import 'package:provider/provider.dart';
  import '../../providers/app_provider.dart';
  import '../../services/excel_import_service.dart';
  
  class FileImportPreviewScreen extends StatefulWidget {
    final String className;
    final ImportResult importResult;
    
    const FileImportPreviewScreen({
      super.key,
      required this.className,
      required this.importResult,
    });
    
    @override
    State<FileImportPreviewScreen> createState() => _FileImportPreviewScreenState();
  }
  
  class _FileImportPreviewScreenState extends State<FileImportPreviewScreen> {
    bool _isImporting = false;
    double _importProgress = 0.0;
    int _importedCount = 0;
    int _totalCount = 0;
    
    Future<void> _importStudents() async {
      setState(() {
        _isImporting = true;
        _importProgress = 0.0;
        _importedCount = 0;
        _totalCount = widget.importResult.names.length;
      });
      
      try {
        final provider = Provider.of<AppProvider>(context, listen: false);
        final result = await provider.batchImportStudents(
          widget.className,
          names: widget.importResult.names,
          genders: widget.importResult.genders,
          groups: widget.importResult.groups,
          onProgress: (current, total) {
            setState(() {
              _importedCount = current;
              _totalCount = total;
              _importProgress = current / total;
            });
          },
        );
        
        setState(() {
          _isImporting = false;
        });
        
        if (!mounted) return;
        
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('导入完成'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 8),
                    Text('成功导入: ${result.successCount} 名学生'),
                  ],
                ),
                if (result.failCount > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.error, color: Colors.red),
                      const SizedBox(width: 8),
                      Text('导入失败: ${result.failCount} 条记录'),
                    ],
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pop(true);
                },
                child: const Text('确定'),
              ),
            ],
          ),
        );
      } catch (e) {
        setState(() {
          _isImporting = false;
        });
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
    
    @override
    Widget build(BuildContext context) {
      return Scaffold(
        appBar: AppBar(
          title: Text('导入到 ${widget.className}'),
          actions: [
            if (!_isImporting)
              TextButton.icon(
                onPressed: _importStudents,
                icon: const Icon(Icons.upload, color: Colors.white),
                label: const Text('确认导入', style: TextStyle(color: Colors.white)),
              ),
          ],
        ),
        body: _isImporting
            ? _buildImportingView()
            : _buildPreviewView(),
        bottomNavigationBar: _isImporting
            ? null
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _importStudents,
                        child: const Text('确认导入'),
                      ),
                    ),
                  ],
                ),
              ),
      );
    }
    
    Widget _buildPreviewView() {
      final names = widget.importResult.names;
      final genders = widget.importResult.genders;
      final groups = widget.importResult.groups;
      
      return Column(
        children: [
          // 统计信息
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('总人数', names.length, Icons.people),
                _buildStatItem('男生', genders.where((g) => g == '男').length, Icons.male, Colors.blue),
                _buildStatItem('女生', genders.where((g) => g == '女').length, Icons.female, Colors.pink),
              ],
            ),
          ),
          // 学生列表
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: names.length,
              itemBuilder: (context, index) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text(
                      names[index],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '性别: ${index < genders.length ? genders[index] : '未知'} | '
                      '小组: ${index < groups.length ? groups[index] : '1'}',
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }
    
    Widget _buildStatItem(String label, int count, IconData icon, [Color? color]) {
      return Column(
        children: [
          Icon(icon, color: color ?? Theme.of(context).colorScheme.primary),
          const SizedBox(height: 4),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      );
    }
    
    Widget _buildImportingView() {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              '正在导入学生数据...',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Column(
                children: [
                  LinearProgressIndicator(value: _importProgress),
                  const SizedBox(height: 8),
                  Text(
                    '$_importedCount / $_totalCount',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
  }
  ```

  **Must NOT do**:
  - 不要删除现有的文本粘贴导入功能（student_import_screen.dart 保留）
  - 不要修改 AppProvider 的 batchImportStudents 方法
  - 不要修改 Student 数据模型

  **Recommended Agent Profile**:
  - Category: `unspecified-low` - UI 修改
  - Skills: [] - 无需特殊技能

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: [] | Blocked By: [1, 2]

  **References**:
  - 文件: `lib/screens/settings/rollcall_settings_screen.dart:328-334` - 现有 FAB 区域
  - 文件: `lib/screens/settings/student_import_screen.dart:374-431` - 预览界面参考
  - 文件: `lib/providers/app_provider.dart:569-649` - batchImportStudents 方法

  **Acceptance Criteria**:
  - [ ] 点名名单设置页面右下角显示两个按钮：快速导入（上）、新建班级（下）
  - [ ] 点击"快速导入"弹出班级选择对话框
  - [ ] 选择班级后弹出文件选择器，仅显示 .xlsx/.txt 文件
  - [ ] 文件解析失败时显示错误对话框（红色错误图标）
  - [ ] 文件为空或无有效数据时显示错误提示
  - [ ] 存在问题数据时显示警告对话框，用户可选择继续或取消
  - [ ] 预览页面显示学生列表（姓名、性别、小组）
  - [ ] 预览页面顶部显示统计信息（总人数、男生、女生）
  - [ ] 点击"确认导入"显示进度条
  - [ ] 导入完成显示成功/失败统计
  - [ ] Web 平台可以正常使用

  **QA Scenarios**:
  ```
  Scenario: 正常 Excel 导入流程
    Tool: Playwright / 手动测试
    Steps:
      1. 准备测试 Excel 文件（表头：姓名、性别、小组，10条数据）
      2. 进入设置 → 点名名单设置
      3. 点击右下角"快速导入"按钮
      4. 选择目标班级
      5. 选择准备好的 Excel 文件
      6. 查看预览页面，确认数据正确
      7. 点击"确认导入"
    Expected: 导入完成，显示成功导入 10 名学生
    Evidence: .sisyphus/evidence/task-3-normal-import.png

  Scenario: TXT 文件导入流程
    Tool: Playwright / 手动测试
    Steps:
      1. 准备 TXT 文件，每行一个姓名（5行）
      2. 执行导入流程，选择 TXT 文件
    Expected: 预览页面显示 5 名学生，性别显示"未知"，小组显示"1"
    Evidence: .sisyphus/evidence/task-3-txt-import.png

  Scenario: 非法格式文件处理
    Tool: Playwright / 手动测试
    Steps:
      1. 准备一个非 Excel/TXT 文件（如 .pdf 或 .jpg）
      2. 尝试导入
    Expected: 显示错误对话框"不支持的文件格式"
    Evidence: .sisyphus/evidence/task-3-invalid-format.png

  Scenario: 空文件处理
    Tool: Playwright / 手动测试
    Steps:
      1. 准备一个空的 Excel 文件（只有表头，无数据）
      2. 尝试导入
    Expected: 显示错误对话框"文件中没有找到有效的学生数据"
    Evidence: .sisyphus/evidence/task-3-empty-file.png

  Scenario: 部分数据问题处理
    Tool: Playwright / 手动测试
    Steps:
      1. 准备 Excel 文件，部分行姓名为空
      2. 尝试导入
    Expected: 显示警告对话框，提示问题数据数量，用户可选择继续导入
    Evidence: .sisyphus/evidence/task-3-partial-data.png

  Scenario: 智能表头匹配
    Tool: Playwright / 手动测试
    Steps:
      1. 准备表头为 ["Name", "Sex", "Group"] 的 Excel 文件
      2. 执行导入流程
    Expected: 数据正确填充，Name 列识别为姓名
    Evidence: .sisyphus/evidence/task-3-smart-header.png

  Scenario: Web 平台兼容性
    Tool: Playwright
    Steps:
      1. 在 Web 浏览器中运行应用
      2. 执行完整导入流程
    Expected: 文件选择、解析、预览、导入均正常工作
    Evidence: .sisyphus/evidence/task-3-web-compat.png
  ```

  **Commit**: YES | Message: `feat(ui): add file import to StudentImportScreen` | Files: [lib/screens/settings/student_import_screen.dart]

## Final Verification Wave

- [ ] F1. Plan Compliance Audit — 检查所有功能是否按计划实现
- [ ] F2. Code Quality Review — 代码风格、命名规范
- [ ] F3. Real Manual QA — 在 3 个平台测试完整流程
- [ ] F4. Scope Fidelity Check — 确认未超出范围

## 文件变更清单

| 操作 | 文件路径 | 说明 |
|------|---------|------|
| 新增 | `lib/services/excel_import_service.dart` | Excel/TXT 解析服务 |
| 新增 | `lib/screens/settings/file_import_preview_screen.dart` | 导入预览页面 |
| 修改 | `lib/screens/settings/rollcall_settings_screen.dart` | 添加快速导入按钮 |
| 修改 | `pubspec.yaml` | 添加依赖 |

## Commit Strategy

```
feat(deps): add excel and file_picker dependencies
feat(service): add ExcelImportService with smart header matching
feat(ui): add quick import button and preview screen to rollcall settings
```

## Success Criteria

1. 点名名单设置页面右下角显示"快速导入"和"新建班级"两个按钮
2. 点击"快速导入"后：选择班级 → 选择文件 → 解析 → 预览 → 确认导入
3. 完善的错误反馈机制：
   - 非法格式文件 → 错误对话框
   - 空文件 → 错误对话框
   - 部分数据问题 → 警告对话框，可选择继续
   - 解析异常 → 错误对话框
4. 智能表头匹配支持中英文
5. 所有 6 个平台均可正常使用
6. 现有文本粘贴导入功能保持不变
