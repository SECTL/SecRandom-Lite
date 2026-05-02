import 'package:flutter/material.dart';
import '../../models/prize.dart';
import '../../services/excel_import_service.dart';

/// 奖品文件导入预览页面
/// 显示解析后的奖品数据，用户确认后返回导入结果
class FilePrizeImportPreviewScreen extends StatefulWidget {
  final String poolName;
  final PrizeImportResult importResult;

  const FilePrizeImportPreviewScreen({
    super.key,
    required this.poolName,
    required this.importResult,
  });

  @override
  State<FilePrizeImportPreviewScreen> createState() => _FilePrizeImportPreviewScreenState();
}

class _FilePrizeImportPreviewScreenState extends State<FilePrizeImportPreviewScreen> {
  List<Prize> _importedPrizes = [];
  bool _isImporting = false;

  Future<void> _importPrizes() async {
    setState(() {
      _isImporting = true;
    });

    try {
      final importedPrizes = <Prize>[];

      for (int i = 0; i < widget.importResult.names.length; i++) {
        importedPrizes.add(
          Prize(
            id: '${DateTime.now().microsecondsSinceEpoch}_$i',
            name: widget.importResult.names[i],
            weight: widget.importResult.weights[i],
            count: widget.importResult.counts[i],
          ),
        );
      }

      setState(() {
        _isImporting = false;
        _importedPrizes = importedPrizes;
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
                  Text('成功导入: ${importedPrizes.length} 个奖品'),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop(importedPrizes);
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
        title: Text('导入到 ${widget.poolName}'),
        actions: [
          if (!_isImporting)
            TextButton.icon(
              onPressed: _importPrizes,
              icon: const Icon(Icons.upload),
              label: const Text('确认导入'),
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
                      onPressed: () => Navigator.pop(context, null),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _importPrizes,
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
    final weights = widget.importResult.weights;
    final counts = widget.importResult.counts;

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
              _buildStatItem('总数量', names.length, Icons.card_giftcard),
              _buildStatItem(
                '总份数',
                counts.fold(0, (sum, count) => sum + count),
                Icons.format_list_numbered,
              ),
            ],
          ),
        ),
        // 奖品列表
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
                    '权重: ${index < weights.length ? weights[index] : 1} | '
                    '数量: ${index < counts.length ? counts[index] : 1}',
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
            '正在准备导入奖品数据...',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}
