import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../services/data_export_service.dart';
import '../../services/data_import_service.dart';
import '../../services/log_service.dart';
import 'log_viewer_screen.dart';

/// DataManagementScreen - 数据管理页面
///
/// - 窄屏: 使用 Scaffold 完整页面，垂直列表
/// - 宽屏: 使用 DataManagementBody 作为 SettingsLayout 的 Detail 区域
///   - 采用三栏网格布局：导出数据、导入数据、日志管理
class DataManagementScreen extends StatefulWidget {
  const DataManagementScreen({super.key});

  @override
  State<DataManagementScreen> createState() => _DataManagementScreenState();
}

class _DataManagementScreenState extends State<DataManagementScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('数据管理')),
      body: const DataManagementBody(),
    );
  }
}

/// 数据管理的主体内容，可嵌入 SettingsLayout 的 Detail 区域
class DataManagementBody extends StatefulWidget {
  const DataManagementBody({super.key});

  @override
  State<DataManagementBody> createState() => _DataManagementBodyState();
}

class _DataManagementBodyState extends State<DataManagementBody> {
  final DataExportService _exportService = DataExportService();
  final DataImportService _importService = DataImportService();
  final AppLogService _logService = AppLogService();

  final Map<ExportType, bool> _exportOptions = {
    ExportType.history: true,
    ExportType.lottery: true,
    ExportType.config: true,
    ExportType.students: true,
    ExportType.prizes: true,
  };

  bool _isExporting = false;
  bool _isImporting = false;

  bool _loggingEnabled = true;
  int _logCount = 0;
  bool _isLoadingLogInfo = true;

  @override
  void initState() {
    super.initState();
    _loadLogInfo();
  }

  Future<void> _loadLogInfo() async {
    final enabled = await _logService.isLoggingEnabled();
    final logs = await _logService.getLogs();
    setState(() {
      _loggingEnabled = enabled;
      _logCount = logs.length;
      _isLoadingLogInfo = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;

        if (isWide) {
          return _buildWideLayout();
        } else {
          return _buildNarrowLayout();
        }
      },
    );
  }

  Widget _buildNarrowLayout() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildExportSectionCard(),
        const SizedBox(height: 12),
        _buildImportSectionCard(),
        const SizedBox(height: 12),
        _buildLogSectionCard(),
      ],
    );
  }

  Widget _buildWideLayout() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _buildExportSectionCard(),
        const SizedBox(height: 16),
        _buildImportSectionCard(),
        const SizedBox(height: 16),
        _buildLogSectionCard(),
      ],
    );
  }

  Widget _buildExportSectionCard() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
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
              subtitle: const Text('选择要导出的数据类型。'),
            ),
            const SizedBox(height: 8),
            ..._buildExportCheckboxes(),
            const SizedBox(height: 12),
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
          ],
        ),
      ),
    );
  }

  List<Widget> _buildExportCheckboxes() {
    return _exportOptions.entries.map((entry) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
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
          dense: true,
        ),
      );
    }).toList();
  }

  Widget _buildImportSectionCard() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
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
              subtitle: const Text('从备份文件中恢复数据。'),
            ),
            const SizedBox(height: 8),
            Text(
              '支持 .json 和 .zip 格式的备份文件。导入前建议先导出当前数据作为备份。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
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
        ),
      ),
    );
  }

  Widget _buildLogSectionCard() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.terminal, color: Theme.of(context).colorScheme.primary),
              title: Text(
                '日志管理',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text('查看、导出或清除应用日志。'),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('记录日志'),
              subtitle: Text(
                _loggingEnabled ? '正在记录日志（已记录 $_logCount 条）' : '日志记录已关闭',
              ),
              value: _loggingEnabled,
              onChanged: _isLoadingLogInfo ? null : _toggleLogging,
              contentPadding: EdgeInsets.zero,
            ),
            if (_loggingEnabled) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isLoadingLogInfo || _logCount == 0 ? null : _viewLogs,
                  icon: const Icon(Icons.visibility, size: 18),
                  label: const Text('查看日志'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoadingLogInfo || _logCount == 0 ? null : _exportLogs,
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('导出'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoadingLogInfo || _logCount == 0 ? null : _clearLogs,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('清除'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
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
        final result = await _exportService.exportDataAsBytes(selectedTypes);
        _exportService.downloadFile(result.fileName, result.bytes);
        
        if (mounted) {
          _showSnackBar('导出成功！文件已开始下载');
        }
      } else {
        String? savePath = await FilePicker.platform.getDirectoryPath(
          dialogTitle: '选择导出保存位置',
        );

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
        withData: kIsWeb,
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _isImporting = false);
        return;
      }

      ImportResult importResult;
      
      if (kIsWeb) {
        final file = result.files.single;
        final bytes = file.bytes;
        if (bytes == null) {
          _showSnackBar('无法读取文件内容', isError: true);
          setState(() => _isImporting = false);
          return;
        }
        importResult = await _importService.importFromBytes(bytes, file.name);
      } else {
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

      final conflicts = await _importService.checkConflicts(importResult);
      final strategy = await _showImportDialog(importResult, conflicts);

      if (strategy == null || !mounted) {
        setState(() => _isImporting = false);
        return;
      }

      if (strategy == MergeStrategy.cancel) {
        setState(() => _isImporting = false);
        return;
      }

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
          final appProvider = Provider.of<AppProvider>(context, listen: false);
          await appProvider.reloadData();
          if (importResult.historyRecords != null ||
              importResult.lotteryRecords != null) {
            await appProvider.syncLocalHistoryToCloud();
          }
          if (!mounted) return;
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
              
              if (result.historyRecords != null && result.historyRecords!.isNotEmpty)
                _buildConflictPreviewItem(
                  icon: Icons.history,
                  title: '点名历史',
                  importCount: result.historyRecords!.length,
                  unit: '条记录',
                  conflict: conflictMap[ConflictType.history],
                ),
              
              if (result.lotteryRecords != null && result.lotteryRecords!.isNotEmpty)
                _buildConflictPreviewItem(
                  icon: Icons.card_giftcard,
                  title: '抽奖历史',
                  importCount: result.lotteryRecords!.length,
                  unit: '条记录',
                  conflict: conflictMap[ConflictType.lottery],
                ),
              
              if (result.config != null)
                _buildPreviewItem(
                  Icons.settings,
                  '应用配置',
                  '主题、动画模式等设置',
                ),
              
              if (result.students != null && result.students!.isNotEmpty)
                _buildConflictPreviewItem(
                  icon: Icons.people,
                  title: '学生名单',
                  importCount: result.students!.length,
                  unit: '人',
                  conflict: conflictMap[ConflictType.students],
                  showClassDetails: true,
                ),
              
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

  Future<void> _toggleLogging(bool value) async {
    await _logService.setLoggingEnabled(value);
    setState(() => _loggingEnabled = value);
    _showSnackBar(value ? '已开启日志记录' : '已关闭日志记录');
  }

  void _viewLogs() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LogViewerScreen()),
    ).then((_) => _loadLogInfo());
  }

  Future<void> _exportLogs() async {
    try {
      final logText = await _logService.exportLogsAsString();

      if (logText.isEmpty) {
        _showSnackBar('没有日志可导出');
        return;
      }

      if (kIsWeb) {
        final bytes = Uint8List.fromList(utf8.encode(logText));
        _exportService.downloadFile(
          'secrandom_logs_${DateTime.now().millisecondsSinceEpoch}.log',
          bytes,
        );
        if (mounted) {
          _showSnackBar('日志导出成功！文件已开始下载');
        }
      } else {
        final savePath = await FilePicker.platform.getDirectoryPath(
          dialogTitle: '选择日志保存位置',
        );

        if (savePath == null) return;

        final fileName = 'secrandom_logs_${DateTime.now().millisecondsSinceEpoch}.log';
        final file = File('$savePath${Platform.pathSeparator}$fileName');
        await file.writeAsString(logText);

        if (mounted) {
          _showSnackBar('日志导出成功！文件已保存到: ${file.path}');
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('导出日志失败: $e', isError: true);
      }
    }
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清除日志'),
        content: const Text('确定要清除所有日志记录吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('清除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _logService.clearLogs();
      await _loadLogInfo();
      if (mounted) {
        _showSnackBar('日志已清除');
      }
    }
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
