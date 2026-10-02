import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/app_provider.dart';
import '../widgets/settings_layout.dart';
import 'settings/about_settings_screen.dart';
import 'settings/account_settings_screen.dart';
import 'settings/cloud_sync_settings_screen.dart';
import 'settings/data_management_screen.dart';
import 'settings/draw_settings_screen.dart';
import 'settings/lottery_settings_screen.dart';
import 'settings/personalization_settings_screen.dart';
import 'settings/rollcall_settings_screen.dart';

/// SettingsScreen - 设置页面
///
/// - 窄屏 (< 900px): 使用移动端列表布局，点击项跳转到新页面
/// - 宽屏 (>= 900px): 使用 SettingsLayout 的 Master-Detail 布局
///   - 左侧：设置项导航列表（Master）
///   - 右侧：选中项的详细内容（Detail）
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsLayout(
      title: '设置',
      items: _buildSettingItems(),
      initialIndex: 1, // 默认显示点名名单
    );
  }

  List<SettingItem> _buildSettingItems() {
    return [
      SettingItem(
        title: '账户',
        icon: Icons.person_outline,
        pageBuilder: () => const AccountSettingsBody(),
        routeName: '/settings/account',
        leadingBuilder: (context) {
          final authProvider = context.watch<AuthProvider>();
          final isLoggedIn = kAccountEnabled && authProvider.isLoggedIn;
          final userInfo = authProvider.userInfo;

          if (isLoggedIn && userInfo?.avatarUrl != null) {
            return CircleAvatar(
              radius: 16,
              backgroundImage: CachedNetworkImageProvider(userInfo!.avatarUrl!),
            );
          }

          return CircleAvatar(
            radius: 16,
            child: isLoggedIn && userInfo?.name.isNotEmpty == true
                ? Text(
                    userInfo!.name[0].toUpperCase(),
                    style: const TextStyle(fontSize: 14),
                  )
                : const Icon(Icons.person_outline, size: 20),
          );
        },
      ),
      SettingItem(
        title: '点名名单',
        icon: Icons.people,
        pageBuilder: () => const RollCallSettingsBody(),
        routeName: '/settings/rollcall',
        applyMaxWidth: false,
        actionsBuilder: (context) {
          final provider = context.read<AppProvider>();
          return [
            TextButton.icon(
              onPressed: () => RollCallSettingsScreen.showQuickImportDialog(
                context,
                provider,
              ),
              icon: const Icon(Icons.file_upload, size: 18),
              label: const Text('快速导入'),
            ),
          ];
        },
      ),
      SettingItem(
        title: '抽奖名单',
        icon: Icons.card_giftcard,
        pageBuilder: () => const LotterySettingsBody(),
        routeName: '/settings/lottery',
        applyMaxWidth: false,
        actionsBuilder: (context) {
          return [
            TextButton.icon(
              onPressed: () => LotterySettingsBody.showQuickImport(),
              icon: const Icon(Icons.file_upload, size: 18),
              label: const Text('快速导入'),
            ),
          ];
        },
      ),
      SettingItem(
        title: '抽取设置',
        icon: Icons.casino,
        pageBuilder: () => const DrawSettingsBody(),
        routeName: '/settings/draw',
      ),
      SettingItem(
        title: '个性化',
        icon: Icons.text_fields,
        pageBuilder: () => const PersonalizationSettingsBody(),
        routeName: '/settings/personalization',
      ),
      SettingItem(
        title: '云同步',
        icon: Icons.cloud_sync_outlined,
        pageBuilder: () => const CloudSyncBody(),
        routeName: '/settings/cloud',
      ),
      SettingItem(
        title: '数据管理',
        icon: Icons.storage,
        pageBuilder: () => const DataManagementBody(),
        routeName: '/settings/data',
      ),
      SettingItem(
        title: '关于',
        icon: Icons.info,
        pageBuilder: () => const AboutSettingsBody(),
        routeName: '/settings/about',
      ),
    ];
  }
}
