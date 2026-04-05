import 'package:flutter/material.dart';

import '../models/user_info.dart';
import '../services/auth/sectl_auth_service.dart';

class AuthProvider with ChangeNotifier {
  AuthProvider({SectlAuthService? authService})
    : _authService = authService ?? SectlAuthService() {
    _initAuth();
  }

  final SectlAuthService _authService;

  UserInfo? _userInfo;
  bool _isLoading = false;
  String? _error;

  UserInfo? get userInfo => _userInfo;
  bool get isLoggedIn => _userInfo != null;
  bool get isLoading => _isLoading;
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
      _error = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> login() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _userInfo = await _authService.login();
      _error = null;
    } catch (error) {
      _error = error.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _authService.logout();
      _userInfo = null;
      _error = null;
    } catch (error) {
      _error = error.toString();
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
      _error = error.toString();
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
