import '../../models/auth_token.dart';
import '../../models/pending_auth_session.dart';
import '../../models/user_info.dart';
import 'auth_config.dart';
import 'key_value_store.dart';

class TokenManager {
  TokenManager({KeyValueStore? store})
    : _store = store ?? SecureKeyValueStore();

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
  }

  Future<AuthToken?> getToken() async {
    if (_cachedToken != null && !_cachedToken!.isExpired) {
      return _cachedToken;
    }

    final accessToken = await _store.read(key: AuthConfig.accessTokenKey);
    if (accessToken == null) return null;

    final refreshToken = await _store.read(key: AuthConfig.refreshTokenKey);
    final expiresAtStr = await _store.read(key: AuthConfig.tokenExpiresAtKey);

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

  Future<void> clearAll() async {
    await clearToken();
    await clearUserInfo();
    await clearPendingAuthSession();
  }
}
