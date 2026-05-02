import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../services/excel_import_service.dart';

/// 文件导入预览页面
/// 显示解析后的学生数据，用户确认后执行导入
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
            _importProgress = total > 0 ? current / total : 0;
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
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('导入完成'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.check, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Text('成功导入: ${result.successCount} 名学生'),
                ],
              ),
              if (result.failCount > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red, size: 20),
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
      body: _isImporting ? _buildImportingView() : _buildPreviewView(),
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
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildStatItem('总人数', names.length, Icons.people),
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
