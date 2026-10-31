import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/auth_provider.dart';
import '../../utils/logger.dart';
export '../../providers/auth_provider.dart';

/// AccountSettingsScreen - 账户设置页面
///
/// - 窄屏: 使用 Scaffold 完整页面
/// - 宽屏: 使用 AccountSettingsBody 作为 SettingsLayout 的 Detail 区域
/// - 各宽度统一竖向流布局，最大行宽 1200px，无外层卡片
class AccountSettingsScreen extends StatelessWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('账户设置')),
      body: const AccountSettingsBody(),
    );
  }
}

/// 账户设置的主体内容，可嵌入 SettingsLayout 的 Detail 区域
class AccountSettingsBody extends StatelessWidget {
  const AccountSettingsBody({super.key});

  static const double maxContentWidth = 1200;

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    // 仅会话恢复阶段整页加载；浏览器授权等待保留登录空态骨架
    if (authProvider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!authProvider.isLoggedIn) {
      return _buildLoginPrompt(context, authProvider);
    }

    return _buildUserInfo(context, authProvider);
  }

  Widget _buildLoginPrompt(BuildContext context, AuthProvider authProvider) {
    final theme = Theme.of(context);
    final isLoggingIn = authProvider.isLoggingIn;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxContentWidth),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.account_circle_outlined,
                size: 80,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.5,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '登录 SECTL 账户',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '登录后可同步数据、查看账户信息。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (isLoggingIn) ...[
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('等待浏览器授权…'),
                  ],
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => _handleCancelLogin(context, authProvider),
                  icon: const Icon(Icons.close),
                  label: const Text('取消登录'),
                ),
              ] else
                FilledButton.icon(
                  onPressed: () => _handleLogin(context, authProvider),
                  icon: const Icon(Icons.login),
                  label: const Text('登录'),
                ),
              if (!isLoggingIn && authProvider.error != null) ...[
                const SizedBox(height: 16),
                Text(
                  authProvider.error!,
                  style: TextStyle(color: theme.colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserInfo(BuildContext context, AuthProvider authProvider) {
    final userInfo = authProvider.userInfo!;

    // 各宽度统一为竖向流布局（头像身份 → 详情 chips → 退出），无外层卡片
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxContentWidth),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _buildNarrowFlow(context, userInfo, authProvider),
        ),
      ),
    );
  }

  Widget _buildNarrowFlow(
    BuildContext context,
    userInfo,
    AuthProvider authProvider,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _buildAvatar(context, userInfo, radius: 36),
            const SizedBox(width: 16),
            Expanded(child: _buildIdentity(context, userInfo)),
          ],
        ),
        const SizedBox(height: 20),
        _buildDetails(context, userInfo),
        const SizedBox(height: 24),
        _buildLogoutButton(context, authProvider),
      ],
    );
  }

  Widget _buildAvatar(
    BuildContext context,
    userInfo, {
    required double radius,
  }) {
    final hasAvatar =
        userInfo.avatarUrl != null && userInfo.avatarUrl!.isNotEmpty;

    return CircleAvatar(
      radius: radius,
      backgroundImage: hasAvatar
          ? CachedNetworkImageProvider(userInfo.avatarUrl!)
          : null,
      onBackgroundImageError: hasAvatar ? (_, __) {} : null,
      child: hasAvatar
          ? null
          : Text(
              userInfo.name.isNotEmpty ? userInfo.name[0].toUpperCase() : 'U',
              style: TextStyle(fontSize: radius),
            ),
    );
  }

  Widget _buildIdentity(BuildContext context, userInfo) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          userInfo.name,
          style: theme.textTheme.titleLarge,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          userInfo.email,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildDetails(BuildContext context, userInfo) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _buildDetailChip(
          context,
          icon: Icons.badge_outlined,
          label: '用户 ID',
          value: userInfo.userId,
          copyable: true,
        ),
        _buildDetailChip(
          context,
          icon: Icons.shield_outlined,
          label: '权限等级',
          value: userInfo.permission,
        ),
        if (userInfo.githubUsername != null &&
            userInfo.githubUsername!.isNotEmpty)
          _buildDetailChip(
            context,
            icon: Icons.code,
            label: 'GitHub',
            value: userInfo.githubUsername!,
            copyable: true,
          ),
        _buildDetailChip(
          context,
          icon: Icons.calendar_today_outlined,
          label: '注册时间',
          value: _formatDate(userInfo.createdAt),
        ),
      ],
    );
  }

  Widget _buildDetailChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    bool copyable = false,
  }) {
    final theme = Theme.of(context);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.55,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (copyable) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.copy_rounded,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );

    if (!copyable) return chip;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _copyValue(context, value, label: label),
      child: chip,
    );
  }

  Future<void> _copyValue(
    BuildContext context,
    String value, {
    required String label,
  }) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已复制$label')));
  }

  Widget _buildLogoutButton(BuildContext context, AuthProvider authProvider) {
    return OutlinedButton.icon(
      onPressed: authProvider.isLoading
          ? null
          : () => _handleLogout(context, authProvider),
      icon: const Icon(Icons.logout),
      label: const Text('退出登录'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.error,
        side: BorderSide(color: Theme.of(context).colorScheme.error),
        minimumSize: const Size(double.infinity, 48),
      ),
    );
  }

  Future<void> _handleLogin(
    BuildContext context,
    AuthProvider authProvider,
  ) async {
    authProvider.clearError();
    try {
      await authProvider.login();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('登录成功'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } on LoginCancelledException {
      // 用户主动取消：不弹错误
    } catch (e) {
      logger.e('登录失败', error: e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(describeAuthError(e)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _handleCancelLogin(
    BuildContext context,
    AuthProvider authProvider,
  ) async {
    await authProvider.cancelLogin();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已取消登录')));
    }
  }

  void _handleLogout(BuildContext context, AuthProvider authProvider) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('要退出登录吗？本地数据将保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await authProvider.logout();
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('已退出登录')));
              }
            },
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return isoDate;
    }
  }
}
