import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import '../../services/data_export_service.dart';
import '../../services/data_import_service.dart';

class DataManagementScreen extends StatefulWidget {
  const DataManagementScreen({super.key});

  @override
  State<DataManagementScreen> createState() => _DataManagementScreenState();
}

class _DataManagementScreenState extends State<DataManagementScreen> {
  final DataExportService _exportService = DataExportService();
  final DataImportService _importService = DataImportService();
  
  // 导出选项状态
  final Map<ExportType, bool> _exportOptions = {
    ExportType.history: true,
    ExportType.lottery: true,
    ExportType.config: true,
    ExportType.students: true,
    ExportType.prizes: true,
  };
  
  bool _isExporting = false;
  bool _isImporting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据管理'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildExportSection(),
          const SizedBox(height: 3),
          _buildImportSection(),
        ],
      ),
    );
  }

  Widget _buildExportSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.upload, color: Theme.of(context).colorScheme.primary),
          title: Text(
            '导出数据',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: const Text('选择要导出的数据类型，导出的文件可用于备份或迁移到其他设备。'),
        ),
        ..._buildExportCheckboxes(),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isExporting ? null : _handleExport,
            icon: _isExporting 
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            label: Text(_isExporting ? '导出中...' : '导出数据'),
          ),
        ),
        const Divider(),
      ],
    );
  }

  List<Widget> _buildExportCheckboxes() {
    return _exportOptions.entries.map((entry) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: CheckboxListTile(
          title: Text(_getExportTypeLabel(entry.key)),
          subtitle: Text(_getExportTypeDescription(entry.key)),
          value: entry.value,
          onChanged: (value) {
            setState(() {
              _exportOptions[entry.key] = value ?? false;
            });
          },
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
      );
    }).toList();
  }

  Widget _buildImportSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.download, color: Theme.of(context).colorScheme.primary),
          title: Text(
            '导入数据',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: const Text('从之前导出的备份文件中恢复数据。支持.json和.zip格式。'),
        ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isImporting ? null : _handleImport,
            icon: _isImporting 
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file),
            label: Text(_isImporting ? '导入中...' : '选择文件导入'),
          ),
        ),
      ],
    );
  }

  String _getExportTypeLabel(ExportType type) {
    switch (type) {
      case ExportType.history:
        return '点名历史记录';
      case ExportType.lottery:
        return '抽奖历史记录';
      case ExportType.config:
        return '应用配置';
      case ExportType.students:
        return '学生名单';
      case ExportType.prizes:
        return '奖品名单';
    }
  }

  String _getExportTypeDescription(ExportType type) {
    switch (type) {
      case ExportType.history:
        return '包含所有班级的点名记录';
      case ExportType.lottery:
        return '包含所有奖池的抽奖记录';
      case ExportType.config:
        return '主题、动画模式等设置';
      case ExportType.students:
        return '所有班级的学生信息';
      case ExportType.prizes:
        return '所有奖池的奖品配置';
    }
  }

  Future<void> _handleExport() async {
    final selectedTypes = _exportOptions.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toSet();

    if (selectedTypes.isEmpty) {
      _showSnackBar('请至少选择一种数据类型', isError: true);
      return;
    }

    setState(() => _isExporting = true);

    try {
      if (kIsWeb) {
        // Web 平台：下载文件
        final result = await _exportService.exportDataAsBytes(selectedTypes);
        _exportService.downloadFile(result.fileName, result.bytes);
        
        if (mounted) {
          _showSnackBar('导出成功！文件已开始下载');
        }
      } else {
        // 桌面/移动平台：保存到本地
        String? savePath;
        if (selectedTypes.length == 1) {
          savePath = await FilePicker.platform.getDirectoryPath(
            dialogTitle: '选择导出保存位置',
          );
        } else {
          savePath = await FilePicker.platform.getDirectoryPath(
            dialogTitle: '选择导出保存位置',
          );
        }

        if (savePath == null) {
          setState(() => _isExporting = false);
          return;
        }

        final filePath = await _exportService.exportData(selectedTypes, savePath);
        
        if (mounted) {
          _showSnackBar('导出成功！文件已保存到: $filePath');
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('导出失败: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _handleImport() async {
    setState(() => _isImporting = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'zip'],
        withData: kIsWeb, // Web 平台需要读取文件内容
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _isImporting = false);
        return;
      }

      ImportResult importResult;
      
      if (kIsWeb) {
        // Web 平台：使用文件内容
        final file = result.files.single;
        final bytes = file.bytes;
        if (bytes == null) {
          _showSnackBar('无法读取文件内容', isError: true);
          setState(() => _isImporting = false);
          return;
        }
        importResult = await _importService.importFromBytes(bytes, file.name);
      } else {
        // 桌面/移动平台：使用文件路径
        final filePath = result.files.single.path;
        if (filePath == null) {
          _showSnackBar('无法获取文件路径', isError: true);
          setState(() => _isImporting = false);
          return;
        }
        importResult = await _importService.importFromFile(filePath);
      }

      if (!mounted) {
        setState(() => _isImporting = false);
        return;
      }

      if (importResult.hasErrors) {
        _showSnackBar('文件解析失败: ${importResult.errors.first}', isError: true);
        setState(() => _isImporting = false);
        return;
      }

      if (!importResult.hasData) {
        _showSnackBar('文件中没有可导入的数据', isError: true);
        setState(() => _isImporting = false);
        return;
      }

      // 检查冲突
      final conflicts = await _importService.checkConflicts(importResult);
      
      // 显示预览和冲突处理对话框
      final strategy = await _showImportDialog(importResult, conflicts);

      if (strategy == null || !mounted) {
        setState(() => _isImporting = false);
        return;
      }

      // 如果用户选择取消
      if (strategy == MergeStrategy.cancel) {
        setState(() => _isImporting = false);
        return;
      }

      // 执行导入
      final options = ImportOptions(
        importHistory: importResult.historyRecords != null,
        importLottery: importResult.lotteryRecords != null,
        importConfig: importResult.config != null,
        importStudents: importResult.students != null,
        importPrizes: importResult.prizePools != null,
        mergeStrategy: strategy,
      );

      final success = await _importService.applyImport(importResult, options);

      if (mounted) {
        if (success) {
          _showSnackBar('导入成功！');
        } else {
          _showSnackBar('导入失败，请重试', isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('导入失败: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<MergeStrategy?> _showImportDialog(ImportResult result, List<ConflictInfo> conflicts) {
    final hasConflicts = conflicts.any((c) => c.hasConflict);
    
    // 创建冲突映射，方便查找
    final conflictMap = <ConflictType, ConflictInfo>{};
    for (final conflict in conflicts) {
      conflictMap[conflict.type] = conflict;
    }
    
    return showDialog<MergeStrategy>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(hasConflicts ? '导入预览 - 检测到冲突' : '导入预览'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('将导入以下数据：'),
              const SizedBox(height: 16),
              
              // 点名历史
              if (result.historyRecords != null && result.historyRecords!.isNotEmpty)
                _buildConflictPreviewItem(
                  icon: Icons.history,
                  title: '点名历史',
                  importCount: result.historyRecords!.length,
                  unit: '条记录',
                  conflict: conflictMap[ConflictType.history],
                ),
              
              // 抽奖历史
              if (result.lotteryRecords != null && result.lotteryRecords!.isNotEmpty)
                _buildConflictPreviewItem(
                  icon: Icons.card_giftcard,
                  title: '抽奖历史',
                  importCount: result.lotteryRecords!.length,
                  unit: '条记录',
                  conflict: conflictMap[ConflictType.lottery],
                ),
              
              // 应用配置
              if (result.config != null)
                _buildPreviewItem(
                  Icons.settings,
                  '应用配置',
                  '主题、动画模式等设置',
                ),
              
              // 学生名单
              if (result.students != null && result.students!.isNotEmpty)
                _buildConflictPreviewItem(
                  icon: Icons.people,
                  title: '学生名单',
                  importCount: result.students!.length,
                  unit: '人',
                  conflict: conflictMap[ConflictType.students],
                  showClassDetails: true,
                ),
              
              // 奖品名单
              if (result.prizePools != null && result.prizePools!.isNotEmpty) ...[
                _buildConflictPreviewItem(
                  icon: Icons.card_giftcard,
                  title: '奖品名单',
                  importCount: result.prizePools!.length,
                  unit: '个奖池',
                  conflict: conflicts.any((c) => c.type == ConflictType.prizes && c.hasConflict)
                      ? ConflictInfo(type: ConflictType.prizes, existingCount: 1, importCount: 0)
                      : null,
                ),
                ...result.prizePools!.entries.map((entry) {
                  final poolConflict = conflicts.firstWhere(
                    (c) => c.type == ConflictType.prizes && c.poolName == entry.key,
                    orElse: () => ConflictInfo(
                      type: ConflictType.prizes,
                      poolName: entry.key,
                      existingCount: 0,
                      importCount: entry.value.length,
                    ),
                  );
                  return Padding(
                    padding: const EdgeInsets.only(left: 32, top: 4),
                    child: Row(
                      children: [
                        Text(
                          '• ${entry.key}: ${entry.value.length} 个奖品',
                          style: TextStyle(
                            color: poolConflict.hasConflict ? Colors.orange : null,
                          ),
                        ),
                        if (poolConflict.hasConflict) ...[
                          const SizedBox(width: 8),
                          Text(
                            '(已有 ${poolConflict.existingCount} 个)',
                            style: const TextStyle(color: Colors.orange, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              ],
              
              if (result.hasWarnings) ...[
                const SizedBox(height: 16),
                const Text(
                  '警告：',
                  style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                ),
                ...result.warnings.map((w) => Text('• $w')),
              ],
              
              if (hasConflicts) ...[
                const SizedBox(height: 16),
                const Text(
                  '请选择处理方式：',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
        ),
        actions: hasConflicts
            ? [
                TextButton(
                  onPressed: () => Navigator.pop(context, MergeStrategy.cancel),
                  child: const Text('取消导入'),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, MergeStrategy.overwrite),
                  child: const Text('覆盖'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, MergeStrategy.merge),
                  child: const Text('合并'),
                ),
              ]
            : [
                TextButton(
                  onPressed: () => Navigator.pop(context, MergeStrategy.cancel),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, MergeStrategy.merge),
                  child: const Text('确认导入'),
                ),
              ],
      ),
    );
  }

  Widget _buildConflictPreviewItem({
    required IconData icon,
    required String title,
    required int importCount,
    required String unit,
    ConflictInfo? conflict,
    bool showClassDetails = false,
  }) {
    final hasConflict = conflict?.hasConflict ?? false;
    final color = hasConflict ? Colors.orange : null;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                        if (hasConflict) ...[
                          const SizedBox(width: 8),
                          Text(
                            '- 存在冲突',
                            style: TextStyle(
                              color: color,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (hasConflict)
                      Text(
                        conflict!.description,
                        style: TextStyle(color: color, fontSize: 12),
                      )
                    else
                      Text(
                        '导入 $importCount $unit',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
          // 显示班级详情（仅学生名单）
          if (showClassDetails && conflict?.classStudents != null) ...[
            const SizedBox(height: 4),
            ...conflict!.classStudents!.map((cs) => Padding(
              padding: const EdgeInsets.only(left: 32, top: 2),
              child: Row(
                children: [
                  Text(
                    '• ${cs.className}',
                    style: TextStyle(
                      color: cs.existingCount > 0 ? Colors.orange : null,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '已有 ${cs.existingCount} 人，导入 ${cs.importCount} 人',
                    style: TextStyle(
                      color: cs.existingCount > 0 ? Colors.orange : Colors.grey,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }

  Widget _buildPreviewItem(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }
}
