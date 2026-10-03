import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/cloud/cloud_sync_service.dart';
import '../../utils/logger.dart';

/// CloudSyncScreen - 云同步设置页面
///
/// - 窄屏: 使用 Scaffold 完整页面
/// - 宽屏: 使用 CloudSyncBody 作为 SettingsLayout 的 Detail 区域
class CloudSyncScreen extends StatelessWidget {
  const CloudSyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('云同步')),
      body: const CloudSyncBody(),
    );
  }
}

/// 云同步设置的主体内容，可嵌入 SettingsLayout 的 Detail 区域
class CloudSyncBody extends StatefulWidget {
  const CloudSyncBody({super.key});

  @override
  State<CloudSyncBody> createState() => _CloudSyncBodyState();
}

class _CloudSyncBodyState extends State<CloudSyncBody> {
  bool _isSyncing = false;
  bool _isBackupBusy = false;
  String? _statusMessage;

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    final authProvider = context.watch<AuthProvider>();
    final syncService = appProvider.cloudSyncService;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 登录状态提示
        if (!authProvider.isLoggedIn)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.cloud_off, color: Theme.of(context).colorScheme.onErrorContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '需要登录 SECTL 账户才能使用云同步',
                      style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // 同步状态
        _buildStatusCard(context, syncService),

        const SizedBox(height: 16),

        // 自动同步开关
        Card(
          child: SwitchListTile(
            title: const Text('自动同步'),
            subtitle: const Text('数据变更后自动上传，登录时自动与云端合并'),
            value: appProvider.cloudSyncEnabled,
            onChanged: (value) => appProvider.setCloudSyncEnabled(value),
          ),
        ),

        const SizedBox(height: 16),

        // 同步操作
        _buildSyncActions(context, appProvider, authProvider),

        const SizedBox(height: 16),

        // 同步数据说明
        _buildInfoCard(context),
      ],
    );
  }

  Widget _buildStatusCard(BuildContext context, CloudSyncService syncService) {
    final theme = Theme.of(context);
    final status = syncService.status;

    IconData icon;
    String label;
    Color color;

    switch (status) {
      case SyncStatus.syncing:
        icon = Icons.sync;
        label = '同步中...';
        color = theme.colorScheme.primary;
        break;
      case SyncStatus.success:
        icon = Icons.cloud_done;
        label = '同步完成';
        color = theme.colorScheme.primary;
        break;
      case SyncStatus.error:
        icon = Icons.cloud_off;
        label = '同步失败';
        color = theme.colorScheme.error;
        break;
      case SyncStatus.idle:
        icon = Icons.cloud_outlined;
        label = '待同步';
        color = theme.colorScheme.onSurfaceVariant;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (status == SyncStatus.syncing)
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: color),
                  )
                else
                  Icon(icon, color: color, size: 24),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(color: color),
                ),
              ],
            ),
            if (syncService.lastSyncAt != null) ...[
              const SizedBox(height: 8),
              Text(
                '上次同步: ${_formatTime(syncService.lastSyncAt!)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (syncService.lastError != null) ...[
              const SizedBox(height: 8),
              Text(
                syncService.lastError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (_statusMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _statusMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSyncActions(
    BuildContext context,
    AppProvider appProvider,
    AuthProvider authProvider,
  ) {
    final enabled = authProvider.isLoggedIn && !_isSyncing;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '同步操作',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: enabled ? _handleSyncNow : null,
              icon: _isSyncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: Text(_isSyncing ? '同步中...' : '立即同步'),
            ),
            const SizedBox(height: 8),
            Text(
              '立即同步：先拉取云端并合并，再上传本地变更（含离线期间记录）',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (enabled && !_isBackupBusy)
                        ? _handleUploadBackup
                        : null,
                    icon: const Icon(Icons.backup_outlined),
                    label: const Text('上传备份'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (enabled && !_isBackupBusy)
                        ? _handleRestoreBackup
                        : null,
                    icon: const Icon(Icons.settings_backup_restore),
                    label: const Text('从备份恢复'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '备份为完整快照，上传前替换旧备份；恢复按记录合并，不覆盖本地已有数据。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '同步内容',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _buildInfoRow(context, Icons.people, '学生名单', '各班级学生信息'),
            _buildInfoRow(context, Icons.bar_chart, '抽取统计', '每台设备贡献求和（公平抽取依据）'),
            _buildInfoRow(context, Icons.history, '历史记录', '每台设备独立历史流，拉取时按 uid 合并去重'),
            const SizedBox(height: 8),
            Text(
              '离线期间的记录会保留在本地队列，登录或恢复网络后自动补传；重复上传不会产生重复记录。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, IconData icon, String title, String subtitle) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium),
                Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${time.month}/${time.day} ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _handleSyncNow() async {
    final appProvider = context.read<AppProvider>();
    setState(() {
      _isSyncing = true;
      _statusMessage = null;
    });

    try {
      final ok = await appProvider.syncNow();
      if (!mounted) return;
      setState(() {
        _statusMessage = ok ? '同步完成' : '同步失败，请检查网络和登录状态';
      });
    } catch (e) {
      logger.e('同步失败', error: e);
      if (!mounted) return;
      setState(() {
        _statusMessage = '同步失败: $e';
      });
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _handleUploadBackup() async {
    final appProvider = context.read<AppProvider>();
    setState(() {
      _isBackupBusy = true;
      _statusMessage = null;
    });
    try {
      final ok = await appProvider.uploadBackupToCloud();
      if (!mounted) return;
      setState(() {
        _statusMessage = ok ? '备份已上传' : '备份上传失败，请检查存储空间和登录状态';
      });
    } catch (e) {
      logger.e('备份上传失败', error: e);
      if (!mounted) return;
      setState(() => _statusMessage = '备份上传失败: $e');
    } finally {
      if (mounted) setState(() => _isBackupBusy = false);
    }
  }

  Future<void> _handleRestoreBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从备份恢复'),
        content: const Text('将下载最近一次云备份并合并到本地（按记录去重，不覆盖本地已有数据）。继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final appProvider = context.read<AppProvider>();
    setState(() {
      _isBackupBusy = true;
      _statusMessage = null;
    });
    try {
      final merged = await appProvider.restoreFromCloudBackup();
      if (!mounted) return;
      setState(() {
        _statusMessage = merged < 0 ? '云端没有可用备份' : '恢复完成，合并 $merged 条记录';
      });
    } catch (e) {
      logger.e('备份恢复失败', error: e);
      if (!mounted) return;
      setState(() => _statusMessage = '恢复失败: $e');
    } finally {
      if (mounted) setState(() => _isBackupBusy = false);
    }
  }

}
