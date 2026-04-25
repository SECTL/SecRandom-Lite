import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_provider.dart';

class PersonalizationSettingsScreen extends StatelessWidget {
  const PersonalizationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('个性化')),
      body: Consumer<AppProvider>(
        builder: (context, appProvider, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SettingsSectionCard(
                title: '抽人设置',
                icon: Icons.person_search,
                child: _FontSizeSliderTile(
                  label: '抽人结果字号',
                  value: appProvider.rollcallResultFontSize,
                  onChanged: appProvider.setRollcallResultFontSize,
                ),
              ),
              const SizedBox(height: 12),
              _SettingsSectionCard(
                title: '抽奖设置',
                icon: Icons.card_giftcard,
                child: _FontSizeSliderTile(
                  label: '抽奖结果字号',
                  value: appProvider.lotteryResultFontSize,
                  onChanged: appProvider.setLotteryResultFontSize,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SettingsSectionCard extends StatelessWidget {
  const _SettingsSectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 0),
          leading: Icon(icon),
          title: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        child,
        const Divider(height: 24),
      ],
    );
  }
}

class _FontSizeSliderTile extends StatelessWidget {
  const _FontSizeSliderTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final displayValue = value.toStringAsFixed(0);

    return Column(
      children: [
        ListTile(title: Text(label), trailing: Text(displayValue)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Slider(
            value: value,
            min: 24,
            max: 72,
            divisions: 48,
            label: displayValue,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
