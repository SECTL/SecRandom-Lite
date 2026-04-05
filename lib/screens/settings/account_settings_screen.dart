import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/auth_provider.dart';

class AccountSettingsScreen extends StatelessWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final userInfo = authProvider.userInfo;

    return Scaffold(
      appBar: AppBar(
        title: const Text('账户设置'),
      ),
      body: ListView(
        children: [
          // 用户信息卡片
          _buildUserInfoCard(context, userInfo),

          const SizedBox(height: 16),

          // 账户详情
          _buildAccountDetails(context, userInfo),

          const SizedBox(height: 32),

          // 退出登录按钮
          _buildLogoutButton(context),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildUserInfoCard(BuildContext context, userInfo) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // 大头像
            CircleAvatar(
              radius: 50,
              backgroundImage: userInfo?.avatarUrl != null
                  ? CachedNetworkImageProvider(userInfo!.avatarUrl!)
                  : null,
              child: userInfo?.avatarUrl == null
                  ? Text(
                      userInfo?.name[0] ?? 'U',
                      style: const TextStyle(fontSize: 32),
                    )
                  : null,
            ),
            const SizedBox(height: 16),
            // 用户名
            Text(
              userInfo?.name ?? '用户',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            // 邮箱
            Text(
              userInfo?.email ?? '',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountDetails(BuildContext context, userInfo) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          ListTile(
            title: const Text('账户详情'),
            titleTextStyle: Theme.of(context).textTheme.titleMedium,
          ),
          const Divider(height: 1),
          _buildDetailItem(
            context,
            icon: Icons.badge_outlined,
            label: '用户 ID',
            value: userInfo?.userId ?? '-',
          ),
          _buildDetailItem(
            context,
            icon: Icons.shield_outlined,
            label: '权限等级',
            value: userInfo?.role ?? '-',
          ),
          if (userInfo?.githubUsername != null)
            _buildDetailItem(
              context,
              icon: Icons.code,
              label: 'GitHub',
              value: userInfo!.githubUsername!,
            ),
          _buildDetailItem(
            context,
            icon: Icons.calendar_today_outlined,
            label: '注册时间',
            value: _formatDate(userInfo?.createdAt),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return ListTile(
      leading: Icon(icon, size: 20),
      title: Text(label),
      subtitle: Text(value),
      dense: true,
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: OutlinedButton.icon(
        onPressed: () => _handleLogout(context),
        icon: const Icon(Icons.logout),
        label: const Text('退出登录'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
          side: BorderSide(
            color: Theme.of(context).colorScheme.error,
          ),
          minimumSize: const Size(double.infinity, 48),
        ),
      ),
    );
  }

  void _handleLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出登录吗？本地数据将保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final authProvider = context.read<AuthProvider>();
              await authProvider.logout();
              if (context.mounted) {
                Navigator.pop(context); // 关闭对话框
                Navigator.pop(context); // 返回设置页面

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已退出登录')),
                );
              }
            },
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return '-';
    try {
      final date = DateTime.parse(isoDate);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return '-';
    }
  }
}
