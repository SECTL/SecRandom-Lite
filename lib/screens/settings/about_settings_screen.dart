import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// AboutSettingsScreen - 关于页面
///
/// - 窄屏: 使用 Scaffold 完整页面
/// - 宽屏: 使用 AboutSettingsBody 作为 SettingsLayout 的 Detail 区域
class AboutSettingsScreen extends StatelessWidget {
  const AboutSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: const AboutSettingsBody(),
    );
  }
}

/// 关于页面的主体内容，可嵌入 SettingsLayout 的 Detail 区域
class AboutSettingsBody extends StatelessWidget {
  const AboutSettingsBody({super.key});

  static const String _appName = 'SecRandom Lite';
  static const String _version = 'v1.0.2';
  static const String _repositoryUrl =
      'https://github.com/SECTL/SecRandom-Lite';
  static const String _authorGithubUrl = 'https://github.com/LeafS825';
  static const String _organizationUrl = 'https://github.com/SECTL';
  static const String _organizationWebsiteUrl = 'https://sectl.cn';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  radius: 28,
                  backgroundImage: AssetImage('assets/icon/app_icon.png'),
                ),
                const SizedBox(height: 16),
                Text(
                  _appName,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '一款面向课堂场景的随机点名工具，帮助你更高效地完成点名与抽取。',
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.code_outlined),
                title: const Text('项目仓库'),
                subtitle: const Text('查看源码、更新记录与后续维护信息'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => _launchUrl(_repositoryUrl),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.group_outlined),
                title: const Text('项目组织'),
                subtitle: const Text('SECTL'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => _launchUrl(_organizationUrl),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.language_outlined),
                title: const Text('组织官网'),
                subtitle: const Text('sectl.cn'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => _launchUrl(_organizationWebsiteUrl),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('项目作者'),
                subtitle: const Text('LeafS825'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => _launchUrl(_authorGithubUrl),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
