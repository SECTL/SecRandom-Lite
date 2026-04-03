import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/app_provider.dart';
import 'settings/draw_settings_screen.dart';
import 'settings/lottery_settings_screen.dart';
import 'settings/personalization_settings_screen.dart';
import 'settings/rollcall_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
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
            subtitle: const Text('Secrandom Lite v0.0.10'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () async {
              final uri = Uri.parse(
                'https://github.com/LeafS825/SecRandom-lutter',
              );
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ],
      ),
    );
  }
}
