import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';

class ParsedStudentData {
  final String name;
  final String gender;
  final String group;
  final bool isValid;

  const ParsedStudentData({
    required this.name,
    required this.gender,
    required this.group,
    required this.isValid,
  });
}

class StudentImportScreen extends StatefulWidget {
  final String className;

  const StudentImportScreen({super.key, required this.className});

  @override
  State<StudentImportScreen> createState() => _StudentImportScreenState();
}

class _StudentImportScreenState extends State<StudentImportScreen> {
  final _namesController = TextEditingController();
  final _gendersController = TextEditingController();
  final _groupsController = TextEditingController();

  List<ParsedStudentData> _parsedData = [];
  bool _showPreview = false;
  bool _isImporting = false;
  double _importProgress = 0.0;
  int _importedCount = 0;
  int _totalCount = 0;

  @override
  void dispose() {
    _namesController.dispose();
    _gendersController.dispose();
    _groupsController.dispose();
    super.dispose();
  }

  List<String> _parseLines(String text) {
    return text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  void _parseData() {
    final names = _parseLines(_namesController.text);
    final genders = _parseLines(_gendersController.text);
    final groups = _parseLines(_groupsController.text);

    _parsedData = [];

    for (int i = 0; i < names.length; i++) {
      final name = names[i].trim();
      String gender = '未知';
      String group = '1';

      if (i < genders.length) {
        final g = genders[i].trim();
        if (g == '男' || g == '女') {
          gender = g;
        }
      }

      if (i < groups.length) {
        final grp = groups[i].trim();
        if (grp.isNotEmpty) {
          group = grp;
        }
      }

      _parsedData.add(ParsedStudentData(
        name: name,
        gender: gender,
        group: group,
        isValid: name.isNotEmpty,
      ));
    }

    setState(() {
      _showPreview = true;
    });
  }

  Future<void> _importStudents() async {
    if (_parsedData.isEmpty) return;

    final validData = _parsedData.where((d) => d.isValid).toList();
    if (validData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有有效的学生数据可导入')),
      );
      return;
    }

    setState(() {
      _isImporting = true;
      _importProgress = 0.0;
      _importedCount = 0;
      _totalCount = validData.length;
    });

    final names = validData.map((d) => d.name).toList();
    final genders = validData.map((d) => d.gender).toList();
    final groups = validData.map((d) => d.group).toList();

    try {
      final provider = Provider.of<AppProvider>(context, listen: false);
      final result = await provider.batchImportStudents(
        widget.className,
        names: names,
        genders: genders,
        groups: groups,
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
        title: const Text('快速导入学生'),
        actions: [
          if (_showPreview && !_isImporting)
            TextButton.icon(
              onPressed: _importStudents,
              icon: const Icon(Icons.upload, color: Colors.white),
              label: const Text('确认导入', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: _isImporting
          ? _buildImportingView()
          : _showPreview
              ? _buildPreviewView()
              : _buildInputView(),
      bottomNavigationBar: !_showPreview || _isImporting
          ? null
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _showPreview = false;
                        });
                      },
                      child: const Text('返回修改'),
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

  Widget _buildInputView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 20, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '导入说明',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• 每行输入一个学生的信息\n'
                    '• 姓名为必填项，性别和小组可留空\n'
                    '• 性格仅接受"男"或"女"，其他值视为"未知"\n'
                    '• 三个输入框的行数需一一对应\n'
                    '• 建议从 WPS Office 或 Excel 直接复制完整表格列',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildInputSection(
            '姓名（必填）',
            _namesController,
            '张三\n李四\n王五',
            Icons.person,
            true,
          ),
          const SizedBox(height: 16),
          _buildInputSection(
            '性别（可选）',
            _gendersController,
            '男\n女\n男',
            Icons.wc,
            false,
          ),
          const SizedBox(height: 16),
          _buildInputSection(
            '小组（可选）',
            _groupsController,
            '1\n2\n1',
            Icons.group,
            false,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                if (_namesController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请至少输入一个学生姓名')),
                  );
                  return;
                }
                _parseData();
              },
              icon: const Icon(Icons.preview),
              label: const Text('预览数据'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputSection(
    String label,
    TextEditingController controller,
    String hint,
    IconData icon,
    bool isRequired,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (isRequired)
                  Text(
                    ' *',
                    style: TextStyle(color: Colors.red[700]),
                  ),
                const Spacer(),
                Text(
                  '${_parseLines(controller.text).length} 行',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: hint,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.all(12),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewView() {
    final validCount = _parsedData.where((d) => d.isValid).length;
    final invalidCount = _parsedData.length - validCount;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('总行数', _parsedData.length, Icons.list),
              _buildStatItem('有效数据', validCount, Icons.check_circle, Colors.green),
              if (invalidCount > 0)
                _buildStatItem('无效数据', invalidCount, Icons.error, Colors.red),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _parsedData.length,
            itemBuilder: (context, index) {
              final data = _parsedData[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: data.isValid
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(
                    data.name.isEmpty ? '(空姓名)' : data.name,
                    style: TextStyle(
                      color: data.isValid ? null : Colors.grey,
                      decoration: data.isValid ? null : TextDecoration.lineThrough,
                    ),
                  ),
                  subtitle: Text('性别: ${data.gender} | 小组: ${data.group}'),
                  trailing: Icon(
                    data.isValid ? Icons.check_circle : Icons.cancel,
                    color: data.isValid ? Colors.green : Colors.red,
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
