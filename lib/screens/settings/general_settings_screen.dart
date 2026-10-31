import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_provider.dart';
import '../../services/auto_start_service.dart';
import '../../services/rollcall_quick_entry_service.dart';

/// GeneralSettingsScreen - 通用设置页面
///
/// - 窄屏: 使用 Scaffold 完整页面，垂直列表
/// - 宽屏: 使用 GeneralSettingsBody 作为 SettingsLayout 的 Detail 区域
class GeneralSettingsScreen extends StatelessWidget {
  const GeneralSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('通用')),
      body: const GeneralSettingsBody(),
    );
  }
}

/// 通用设置的主体内容，可嵌入 SettingsLayout 的 Detail 区域。
///
/// 包含不重复抽取、点名悬浮窗与开机自启；后两者仅在受支持的平台渲染。
class GeneralSettingsBody extends StatelessWidget {
  const GeneralSettingsBody({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, appProvider, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 600;
            final spacing = isWide ? 16.0 : 12.0;

            return ListView(
              padding: EdgeInsets.all(isWide ? 24 : 16),
              children: [
                _AutoStartSection(spacing: spacing),
                SwitchListTile(
                  key: const ValueKey('non_repeat_switch'),
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.repeat),
                  title: const Text('启用不重复抽取'),
                  subtitle: const Text('开启后抽中过的学生在本轮不会再次被抽中；关闭后每次都从当前筛选全量中抽取。'),
                  value: appProvider.nonRepeatEnabled,
                  onChanged: appProvider.setNonRepeatEnabled,
                ),
                SizedBox(height: spacing),
                _FloatingWindowSection(spacing: spacing),
              ],
            );
          },
        );
      },
    );
  }
}

/// 通用设置中的分区：只保留标题和选项，不再使用卡片容器。
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon),
          title: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        ...children,
      ],
    );
  }
}

/// 点名悬浮窗开关（仅 Windows 桌面）。
///
/// 不受支持的平台整块不渲染，也不占位，避免留下多余间距。
class _FloatingWindowSection extends StatelessWidget {
  const _FloatingWindowSection({required this.spacing});

  /// 分区下方要留出的间距，跟随所在布局的间距。
  final double spacing;

  @override
  Widget build(BuildContext context) {
    if (!RollCallQuickEntryService.instance.supportsFloatingWindow) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SettingsSection(
          title: '点名悬浮窗',
          icon: Icons.picture_in_picture_alt_outlined,
          children: [_FloatingWindowTile()],
        ),
        SizedBox(height: spacing),
      ],
    );
  }
}

/// 开机自启开关（仅 Windows 桌面）。
///
/// 不受支持的平台整块不渲染，也不占位，避免留下多余间距；
/// 分区下方的间距跟随所在布局的间距，与 `_FloatingWindowSection` 一致。
class _AutoStartSection extends StatelessWidget {
  const _AutoStartSection({required this.spacing});

  final double spacing;

  @override
  Widget build(BuildContext context) {
    if (!AutoStartService.instance.supportsAutoStart) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _AutoStartTile(),
        SizedBox(height: spacing),
      ],
    );
  }
}

/// 开关本身自己持有状态：注册表可能被系统策略或外部工具改写，
/// 每次读取都以注册表回填为准。
class _AutoStartTile extends StatefulWidget {
  const _AutoStartTile();

  @override
  State<_AutoStartTile> createState() => _AutoStartTileState();
}

class _AutoStartTileState extends State<_AutoStartTile> {
  final _autoStartService = AutoStartService.instance;
  bool _enabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 读取失败也要恢复可操作状态，避免开关被永久禁用。
  Future<void> _load() async {
    var enabled = false;
    try {
      enabled = await _autoStartService.loadAutoStartEnabled();
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
      await _autoStartService.setAutoStartEnabled(enabled);
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _loading = false;
      });
    } catch (_) {
      // 写失败后回到注册表的真实值：开启失败就是关闭，
      // 关闭失败则保持开启，而不是一律弹成关闭。
      var actual = _enabled;
      try {
        actual = await _autoStartService.loadAutoStartEnabled();
      } catch (_) {
        actual = false;
      }
      if (!mounted) return;
      setState(() {
        _enabled = actual;
        _loading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法修改开机自启设置')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      key: const ValueKey('auto_start_switch'),
      contentPadding: EdgeInsets.zero,
      secondary: const Icon(Icons.power_settings_new),
      title: const Text('登录时启动'),
      subtitle: const Text('登录 Windows 后自动启动本应用'),
      value: _enabled,
      onChanged: _loading ? null : _setEnabled,
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
  Map<String, int> _appearance = {
    'size': 80,
    'color': 0xFFBDEAFF,
    'radius': 18,
  };
  Future<void> _pendingAppearance = Future<void>.value();

  void _changeAppearance(String key, int value) {
    setState(() => _appearance = {..._appearance, key: value});
    final appearance = Map<String, int>.from(_appearance);
    _pendingAppearance = _pendingAppearance.catchError((_) {}).then((_) async {
      try {
        await _quickEntryService.saveAppearance(appearance);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法更新悬浮窗外观')));
      }
    });
  }

  Future<void> _chooseCustomColor() async {
    final controller = TextEditingController(
      text: _appearance['color']!.toRadixString(16).substring(2).toUpperCase(),
    );
    final color = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('自定义背景色'),
          content: TextField(
            controller: controller,
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: '六位十六进制颜色',
              prefixText: '#',
              hintText: 'BDEAFF',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                final text = controller.text.trim();
                if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(text)) {
                  Navigator.pop(
                    context,
                    0xFF000000 | int.parse(text, radix: 16),
                  );
                }
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
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
    final foreground = background.computeLuminance() > 0.4
        ? Colors.black87
        : Colors.white;
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
                borderRadius: BorderRadius.circular(
                  _appearance['radius']!.toDouble(),
                ),
              ),
              child: Text(
                '点名',
                style: TextStyle(
                  color: foreground,
                  fontSize: _appearance['size']! * 0.25,
                ),
              ),
            ),
          ),
        ),
        Text('大小：${_appearance['size']}'),
        Slider(
          key: const ValueKey('floating_size_slider'),
          min: 48,
          max: 160,
          divisions: 28,
          value: _appearance['size']!.toDouble(),
          onChanged: _loading
              ? null
              : (value) => _changeAppearance('size', value.round()),
        ),
        Text('圆角：${_appearance['radius']}'),
        Slider(
          min: 0,
          max: 24,
          divisions: 24,
          value: _appearance['radius']!.toDouble(),
          onChanged: _loading
              ? null
              : (value) => _changeAppearance('radius', value.round()),
        ),
        const Text('背景颜色'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children:
              [
                    0xFFBDEAFF,
                    0xFFCCE8D4,
                    0xFFFFE2BA,
                    0xFFE2D6FF,
                    0xFFF2F2F2,
                    0xFF30343B,
                  ]
                  .map(
                    (color) => InkWell(
                      onTap: _loading
                          ? null
                          : () => _changeAppearance('color', color),
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Color(color),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _appearance['color'] == color
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey,
                            width: _appearance['color'] == color ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
        ),
        TextButton(
          onPressed: _loading ? null : _chooseCustomColor,
          child: const Text('自定义颜色'),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _loading
                ? null
                : () {
                    _changeAppearance('size', 80);
                    _changeAppearance('radius', 18);
                    _changeAppearance('color', 0xFFBDEAFF);
                  },
            child: const Text('恢复默认'),
          ),
        ),
      ],
    );
  }
}
