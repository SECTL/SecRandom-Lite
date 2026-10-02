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
  bool _isPushing = false;
  bool _isPulling = false;
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
    final enabled = authProvider.isLoggedIn && !_isPushing && !_isPulling;

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
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: enabled ? _handlePush : null,
                    icon: _isPushing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_upload),
                    label: Text(_isPushing ? '推送中...' : '推送到云端'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: enabled ? _handlePull : null,
                    icon: _isPulling
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_download),
                    label: Text(_isPulling ? '拉取中...' : '从云端拉取'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '推送：将本地数据上传到云端\n拉取：从云端下载并合并到本地',
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
            _buildInfoRow(context, Icons.bar_chart, '抽取统计', '每人被抽中次数（公平抽取依据）'),
            _buildInfoRow(context, Icons.history, '历史记录', '点名和抽奖历史（分片存储）'),
            const SizedBox(height: 8),
            Text(
              '公平抽取权重基于聚合统计计算，不依赖历史记录是否完整下载。',
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

  Future<void> _handlePush() async {
    final appProvider = context.read<AppProvider>();
    setState(() {
      _isPushing = true;
      _statusMessage = null;
    });

    try {
      final ok = await appProvider.pushToCloud();
      if (!mounted) return;
      setState(() {
        _statusMessage = ok ? '推送成功' : '推送失败，请检查网络和登录状态';
      });
    } catch (e) {
      logger.e('推送失败', error: e);
      if (!mounted) return;
      setState(() {
        _statusMessage = '推送失败: $e';
      });
    } finally {
      if (mounted) setState(() => _isPushing = false);
    }
  }

  Future<void> _handlePull() async {
    final appProvider = context.read<AppProvider>();

    // 确认对话框（含冲突解决选项）
    final resolution = await showDialog<ConflictResolution>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从云端拉取'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('拉取将合并云端数据到本地。'),
            const SizedBox(height: 8),
            const Text('合并策略：'),
            const SizedBox(height: 4),
            _buildResolutionOption(
              ctx,
              ConflictResolution.merge,
              '智能合并',
              '统计取较大值，名单以云端为准（推荐）',
            ),
            _buildResolutionOption(
              ctx,
              ConflictResolution.useRemote,
              '使用云端数据',
              '完全覆盖本地数据',
            ),
            _buildResolutionOption(
              ctx,
              ConflictResolution.keepLocal,
              '保留本地数据',
              '不做任何变更',
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ],
      ),
    );
    if (resolution == null) return;

    setState(() {
      _isPulling = true;
      _statusMessage = null;
    });

    try {
      final ok = await appProvider.pullFromCloud(conflictResolution: resolution);
      if (!mounted) return;
      setState(() {
        _statusMessage = ok ? '拉取成功' : '拉取失败，请检查网络和登录状态';
      });
    } catch (e) {
      logger.e('拉取失败', error: e);
      if (!mounted) return;
      setState(() {
        _statusMessage = '拉取失败: $e';
      });
    } finally {
      if (mounted) setState(() => _isPulling = false);
    }
  }

  Widget _buildResolutionOption(
    BuildContext ctx,
    ConflictResolution resolution,
    String title,
    String subtitle,
  ) {
    return InkWell(
      onTap: () => Navigator.pop(ctx, resolution),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              resolution == ConflictResolution.merge
                  ? Icons.merge_type
                  : resolution == ConflictResolution.useRemote
                      ? Icons.cloud_download
                      : Icons.phone_android,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
