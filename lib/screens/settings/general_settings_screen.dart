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

/// 点名悬浮窗分区（仅 Windows 桌面）。
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
        const _FloatingWindowTile(),
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
      subtitle: const Text('登录 Windows 后自动启动，驻留托盘而不弹出主界面'),
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
  bool _loaded = false;
  int _size = 64;
  Future<void> _pendingAppearance = Future<void>.value();

  void _changeSize(int size) {
    setState(() => _size = size);
    _pendingAppearance = _pendingAppearance.catchError((_) {}).then((_) async {
      try {
        await _quickEntryService.saveAppearance({'size': _size});
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法更新悬浮窗大小')));
      }
    });
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
      if (mounted) _size = appearance['size'] ?? 64;
    } catch (_) {
      enabled = false;
    }
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _loading = false;
      _loaded = true;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MergeSemantics(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.picture_in_picture_alt_outlined),
            // 与其他开关项保持一致，标题使用 ListTile 默认样式（不加粗）。
            title: const Text('点名悬浮窗'),
            subtitle: const Text('点击打开点名页，悬浮窗保持显示'),
            trailing: _loaded
                ? Switch(
                    key: const ValueKey('floating_window_switch'),
                    value: _enabled,
                    onChanged: _loading ? null : _setEnabled,
                  )
                : const SizedBox(width: 52, height: 48),
            onTap: !_loaded || _loading ? null : () => _setEnabled(!_enabled),
          ),
        ),
        if (_enabled) ...[
          Text('大小：$_size'),
          Slider(
            key: const ValueKey('floating_size_slider'),
            min: 48,
            max: 160,
            divisions: 28,
            value: _size.toDouble(),
            onChanged: _loading ? null : (value) => _changeSize(value.round()),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _loading ? null : () => _changeSize(64),
              child: const Text('恢复默认'),
            ),
          ),
        ],
      ],
    );
  }
}
