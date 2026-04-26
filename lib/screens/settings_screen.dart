import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/app_provider.dart';
import '../providers/auth_provider.dart';
import 'settings/about_settings_screen.dart';
import 'settings/draw_settings_screen.dart';
import 'settings/lottery_settings_screen.dart';
import 'settings/personalization_settings_screen.dart';
import 'settings/rollcall_settings_screen.dart';
import 'settings/account_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          // 账户设置卡片
          _buildAccountCard(context),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.people),
            title: const Text('点名名单设置'),
            subtitle: const Text('管理班级、学生姓名及分组信息'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const RollCallSettingsScreen(),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.card_giftcard),
            title: const Text('抽奖设置'),
            subtitle: const Text('管理奖池、奖品及抽奖配置'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const LotterySettingsScreen(),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.casino),
            title: const Text('抽取设置'),
            subtitle: const Text('配置点名公平抽取与不重复抽取开关'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const DrawSettingsScreen(),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.text_fields),
            title: const Text('个性化'),
            subtitle: const Text('调整抽人/抽奖结果字号'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const PersonalizationSettingsScreen(),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            title: const Text('深色模式'),
            trailing: DropdownButton<ThemeMode>(
              value: appProvider.themeMode,
              onChanged: (ThemeMode? newValue) {
                if (newValue != null) {
                  appProvider.setThemeMode(newValue);
                }
              },
              items: const [
                DropdownMenuItem(value: ThemeMode.light, child: Text('浅色')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('深色')),
                DropdownMenuItem(value: ThemeMode.system, child: Text('跟随系统')),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('关于'),
            subtitle: const Text('Secrandom Lite v1.0.0'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const AboutSettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final isLoggedIn = authProvider.isLoggedIn;
    final userInfo = authProvider.userInfo;

    return InkWell(
      onTap: () {
        if (isLoggedIn) {
          // 已登录：进入账户设置详情
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AccountSettingsScreen(),
            ),
          );
        } else {
          // 未登录：触发登录流程
          _showLoginDialog(context);
        }
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // 头像
            CircleAvatar(
              radius: 30,
              backgroundImage: isLoggedIn && userInfo?.avatarUrl != null
                  ? CachedNetworkImageProvider(userInfo!.avatarUrl!)
                  : null,
              child: isLoggedIn && userInfo?.avatarUrl == null
                  ? Text(userInfo?.name[0] ?? 'U')
                  : const Icon(Icons.person_outline),
            ),
            const SizedBox(width: 16),
            // 用户信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isLoggedIn ? userInfo?.name ?? '用户' : '游客模式',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isLoggedIn ? userInfo?.email ?? '' : '点击登录以同步数据',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            // 箭头图标
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  void _showLoginDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('登录 SECTL 账户'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('登录后可以：'),
            const SizedBox(height: 8),
            _buildFeatureItem('☁️ 云端同步数据'),
            _buildFeatureItem('📱 多设备访问'),
            _buildFeatureItem('🔒 数据安全备份'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _handleLogin(context);
            },
            child: const Text('使用 SECTL 登录'),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [const SizedBox(width: 16), Text(text)]),
    );
  }

  Future<void> _handleLogin(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      // 显示加载指示器
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // 执行登录
      await authProvider.login();

      // 关闭加载指示器
      navigator.pop();

      // 显示成功提示
      messenger.showSnackBar(const SnackBar(content: Text('登录成功！')));
    } catch (e) {
      // 关闭加载指示器
      navigator.pop();

      // 显示错误
      messenger.showSnackBar(SnackBar(content: Text('登录失败：$e')));
    }
  }
}
