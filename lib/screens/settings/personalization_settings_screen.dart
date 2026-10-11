import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_config.dart';
import '../../providers/app_provider.dart';
import '../../services/rollcall_quick_entry_service.dart';

/// PersonalizationSettingsScreen - 个性化设置页面
///
/// - 窄屏: 使用 Scaffold 完整页面，垂直列表
/// - 宽屏: 使用 PersonalizationSettingsBody 作为 SettingsLayout 的 Detail 区域
///   - 采用双栏并排卡片布局
class PersonalizationSettingsScreen extends StatelessWidget {
  const PersonalizationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('个性化')),
      body: const PersonalizationSettingsBody(),
    );
  }
}

/// 个性化设置的主体内容，可嵌入 SettingsLayout 的 Detail 区域
class PersonalizationSettingsBody extends StatelessWidget {
  const PersonalizationSettingsBody({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, appProvider, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 600;

            if (isWide) {
              return _buildWideLayout(context, appProvider);
            } else {
              return _buildNarrowLayout(context, appProvider);
            }
          },
        );
      },
    );
  }

  Widget _buildNarrowLayout(BuildContext context, AppProvider appProvider) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SettingsSectionCard(
          title: '主题',
          icon: Icons.palette,
          children: [
            _ThemeModeTile(
              currentMode: appProvider.themeMode,
              onModeChanged: appProvider.setThemeMode,
            ),
          ],
        ),
        const SizedBox(height: 12),
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
        const _FloatingWindowSection(spacing: 12),
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
  }

  Widget _buildWideLayout(BuildContext context, AppProvider appProvider) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SettingsSectionCard(
          title: '主题',
          icon: Icons.palette,
          children: [
            _ThemeModeTile(
              currentMode: appProvider.themeMode,
              onModeChanged: appProvider.setThemeMode,
            ),
          ],
        ),
        const SizedBox(height: 16),
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
        const SizedBox(height: 16),
        const _FloatingWindowSection(spacing: 16),
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
  }
}

/// 点名悬浮窗开关（仅 Windows 桌面）。
///
/// 不受支持的平台整块不渲染，也不占位，避免留下多余间距。
class _FloatingWindowSection extends StatelessWidget {
  const _FloatingWindowSection({required this.spacing});

  /// 卡片下方要留出的间距，跟随所在布局的卡片间距。
  final double spacing;

  @override
  Widget build(BuildContext context) {
    if (!RollCallQuickEntryService.instance.supportsFloatingWindow) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SettingsSectionCard(
          title: '点名悬浮窗',
          icon: Icons.picture_in_picture_alt_outlined,
          children: [_FloatingWindowTile()],
        ),
        SizedBox(height: spacing),
      ],
    );
  }
}

/// 开关本身自己持有状态：服务可能因创建失败把开关回落为关闭。
class _FloatingWindowTile extends StatefulWidget {
  const _FloatingWindowTile();

  @override
  State<_FloatingWindowTile> createState() => _FloatingWindowTileState();
}

class _FloatingWindowTileState extends State<_FloatingWindowTile> {
  final _quickEntryService = RollCallQuickEntryService.instance;
  StreamSubscription<bool>? _stateSubscription;
  bool _enabled = false;
  bool _loading = true;
  Map<String, int> _appearance = {'size': 80, 'color': 0xFFBDEAFF, 'radius': 18};
  Future<void> _pendingAppearance = Future<void>.value();

  void _changeAppearance(String key, int value) {
    setState(() => _appearance = {..._appearance, key: value});
    final appearance = Map<String, int>.from(_appearance);
    _pendingAppearance = _pendingAppearance.catchError((_) {}).then((_) async {
      try {
        await _quickEntryService.saveAppearance(appearance);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法更新悬浮窗外观')),
        );
      }
    });
  }

  Future<void> _chooseCustomColor() async {
    final controller = TextEditingController(text: _appearance['color']!.toRadixString(16).substring(2).toUpperCase());
    final color = await showDialog<int>(context: context, builder: (context) {
      return AlertDialog(
        title: const Text('自定义背景色'),
        content: TextField(controller: controller, maxLength: 6,
          decoration: const InputDecoration(labelText: '六位十六进制颜色', prefixText: '#', hintText: 'BDEAFF')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(onPressed: () {
            final text = controller.text.trim();
            if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(text)) {
              Navigator.pop(context, 0xFF000000 | int.parse(text, radix: 16));
            }
          }, child: const Text('确定')),
        ],
      );
    });
    if (color != null && mounted) _changeAppearance('color', color);
  }

  @override
  void initState() {
    super.initState();
    _stateSubscription = _quickEntryService.floatingWindowState.listen((
      enabled,
    ) {
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
      });
    });
    _load();
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    super.dispose();
  }

  /// 读取失败也要恢复可操作状态，避免开关被永久禁用。
  Future<void> _load() async {
    var enabled = false;
    try {
      await _quickEntryService.initialize();
      enabled = await _quickEntryService.loadFloatingWindowEnabled();
      final appearance = await _quickEntryService.loadAppearance();
      if (mounted) _appearance = appearance;
    } catch (_) {
      enabled = false;
    }
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _loading = false;
    });
  }

  Future<void> _setEnabled(bool enabled) async {
    setState(() {
      _loading = true;
    });
    try {
      await _quickEntryService.setFloatingWindowEnabled(enabled);
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _enabled = false;
        _loading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法创建点名悬浮窗')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final background = Color(_appearance['color']!);
    final foreground = background.computeLuminance() > 0.4 ? Colors.black87 : Colors.white;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('显示悬浮窗'),
          subtitle: const Text('点击打开点名页，悬浮窗保持显示'),
          value: _enabled,
          onChanged: _loading ? null : _setEnabled,
        ),
        SizedBox(
          height: 170,
          child: Center(
            child: Container(
              key: const ValueKey('floating_window_preview'),
              width: _appearance['size']!.toDouble(),
              height: _appearance['size']!.toDouble(),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(_appearance['radius']!.toDouble()),
              ),
              child: Text('点名', style: TextStyle(color: foreground, fontSize: _appearance['size']! * 0.25)),
            ),
          ),
        ),
        Text('大小：${_appearance['size']}'),
        Slider(
          key: const ValueKey('floating_size_slider'),
          min: 48, max: 160, divisions: 28,
          value: _appearance['size']!.toDouble(),
          onChanged: _loading ? null : (value) => _changeAppearance('size', value.round()),
        ),
        Text('圆角：${_appearance['radius']}'),
        Slider(
          min: 0, max: 24, divisions: 24,
          value: _appearance['radius']!.toDouble(),
          onChanged: _loading ? null : (value) => _changeAppearance('radius', value.round()),
        ),
        const Text('背景颜色'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12, runSpacing: 8,
          children: [0xFFBDEAFF, 0xFFCCE8D4, 0xFFFFE2BA, 0xFFE2D6FF, 0xFFF2F2F2, 0xFF30343B].map((color) =>
            InkWell(
              onTap: _loading ? null : () => _changeAppearance('color', color),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: Color(color), shape: BoxShape.circle,
                  border: Border.all(color: _appearance['color'] == color ? Theme.of(context).colorScheme.primary : Colors.grey, width: _appearance['color'] == color ? 3 : 1)),
              ),
            ),
          ).toList(),
        ),
        TextButton(onPressed: _loading ? null : _chooseCustomColor, child: const Text('自定义颜色')),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: _loading ? null : () {
            _changeAppearance('size', 80);
            _changeAppearance('radius', 18);
            _changeAppearance('color', 0xFFBDEAFF);
          }, child: const Text('恢复默认')),
        ),
      ],
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
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon),
              title: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            ...children,
          ],
        ),
      ),
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

class _ThemeModeTile extends StatelessWidget {
  const _ThemeModeTile({
    required this.currentMode,
    required this.onModeChanged,
  });

  final ThemeMode currentMode;
  final ValueChanged<ThemeMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.dark_mode),
      title: const Text('深色模式'),
      trailing: SizedBox(
        width: 140,
        child: DropdownButtonFormField<ThemeMode>(
          initialValue: currentMode,
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(
              value: ThemeMode.system,
              child: Text('跟随系统'),
            ),
            DropdownMenuItem(
              value: ThemeMode.light,
              child: Text('浅色'),
            ),
            DropdownMenuItem(
              value: ThemeMode.dark,
              child: Text('深色'),
            ),
          ],
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
