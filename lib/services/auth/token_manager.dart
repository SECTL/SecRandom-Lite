import '../../models/auth_token.dart';
import '../../models/pending_auth_session.dart';
import '../../models/user_info.dart';
import 'package:uuid/uuid.dart';
import 'auth_config.dart';
import 'key_value_store.dart';
import 'web_cookie_bridge.dart';

class TokenManager {
  TokenManager({KeyValueStore? store})
    : _store = store ?? SecureKeyValueStore();

  static const Uuid _uuid = Uuid();
  static final RegExp _standardUuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-'
    r'[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{12}$',
  );

  final KeyValueStore _store;

  AuthToken? _cachedToken;
  UserInfo? _cachedUserInfo;
  PendingAuthSession? _cachedPendingSession;

  Future<void> saveToken(AuthToken token) async {
    _cachedToken = token;
    await _store.write(
      key: AuthConfig.accessTokenKey,
      value: token.accessToken,
    );
    if (token.refreshToken != null) {
      await _store.write(
        key: AuthConfig.refreshTokenKey,
        value: token.refreshToken!,
      );
    } else {
      await _store.delete(key: AuthConfig.refreshTokenKey);
    }
    if (token.expiresAt != null) {
      await _store.write(
        key: AuthConfig.tokenExpiresAtKey,
        value: token.expiresAt!.toIso8601String(),
      );
    } else {
      await _store.delete(key: AuthConfig.tokenExpiresAtKey);
    }
    await _writeTokenCookies(token);
  }

  Future<AuthToken?> getToken() async {
    if (_cachedToken != null && !_cachedToken!.isExpired) {
      return _cachedToken;
    }

    String? accessToken = await _store.read(key: AuthConfig.accessTokenKey);
    String? refreshToken = await _store.read(key: AuthConfig.refreshTokenKey);
    String? expiresAtStr = await _store.read(key: AuthConfig.tokenExpiresAtKey);

    if (accessToken == null) {
      final restored = await restoreTokenFromCookieIfPresent();
      if (restored) {
        accessToken = await _store.read(key: AuthConfig.accessTokenKey);
        refreshToken = await _store.read(key: AuthConfig.refreshTokenKey);
        expiresAtStr = await _store.read(key: AuthConfig.tokenExpiresAtKey);
      }
    }
    if (accessToken == null) return null;

    DateTime? expiresAt;
    if (expiresAtStr != null) {
      try {
        expiresAt = DateTime.parse(expiresAtStr);
      } catch (_) {
        expiresAt = null;
      }
    }

    _cachedToken = AuthToken(
      accessToken: accessToken,
      refreshToken: refreshToken,
      tokenType: 'Bearer',
      expiresIn: expiresAt != null
          ? expiresAt.difference(DateTime.now()).inSeconds
          : 3600,
      expiresAt: expiresAt,
    );

    return _cachedToken;
  }

  Future<bool> restoreTokenFromCookieIfPresent() async {
    final cookies = readBrowserCookies();
    final accessToken = cookies[AuthConfig.accessTokenKey];
    if (accessToken == null || accessToken.isEmpty) {
      return false;
    }

    final refreshToken = cookies[AuthConfig.refreshTokenKey];
    final expiresAtStr = cookies[AuthConfig.tokenExpiresAtKey];
    DateTime? expiresAt;
    if (expiresAtStr != null && expiresAtStr.isNotEmpty) {
      try {
        expiresAt = DateTime.parse(expiresAtStr);
      } catch (_) {
        expiresAt = null;
      }
    }

    final token = AuthToken(
      accessToken: accessToken,
      refreshToken: refreshToken,
      tokenType: 'Bearer',
      expiresIn: expiresAt != null
          ? expiresAt.difference(DateTime.now()).inSeconds
          : 3600,
      expiresAt: expiresAt,
    );
    await saveToken(token);

    final cookieDeviceUuid = cookies[AuthConfig.deviceUuidKey];
    if (cookieDeviceUuid != null && _isStandardUuid(cookieDeviceUuid)) {
      await _store.write(
        key: AuthConfig.deviceUuidKey,
        value: cookieDeviceUuid,
      );
    }

    return true;
  }

  Future<String?> getAccessToken() async {
    final token = await getToken();
    return token?.accessToken;
  }

  Future<String?> getRefreshToken() async {
    final token = await getToken();
    return token?.refreshToken;
  }

  Future<bool> hasValidToken() async {
    final token = await getToken();
    return token != null && !token.isExpired;
  }

  Future<bool> isTokenExpiringSoon() async {
    final token = await getToken();
    return token?.isExpiringSoon ?? false;
  }

  Future<void> clearToken() async {
    _cachedToken = null;
    await _store.delete(key: AuthConfig.accessTokenKey);
    await _store.delete(key: AuthConfig.refreshTokenKey);
    await _store.delete(key: AuthConfig.tokenExpiresAtKey);
    await deleteBrowserCookie(AuthConfig.accessTokenKey);
    await deleteBrowserCookie(AuthConfig.refreshTokenKey);
    await deleteBrowserCookie(AuthConfig.tokenExpiresAtKey);
  }

  Future<void> saveUserInfo(UserInfo userInfo) async {
    _cachedUserInfo = userInfo;
    await _store.write(
      key: AuthConfig.userInfoKey,
      value: userInfo.toJsonString(),
    );
  }

  Future<UserInfo?> getUserInfo() async {
    if (_cachedUserInfo != null) {
      return _cachedUserInfo;
    }

    final userInfoStr = await _store.read(key: AuthConfig.userInfoKey);
    if (userInfoStr == null) return null;

    try {
      _cachedUserInfo = UserInfo.fromJsonString(userInfoStr);
      return _cachedUserInfo;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearUserInfo() async {
    _cachedUserInfo = null;
    await _store.delete(key: AuthConfig.userInfoKey);
  }

  Future<void> savePendingAuthSession(PendingAuthSession session) async {
    _cachedPendingSession = session;
    await _store.write(
      key: AuthConfig.pendingAuthSessionKey,
      value: session.toJsonString(),
    );
  }

  Future<PendingAuthSession?> getPendingAuthSession() async {
    if (_cachedPendingSession != null) {
      return _cachedPendingSession;
    }

    final sessionStr = await _store.read(key: AuthConfig.pendingAuthSessionKey);
    if (sessionStr == null) return null;

    try {
      _cachedPendingSession = PendingAuthSession.fromJsonString(sessionStr);
      return _cachedPendingSession;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearPendingAuthSession() async {
    _cachedPendingSession = null;
    await _store.delete(key: AuthConfig.pendingAuthSessionKey);
  }

  Future<String> getOrCreateDeviceUuid() async {
    final existing = await _store.read(key: AuthConfig.deviceUuidKey);
    if (existing != null && _isStandardUuid(existing)) {
      return existing;
    }

    final cookieDeviceUuid = readBrowserCookies()[AuthConfig.deviceUuidKey];
    if (cookieDeviceUuid != null && _isStandardUuid(cookieDeviceUuid)) {
      await _store.write(
        key: AuthConfig.deviceUuidKey,
        value: cookieDeviceUuid,
      );
      return cookieDeviceUuid;
    }

    final generated = _uuid.v4();
    await _store.write(key: AuthConfig.deviceUuidKey, value: generated);
    await setBrowserCookie(
      key: AuthConfig.deviceUuidKey,
      value: generated,
      maxAgeDays: AuthConfig.webAuthCookieMaxAgeDays,
    );
    return generated;
  }

  bool _isStandardUuid(String value) {
    return _standardUuidPattern.hasMatch(value);
  }

  Future<void> clearAll() async {
    await clearToken();
    await clearUserInfo();
    await clearPendingAuthSession();
    await deleteBrowserCookie(AuthConfig.deviceUuidKey);
  }

  Future<void> _writeTokenCookies(AuthToken token) async {
    await setBrowserCookie(
      key: AuthConfig.accessTokenKey,
      value: token.accessToken,
      maxAgeDays: AuthConfig.webAuthCookieMaxAgeDays,
    );

    final refreshToken = token.refreshToken;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await setBrowserCookie(
        key: AuthConfig.refreshTokenKey,
        value: refreshToken,
        maxAgeDays: AuthConfig.webAuthCookieMaxAgeDays,
      );
    } else {
      await deleteBrowserCookie(AuthConfig.refreshTokenKey);
    }

    if (token.expiresAt != null) {
      await setBrowserCookie(
        key: AuthConfig.tokenExpiresAtKey,
        value: token.expiresAt!.toIso8601String(),
        maxAgeDays: AuthConfig.webAuthCookieMaxAgeDays,
      );
    } else {
      await deleteBrowserCookie(AuthConfig.tokenExpiresAtKey);
    }
  }
}
