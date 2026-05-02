import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import '../../models/student.dart';
import '../../providers/app_provider.dart';
import '../../services/excel_import_service.dart';
import '../../widgets/responsive_grid.dart';
import 'student_import_screen.dart';
import 'file_import_preview_screen.dart';

enum _EntryAction { edit, delete }

class RollCallSettingsScreen extends StatefulWidget {
  const RollCallSettingsScreen({super.key});

  @override
  State<RollCallSettingsScreen> createState() => _RollCallSettingsScreenState();
}

class _RollCallSettingsScreenState extends State<RollCallSettingsScreen> {
  bool _isLoading = true;
  bool get _isMobilePlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _addClass(AppProvider provider) async {
    final nameController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建班级'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: '班级名称',
            hintText: '请输入班级名称',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;
    if (provider.groups.contains(result)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('班级已存在')),
      );
      return;
    }

    try {
      await provider.addClass(result);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ClassStudentSettingsScreen(className: result),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('添加班级失败')),
      );
    }
  }

  Future<void> _openClass(String className) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ClassStudentSettingsScreen(className: className),
      ),
    );
  }

  Future<void> _renameClassInList(AppProvider provider, String oldName) async {
    final nameController = TextEditingController(text: oldName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑班级'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: '班级名称',
            hintText: '请输入班级名称',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty || result == oldName) return;
    if (provider.groups.contains(result)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('班级已存在')),
      );
      return;
    }

    try {
      await provider.renameClass(oldName, result);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('编辑班级失败')),
      );
    }
  }

  Future<void> _deleteClass(AppProvider provider, String className, int studentCount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除班级 "$className" 吗？\n该班级下 $studentCount 名学生将被永久删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await provider.deleteClass(className);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除班级失败')),
      );
    }
  }

  Future<void> _handleClassAction(
    AppProvider provider,
    String className,
    int totalCount,
    _EntryAction action,
  ) async {
    switch (action) {
      case _EntryAction.edit:
        await _renameClassInList(provider, className);
        break;
      case _EntryAction.delete:
        await _deleteClass(provider, className, totalCount);
        break;
    }
  }

  Future<void> _showClassActionMenuAtPosition(
    AppProvider provider,
    String className,
    int totalCount,
    Offset globalPosition,
  ) async {
    final action = await showMenu<_EntryAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: const [
        PopupMenuItem<_EntryAction>(
          value: _EntryAction.edit,
          child: Text('编辑'),
        ),
        PopupMenuItem<_EntryAction>(
          value: _EntryAction.delete,
          child: Text('删除'),
        ),
      ],
    );

    if (action == null || !mounted) return;
    await _handleClassAction(provider, className, totalCount, action);
  }

  Future<void> _showQuickImportDialog(BuildContext context, AppProvider provider) async {
    // 先让用户选择目标班级
    final selectedClass = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择导入到哪个班级'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, '__create_new__'),
            child: const Row(
              children: [
                Icon(Icons.add, color: Colors.blue),
                SizedBox(width: 8),
                Text('新建班级', style: TextStyle(color: Colors.blue)),
              ],
            ),
          ),
          const Divider(),
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

    String targetClass = selectedClass;

    // 如果用户选择创建新班级
    if (selectedClass == '__create_new__') {
      final newClassName = await _showCreateClassDialog(context);
      if (newClassName == null || newClassName.isEmpty) return;

      // 检查班级是否已存在
      if (provider.groups.contains(newClassName)) {
        if (!mounted) return;
        _showErrorDialog('班级 "$newClassName" 已存在');
        return;
      }

      // 创建新班级
      await provider.addClass(newClassName);
      targetClass = newClassName;
    }

    // 选择导入方式
    final importMethod = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择导入方式'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'file'),
            child: const Row(
              children: [
                Icon(Icons.file_upload),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('从文件导入', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('支持 .xlsx 和 .txt 格式', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'text'),
            child: const Row(
              children: [
                Icon(Icons.text_fields),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('从文本导入', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('直接粘贴姓名列表', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (importMethod == null) return;

    if (importMethod == 'text') {
      // 导航到文本导入页面
      final importSuccess = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => StudentImportScreen(className: targetClass),
        ),
      );

      if (importSuccess == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('学生导入成功')),
        );
      }
      return;
    }

    // 从文件导入
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'txt'],
        withData: true,
      );
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog('文件选择失败: ${e.toString()}');
      return;
    }

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
          if (file.bytes == null) {
            if (mounted) Navigator.pop(context);
            if (mounted) _showErrorDialog('无法读取文件内容');
            return;
          }
          importResult = await ExcelImportService.parseExcel(file.bytes!);
          break;
        case 'txt':
          final bytes = file.bytes;
          if (bytes == null) {
            if (mounted) Navigator.pop(context);
            if (mounted) _showErrorDialog('无法读取文件内容');
            return;
          }
          importResult = await ExcelImportService.parseTxt(utf8.decode(bytes));
          break;
        default:
          if (mounted) Navigator.pop(context);
          if (mounted) _showErrorDialog('不支持的文件格式，请使用 .xlsx 或 .txt 文件');
          return;
      }

      if (mounted) Navigator.pop(context); // 关闭加载指示器

      // 检查解析结果
      if (importResult.names.isEmpty) {
        if (mounted) {
          _showErrorDialog(
            importResult.errors.isNotEmpty
                ? '文件解析失败: ${importResult.errors.first}'
                : '文件中没有找到有效的学生数据',
          );
        }
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
            className: targetClass,
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
      if (mounted) Navigator.pop(context); // 关闭加载指示器（如果还在）
      if (mounted) _showErrorDialog('文件解析失败: ${e.toString()}');
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

  Future<String?> _showCreateClassDialog(BuildContext context) {
    final nameController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建班级'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: '班级名称',
            hintText: '请输入班级名称',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('点名名单设置'),
        actions: [
          Consumer<AppProvider>(
            builder: (context, provider, _) => TextButton.icon(
              onPressed: () => _showQuickImportDialog(context, provider),
              icon: const Icon(Icons.file_upload),
              label: const Text('快速导入'),
            ),
          ),
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          final classNames = provider.groups;
          final students = provider.allStudents;

          return Column(
            children: [
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : classNames.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.class_outlined,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '暂无班级',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '点击右下角 + 按钮创建新班级',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ResponsiveGrid(
                        padding: const EdgeInsets.all(16),
                        children: classNames.map((className) {
                          final classStudents = students.where((s) => s.className == className).toList();
                          final existingCount = classStudents.where((s) => s.exist).length;
                          final totalCount = classStudents.length;

                          return Card(
                            child: GestureDetector(
                              onLongPressStart: _isMobilePlatform
                                  ? (details) async {
                                      await _showClassActionMenuAtPosition(
                                        provider,
                                        className,
                                        totalCount,
                                        details.globalPosition,
                                      );
                                    }
                                  : null,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Theme.of(context).colorScheme.primary,
                                  child: Text(
                                    className.isEmpty ? '?' : className[0].toUpperCase(),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                title: Text(
                                  className,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text('学生数量: $existingCount | 总数: $totalCount'),
                                trailing: _isMobilePlatform
                                    ? null
                                    : PopupMenuButton<_EntryAction>(
                                        tooltip: '更多',
                                        onSelected: (action) =>
                                            _handleClassAction(provider, className, totalCount, action),
                                        itemBuilder: (context) => const [
                                          PopupMenuItem<_EntryAction>(
                                            value: _EntryAction.edit,
                                            child: Text('编辑'),
                                          ),
                                          PopupMenuItem<_EntryAction>(
                                            value: _EntryAction.delete,
                                            child: Text('删除'),
                                          ),
                                        ],
                                        icon: const Icon(Icons.more_vert),
                                      ),
                                onTap: () => _openClass(className),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: Consumer<AppProvider>(
        builder: (context, provider, _) => FloatingActionButton(
          onPressed: () => _addClass(provider),
          tooltip: '新建班级',
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class ClassStudentSettingsScreen extends StatefulWidget {
  final String className;

  const ClassStudentSettingsScreen({super.key, required this.className});

  @override
  State<ClassStudentSettingsScreen> createState() => _ClassStudentSettingsScreenState();
}

class _ClassStudentSettingsScreenState extends State<ClassStudentSettingsScreen> {
  late String _className;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _className = widget.className;
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _addStudent(AppProvider provider) async {
    final result = await _showStudentDialog();
    if (result == null) return;

    try {
      await provider.addStudentToClass(
        _className,
        name: result.name,
        gender: result.gender,
        group: result.group,
        exist: result.exist,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('添加学生失败')),
      );
    }
  }

  Future<void> _editStudent(AppProvider provider, Student student) async {
    final result = await _showStudentDialog(initialStudent: student);
    if (result == null) return;

    try {
      await provider.updateStudentInClass(
        _className,
        student.id,
        name: result.name,
        gender: result.gender,
        group: result.group,
        exist: result.exist,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('编辑学生失败')),
      );
    }
  }

  Future<void> _deleteStudent(AppProvider provider, Student student) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除学生 "${student.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await provider.deleteStudentFromClass(_className, student.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除学生失败')),
      );
    }
  }

  Future<_StudentFormData?> _showStudentDialog({Student? initialStudent}) async {
    final nameController = TextEditingController(text: initialStudent?.name ?? '');
    final groupController = TextEditingController(text: initialStudent?.group ?? '1');
    String gender = initialStudent?.gender ?? '男';
    bool exist = initialStudent?.exist ?? true;

    return showDialog<_StudentFormData>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(initialStudent == null ? '添加学生' : '编辑学生'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '姓名',
                    hintText: '请输入学生姓名',
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: gender,
                  decoration: const InputDecoration(labelText: '性别'),
                  items: [
                    const DropdownMenuItem(value: '男', child: Text('男')),
                    const DropdownMenuItem(value: '女', child: Text('女')),
                    const DropdownMenuItem(value: '未知', child: Text('未知')),
                    const DropdownMenuItem(
                      value: '__custom__',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 16),
                          SizedBox(width: 8),
                          Text('自定义...'),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (value) async {
                    if (value == '__custom__') {
                      final customGender = await _showCustomGenderDialog(context, gender);
                      if (customGender != null && customGender.isNotEmpty) {
                        setDialogState(() {
                          gender = customGender;
                        });
                      }
                    } else if (value != null) {
                      setDialogState(() {
                        gender = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: groupController,
                  decoration: const InputDecoration(
                    labelText: '小组',
                    hintText: '请输入小组名称',
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: exist,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('存在状态'),
                  subtitle: const Text('关闭后将不会参与点名'),
                  onChanged: (value) {
                    setDialogState(() {
                      exist = value;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                final name = nameController.text.trim();
                final group = groupController.text.trim().isEmpty ? '1' : groupController.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(
                  context,
                  _StudentFormData(
                    name: name,
                    gender: gender,
                    group: group,
                    exist: exist,
                  ),
                );
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _showCustomGenderDialog(BuildContext context, String currentGender) {
    final controller = TextEditingController(text: currentGender);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自定义性别'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '性别',
            hintText: '请输入自定义性别',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_className),
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          final students = provider.allStudents.where((s) => s.className == _className).toList();

          if (_isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (students.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '暂无学生',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '点击右下角按钮添加或快速导入学生',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            );
          }

          return ResponsiveGrid(
            children: students.map((student) {
              return Card(
                child: ListTile(
                  title: Text(
                    student.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      decoration: student.exist ? null : TextDecoration.lineThrough,
                      color: student.exist ? null : Colors.grey,
                    ),
                  ),
                  subtitle: Row(
                    children: [
                      Checkbox(
                        value: student.exist,
                        visualDensity: VisualDensity.compact,
                        onChanged: (value) async {
                          if (value == null) return;
                          try {
                            await provider.setStudentExistInClass(_className, student.id, value);
                          } catch (_) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(content: Text('更新学生状态失败')),
                            );
                          }
                        },
                      ),
                      Expanded(
                        child: Text(
                          '性别: ${student.gender} | 小组: ${student.group} | 学号: ${student.id}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: student.exist ? null : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                  trailing: SizedBox(
                    width: 96,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _editStudent(provider, student),
                          tooltip: '编辑',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _deleteStudent(provider, student),
                          tooltip: '删除',
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
      floatingActionButton: Consumer<AppProvider>(
        builder: (context, provider, _) => FloatingActionButton(
          onPressed: () => _addStudent(provider),
          tooltip: '添加学生',
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class _StudentFormData {
  final String name;
  final String gender;
  final String group;
  final bool exist;

  const _StudentFormData({
    required this.name,
    required this.gender,
    required this.group,
    required this.exist,
  });
}
