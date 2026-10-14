import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/logger.dart';
import 'auth/platform_info.dart';

/// 开机自启：把当前可执行文件写入 HKCU 的 `Run` 键，随用户登录自动拉起。
///
/// **注册表是唯一事实来源**，`SharedPreferences` 只记录最近一次已知状态，
/// 供通道不可用时兜底显示。这样在注册表编辑器里手工改过的值会在下次读取时
/// 反映到开关上，不会出现「设置显示已开启但实际没配置」的假象。
class AutoStartService {
  AutoStartService._();

  static final AutoStartService instance = AutoStartService._();

  static const _channel = MethodChannel('secrandom_lite/auto_start');
  static const _enabledKey = 'auto_start_enabled';

  /// 仅 Windows 桌面有原生实现；其他平台整块不渲染开关。
  bool get supportsAutoStart => PlatformInfo.isWindows;

  /// 读取真实状态。读不到时回落到上次记录的偏好，让开关至少保持可用，
  /// 而不是把用户卡在原地。
  Future<bool> loadAutoStartEnabled() async {
    if (!supportsAutoStart) return false;
    try {
      final enabled = await _channel.invokeMethod<bool>('isEnabled');
      if (enabled != null) {
        await _remember(enabled);
        return enabled;
      }
    } on PlatformException catch (e) {
      logger.w('读取开机自启状态失败，回退到本地偏好', error: e);
    } on MissingPluginException {
      logger.w('当前平台没有开机自启实现，回退到本地偏好');
    }
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_enabledKey) ?? false;
  }

  /// 开启或关闭开机自启。
  ///
  /// 写入失败时先把偏好对齐注册表的真实值再原样抛出，调用方据此把开关回落，
  /// 避免界面停留在一个并没有生效的状态上。
  Future<void> setAutoStartEnabled(bool enabled) async {
    if (!supportsAutoStart) return;
    try {
      await _channel.invokeMethod<void>('setEnabled', enabled);
    } catch (e) {
      logger.e('写入开机自启失败', error: e);
      await _syncToRegistry();
      rethrow;
    }
    await _remember(enabled);
  }

  /// 写失败后把偏好对齐注册表实际值；读不回真实状态就保留最近一次已知值，
  /// 且**绝不再抛**，否则会盖掉调用方本来要处理的那个错误。
  Future<void> _syncToRegistry() async {
    try {
      final actual = await _channel.invokeMethod<bool>('isEnabled');
      if (actual != null) await _remember(actual);
    } catch (_) {
      // 读不回真实状态，维持现状即可。
    }
  }

  Future<void> _remember(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey, enabled);
  }
}
