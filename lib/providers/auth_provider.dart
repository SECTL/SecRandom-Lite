import 'package:flutter/material.dart';

import '../models/user_info.dart';
import '../services/auth/auth_error_messages.dart';
import '../services/auth/sectl_auth_service.dart';

export '../services/auth/auth_error_messages.dart';
export '../services/auth/sectl_auth_service.dart' show LoginCancelledException;

class AuthProvider with ChangeNotifier {
  AuthProvider({SectlAuthService? authService})
    : _authService = authService ?? SectlAuthService() {
    _initAuth();
  }

  final SectlAuthService _authService;

  UserInfo? _userInfo;
  bool _isLoading = false;
  bool _isLoggingIn = false;
  String? _error;

  UserInfo? get userInfo => _userInfo;
  bool get isLoggedIn => _userInfo != null;

  /// 会话恢复 / 退出登录等阻塞态；登录中请用 [isLoggingIn]，避免整页转圈。
  bool get isLoading => _isLoading;
  bool get isLoggingIn => _isLoggingIn;
  String? get error => _error;

  Future<void> _initAuth() async {
    _isLoading = true;
    notifyListeners();

    try {
      final callbackUser = await _authService.completePendingLoginIfPresent();
      if (callbackUser != null) {
        _userInfo = callbackUser;
        _error = null;
      } else {
        _userInfo = await _authService.restoreValidSession();
        _error = null;
      }
    } catch (error) {
      _userInfo = null;
      _error = describeAuthError(error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> login() async {
    if (_isLoggingIn) return;
    _isLoggingIn = true;
    _error = null;
    notifyListeners();

    try {
      _userInfo = await _authService.login();
      _error = null;
    } catch (error) {
      if (error is LoginCancelledException) {
        _error = null;
      } else {
        _error = describeAuthError(error);
      }
      rethrow;
    } finally {
      _isLoggingIn = false;
      notifyListeners();
    }
  }

  /// 取消进行中的浏览器授权等待。
  Future<void> cancelLogin() async {
    if (!_isLoggingIn) return;
    await _authService.cancelLogin();
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _authService.logout();
      _userInfo = null;
      _error = null;
    } catch (error) {
      _error = describeAuthError(error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshUserInfo() async {
    if (!isLoggedIn) return;

    try {
      _userInfo = await _authService.refreshCurrentUser();
      _error = null;
      notifyListeners();
    } catch (error) {
      _error = describeAuthError(error);
      _userInfo = null;
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authService.dispose();
    super.dispose();
  }
}
