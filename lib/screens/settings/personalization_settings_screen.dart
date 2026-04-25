import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_config.dart';
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
                children: [
                  _AnimationModeTile(
                    title: '点名动画模式',
                    currentMode: appProvider.rollcallAnimationMode,
                    onModeChanged: appProvider.setRollcallAnimationMode,
                  ),
                  const SizedBox(height: 12),
                  _FontSizeSliderTile(
                    label: '抽人结果字号',
                    value: appProvider.rollcallResultFontSize,
                    onChanged: appProvider.setRollcallResultFontSize,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SettingsSectionCard(
                title: '抽奖设置',
                icon: Icons.card_giftcard,
                children: [
                  _AnimationModeTile(
                    title: '抽奖动画模式',
                    currentMode: appProvider.lotteryAnimationMode,
                    onModeChanged: appProvider.setLotteryAnimationMode,
                  ),
                  const SizedBox(height: 12),
                  _FontSizeSliderTile(
                    label: '抽奖结果字号',
                    value: appProvider.lotteryResultFontSize,
                    onChanged: appProvider.setLotteryResultFontSize,
                  ),
                ],
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
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

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
        ...children,
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

const List<DropdownMenuItem<AnimationMode>> _animationModeOptions = [
  DropdownMenuItem(
    value: AnimationMode.manualStop,
    child: Text('手动停止'),
  ),
  DropdownMenuItem(
    value: AnimationMode.auto,
    child: Text('自动播放'),
  ),
  DropdownMenuItem(
    value: AnimationMode.none,
    child: Text('无动画'),
  ),
];

class _AnimationModeTile extends StatelessWidget {
  const _AnimationModeTile({
    required this.title,
    required this.currentMode,
    required this.onModeChanged,
  });

  final String title;
  final AnimationMode currentMode;
  final ValueChanged<AnimationMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.animation_outlined),
      title: Text(title),
      trailing: SizedBox(
        width: 140,
        child: DropdownButtonFormField<AnimationMode>(
          initialValue: currentMode,
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(),
          ),
          items: _animationModeOptions,
          onChanged: (value) {
            if (value != null) {
              onModeChanged(value);
            }
          },
        ),
      ),
    );
  }
}
