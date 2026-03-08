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
            children: [
              ListTile(
                leading: const Icon(Icons.person_search),
                title: const Text('抽人结果字号'),
                subtitle: Text(
                  appProvider.rollcallResultFontSize.toStringAsFixed(0),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Slider(
                  value: appProvider.rollcallResultFontSize,
                  min: 24,
                  max: 72,
                  divisions: 48,
                  label: appProvider.rollcallResultFontSize.toStringAsFixed(0),
                  onChanged: appProvider.setRollcallResultFontSize,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.card_giftcard),
                title: const Text('抽奖结果字号'),
                subtitle: Text(
                  appProvider.lotteryResultFontSize.toStringAsFixed(0),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Slider(
                  value: appProvider.lotteryResultFontSize,
                  min: 24,
                  max: 72,
                  divisions: 48,
                  label: appProvider.lotteryResultFontSize.toStringAsFixed(0),
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
