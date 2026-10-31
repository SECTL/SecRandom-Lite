import 'dart:async';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/logger.dart';
import 'auth/platform_info.dart';

/// 点名快捷入口：Windows 独立悬浮窗与 Android 控制中心磁贴共用的通道。
///
/// 平台只负责上报“用户想看点名”这类事实，状态落库与页面跳转都在这里统一处理。
class RollCallQuickEntryService {
  RollCallQuickEntryService._() {
    // 监听者出现时补投启动期暂存的点名请求。
    _openRollCallController = StreamController<void>.broadcast(
      onListen: _flushPendingOpenRequest,
    );
  }

  static final RollCallQuickEntryService instance =
      RollCallQuickEntryService._();

  static const _channel = MethodChannel('secrandom_lite/quick_entry');
  static const _enabledKey = 'rollcall_floating_window_enabled';

  late final StreamController<void> _openRollCallController;
  final StreamController<bool> _floatingWindowStateController =
      StreamController<bool>.broadcast();

  bool _handlerRegistered = false;
  bool _initialized = false;
  bool _pendingOpenRequest = false;

  bool get supportsFloatingWindow => PlatformInfo.isWindows;

  Stream<void> get openRollCallRequests => _openRollCallController.stream;
  Stream<bool> get floatingWindowState => _floatingWindowStateController.stream;

  /// 注册事件通道，并按上次的开关状态恢复悬浮窗。
  ///
  /// 通道注册是同步的且只做一次；后续的偏好读取与 Android 冷启动补投可能失败，
  /// 失败时保持未完成状态，下次调用可重试，不影响已经可用的入口事件。
  Future<void> initialize() async {
    if (!_handlerRegistered) {
      _handlerRegistered = true;
      _channel.setMethodCallHandler(_handleMethodCall);
    }
    if (_initialized) return;

    try {
      if (supportsFloatingWindow) {
        final preferences = await SharedPreferences.getInstance();
        await _channel.invokeMethod<void>('setFloatingAppearance', await loadAppearance());
        if (preferences.getBool(_enabledKey) ?? false) {
          // 开关是用户有意打开的，跨重启恢复；恢复不了就如实把开关关掉，
          // 避免设置里显示“已开启”而实际没有窗口。
          try {
            await _channel.invokeMethod<void>('showFloatingWindow');
          } on PlatformException {
            await preferences.setBool(_enabledKey, false);
            _floatingWindowStateController.add(false);
          }
        }
      }
      if (PlatformInfo.isAndroid) {
        final pending = await _channel.invokeMethod<bool>(
          'consumePendingRollCall',
        );
        if (pending == true) _emitOpenRollCall();
      }
      _initialized = true;
    } catch (e) {
      logger.w('点名快捷入口初始化失败，将在下次进入页面时重试', error: e);
    }
  }

  Future<Map<String, int>> loadAppearance() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'size': prefs.getInt('floating_size') ?? 64,
      'color': prefs.getInt('floating_color') ?? 0xFFBDEAFF,
    };
  }

  Future<void> saveAppearance(Map<String, int> appearance) async {
    if (!supportsFloatingWindow) return;
    await _channel.invokeMethod<void>('setFloatingAppearance', appearance);
    final prefs = await SharedPreferences.getInstance();
    for (final entry in appearance.entries) {
      await prefs.setInt('floating_${entry.key}', entry.value);
    }
  }

  Future<bool> loadFloatingWindowEnabled() async {
    if (!supportsFloatingWindow) return false;
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_enabledKey) ?? false;
  }

  Future<void> setFloatingWindowEnabled(bool enabled) async {
    if (!supportsFloatingWindow) return;
    final preferences = await SharedPreferences.getInstance();
    if (!enabled) {
      await _channel.invokeMethod<void>('hideFloatingWindow');
      await preferences.setBool(_enabledKey, false);
      _floatingWindowStateController.add(false);
      return;
    }

    try {
      await _channel.invokeMethod<void>('showFloatingWindow');
      await preferences.setBool(_enabledKey, true);
      _floatingWindowStateController.add(true);
    } on PlatformException {
      await preferences.setBool(_enabledKey, false);
      rethrow;
    }
  }

  /// 事件可能在监听者挂载前到达（冷启动），先暂存、等首个监听者出现再补投。
  void _emitOpenRollCall() {
    if (!_openRollCallController.hasListener) {
      _pendingOpenRequest = true;
      return;
    }
    _openRollCallController.add(null);
  }

  void _flushPendingOpenRequest() {
    if (!_pendingOpenRequest) return;
    _pendingOpenRequest = false;
    _openRollCallController.add(null);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    // 点击悬浮窗只是打开点名页，悬浮窗本身继续置顶驻留，
    // 开关状态不变；关闭悬浮窗由设置开关控制。
    if (call.method == 'openRollCall') {
      _emitOpenRollCall();
    }
  }
}
