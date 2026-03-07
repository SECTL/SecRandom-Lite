import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_provider.dart';

class DrawSettingsScreen extends StatelessWidget {
  const DrawSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('抽取设置')),
      body: Consumer<AppProvider>(
        builder: (context, appProvider, _) {
          return ListView(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.repeat),
                title: const Text('启用不重复抽取'),
                subtitle: const Text('开启后抽中过的学生在本轮不会再次被抽中；关闭后每次都从当前筛选全量中抽取。'),
                value: appProvider.nonRepeatEnabled,
                onChanged: appProvider.setNonRepeatEnabled,
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.balance),
                title: const Text('启用公平抽取'),
                subtitle: const Text('开启后按历史抽取次数动态计算权重，降低重复抽中概率。'),
                value: appProvider.fairDrawEnabled,
                onChanged: appProvider.setFairDrawEnabled,
              ),
            ],
          );
        },
      ),
    );
  }
}
