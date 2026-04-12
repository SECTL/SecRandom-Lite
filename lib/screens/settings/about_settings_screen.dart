import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutSettingsScreen extends StatelessWidget {
  const AboutSettingsScreen({super.key});

  static const String _appName = 'Secrandom Lite';
  static const String _version = 'v0.0.10';
  static const String _repositoryUrl =
      'https://github.com/LeafS825/SecRandom-lutter';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: colorScheme.primaryContainer,
                    foregroundColor: colorScheme.onPrimaryContainer,
                    child: const Icon(Icons.info_outline, size: 28),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _appName,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '一款面向课堂场景的随机点名与抽奖工具，帮助你更高效地完成点名、抽取和简单活动管理。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '当前版本：$_version',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.code_outlined),
                  title: const Text('项目仓库'),
                  subtitle: const Text('查看源码、更新记录与后续维护信息'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: _openRepository,
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('项目作者'),
                  subtitle: Text('LeafS825'),
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.palette_outlined),
                  title: Text('界面风格'),
                  subtitle: Text('基于 Material 3 的简洁设置页设计'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              '感谢使用 $_appName。若你在使用中发现问题或有改进建议，欢迎前往项目仓库反馈。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openRepository() async {
    final uri = Uri.parse(_repositoryUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
