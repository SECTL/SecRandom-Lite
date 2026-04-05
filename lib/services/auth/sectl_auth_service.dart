import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../models/auth_token.dart';
import '../../models/pending_auth_session.dart';
import '../../models/user_info.dart';
import 'auth_config.dart';
import 'loopback_server.dart';
import 'platform_info.dart';
import 'token_manager.dart';
import 'web_auth_navigation.dart';
import 'web_popup_auth.dart';

class AuthApiException implements Exception {
  const AuthApiException({
    required this.statusCode,
    required this.error,
    required this.description,
  });

  final int statusCode;
  final String error;
  final String description;

  bool get isInvalidToken =>
      statusCode == 401 || error.toLowerCase() == 'invalid_token';

  @override
  String toString() => '$error: $description';
}

class SectlAuthService {
  SectlAuthService({
    TokenManager? tokenManager,
    AppLinks? appLinks,
    http.Client? httpClient,
  }) : _tokenManager = tokenManager ?? TokenManager(),
       _appLinks = appLinks ?? AppLinks(),
       _httpClient = httpClient ?? http.Client();

  final TokenManager _tokenManager;
  final AppLinks _appLinks;
  final http.Client _httpClient;

  StreamSubscription<Uri>? _linkSubscription;
  AuthLoopbackServer? _loopbackServer;
  Completer<UserInfo>? _activeLoginCompleter;
  WebAuthPopupSession? _webPopupSession;

  static String generateCodeVerifier({int byteLength = 32}) {
    final random = Random.secure();
    final bytes = List<int>.generate(byteLength, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String generateCodeChallenge(String codeVerifier) {
    final digest = sha256.convert(utf8.encode(codeVerifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  static String encodeStatePayload(Map<String, dynamic> payload) {
    return base64UrlEncode(
      utf8.encode(jsonEncode(payload)),
    ).replaceAll('=', '');
  }

  static Map<String, dynamic> decodeStatePayload(String state) {
    final normalized = base64.normalize(state);
    final decoded = utf8.decode(base64Url.decode(normalized));
    return jsonDecode(decoded) as Map<String, dynamic>;
  }

  static Map<String, dynamic> buildTokenExchangePayload({
    required String code,
    required String codeVerifier,
    required String deviceUuid,
  }) {
    return {
      'grant_type': 'authorization_code',
      'code': code,
      'client_id': AuthConfig.platformId,
      'redirect_uri': AuthConfig.oauthRedirectUri,
      'code_verifier': codeVerifier,
      'device_uuid': deviceUuid,
    };
  }

  static Map<String, dynamic> buildRefreshPayload({
    required String refreshToken,
  }) {
    return {
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'client_id': AuthConfig.platformId,
    };
  }

  String getAuthorizationUrl(PendingAuthSession session) {
    final params = {
      'client_id': AuthConfig.platformId,
      'redirect_uri': AuthConfig.oauthRedirectUri,
      'response_type': 'code',
      'state': session.state,
      'code_challenge': generateCodeChallenge(session.codeVerifier),
      'code_challenge_method': 'S256',
    };

    final uri = Uri.parse(
      '${AuthConfig.authUrl}${AuthConfig.authorizeEndpoint}',
    );
    return uri.replace(queryParameters: params).toString();
  }

  Future<UserInfo> login() async {
    final targetPlatform = _resolveTargetPlatform();
    if (PlatformInfo.isIOS) {
      throw UnsupportedError('SECTL login is not supported on iOS.');
    }

    await _cleanupRuntime();

    final session = PendingAuthSession(
      state: _buildState(targetPlatform),
      codeVerifier: generateCodeVerifier(),
      targetPlatform: targetPlatform,
      desktopPort: targetPlatform == PendingAuthTargetPlatform.desktop
          ? AuthConfig.loopbackPort
          : null,
      createdAt: DateTime.now(),
    );

    await _tokenManager.savePendingAuthSession(session);
    await _prepareCallbackRuntime(session);

    final authUrl = getAuthorizationUrl(session);
    _activeLoginCompleter = Completer<UserInfo>();

    if (targetPlatform == PendingAuthTargetPlatform.web) {
      final popupSession = await openWebAuthPopup(authUrl);
      if (popupSession == null) {
        await navigateBrowserTo(authUrl);
        return _activeLoginCompleter!.future;
      }

      _webPopupSession = popupSession;
      unawaited(_waitForWebPopupCallback(popupSession));
      return _activeLoginCompleter!.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () async {
          await _tokenManager.clearPendingAuthSession();
          await _cleanupRuntime();
          throw TimeoutException('SECTL login timed out.');
        },
      );
    }

    final launched = await launchUrl(
      Uri.parse(authUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      await _tokenManager.clearPendingAuthSession();
      await _cleanupRuntime();
      throw StateError('Unable to open the browser for SECTL login.');
    }

    return _activeLoginCompleter!.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () async {
        await _tokenManager.clearPendingAuthSession();
        await _cleanupRuntime();
        throw TimeoutException('SECTL login timed out.');
      },
    );
  }

  Future<UserInfo?> completePendingLoginIfPresent() async {
    final pendingSession = await _tokenManager.getPendingAuthSession();
    if (pendingSession == null) return null;

    if (pendingSession.isExpired) {
      await _tokenManager.clearPendingAuthSession();
      return null;
    }

    if (kIsWeb) {
      final uri = getCurrentBrowserUri();
      if (!_looksLikeWebOAuthCallback(uri)) {
        return null;
      }

      try {
        final userInfo = await completeLoginFromCallbackUri(uri);
        clearBrowserOAuthParams();
        return userInfo;
      } catch (_) {
        clearBrowserOAuthParams();
        rethrow;
      }
    }

    final initialLink = await _appLinks.getInitialLink();
    if (initialLink != null && _isDeepLinkCallback(initialLink)) {
      return completeLoginFromCallbackUri(initialLink);
    }

    return null;
  }

  Future<UserInfo> completeLoginFromCallbackUri(Uri uri) async {
    final pendingSession = await _tokenManager.getPendingAuthSession();
    if (pendingSession == null) {
      throw StateError('No pending SECTL login session was found.');
    }

    if (pendingSession.isExpired) {
      await _tokenManager.clearPendingAuthSession();
      await _cleanupRuntime();
      throw StateError('The pending SECTL login session has expired.');
    }

    final error = uri.queryParameters['error'];
    if (error != null) {
      final description =
          uri.queryParameters['error_description'] ?? 'Authorization failed.';
      await _tokenManager.clearPendingAuthSession();
      await _cleanupRuntime(clearCompleter: false);
      throw AuthApiException(
        statusCode: 400,
        error: error,
        description: description,
      );
    }

    final returnedState = uri.queryParameters['state'];
    if (returnedState != pendingSession.state) {
      await _tokenManager.clearPendingAuthSession();
      await _cleanupRuntime(clearCompleter: false);
      throw StateError('SECTL login state validation failed.');
    }

    final code = uri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      await _tokenManager.clearPendingAuthSession();
      await _cleanupRuntime(clearCompleter: false);
      throw StateError('SECTL did not return an authorization code.');
    }

    try {
      final token = await exchangeCode(
        code,
        codeVerifier: pendingSession.codeVerifier,
      );
      final userInfo = await getUserInfo(token.accessToken);
      await _tokenManager.saveToken(token);
      await _tokenManager.saveUserInfo(userInfo);
      await _tokenManager.clearPendingAuthSession();
      await _cleanupRuntime(clearCompleter: false);
      return userInfo;
    } catch (_) {
      await _tokenManager.clearPendingAuthSession();
      await _cleanupRuntime(clearCompleter: false);
      rethrow;
    }
  }

  Future<AuthToken> exchangeCode(
    String code, {
    required String codeVerifier,
  }) async {
    final url = Uri.parse('${AuthConfig.baseUrl}${AuthConfig.tokenEndpoint}');
    final deviceUuid = await _tokenManager.getOrCreateDeviceUuid();
    final payload = buildTokenExchangePayload(
      code: code,
      codeVerifier: codeVerifier,
      deviceUuid: deviceUuid,
    );

    final response = await _httpClient.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      throw _parseError(response);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return AuthToken.fromJson(data);
  }

  Future<AuthToken> refreshToken(String refreshToken) async {
    final url = Uri.parse('${AuthConfig.baseUrl}${AuthConfig.refreshEndpoint}');
    final response = await _httpClient.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(buildRefreshPayload(refreshToken: refreshToken)),
    );

    if (response.statusCode != 200) {
      throw _parseError(response);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = AuthToken.fromJson(data);
    await _tokenManager.saveToken(token);
    return token;
  }

  Future<UserInfo> getUserInfo(String accessToken) async {
    final url = Uri.parse(
      '${AuthConfig.baseUrl}${AuthConfig.userInfoEndpoint}',
    );
    final response = await _httpClient.get(
      url,
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (response.statusCode != 200) {
      throw _parseError(response);
    }

    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return UserInfo.fromJson(data);
  }

  Future<UserInfo?> restoreValidSession() async {
    final pendingSession = await _tokenManager.getPendingAuthSession();
    if (pendingSession != null && pendingSession.isExpired) {
      await _tokenManager.clearPendingAuthSession();
    }

    var token = await _tokenManager.getToken();
    if (token == null) return null;

    if (token.isExpired) {
      final refreshTokenValue = token.refreshToken;
      if (refreshTokenValue == null) {
        await _tokenManager.clearAll();
        return null;
      }
      try {
        token = await refreshToken(refreshTokenValue);
      } catch (_) {
        await _tokenManager.clearAll();
        return null;
      }
    } else if (token.isExpiringSoon && token.refreshToken != null) {
      try {
        token = await refreshToken(token.refreshToken!);
      } catch (_) {
        await _tokenManager.clearAll();
        return null;
      }
    }

    try {
      final userInfo = await getUserInfo(token.accessToken);
      await _tokenManager.saveUserInfo(userInfo);
      return userInfo;
    } on AuthApiException catch (error) {
      if (error.isInvalidToken) {
        await _tokenManager.clearAll();
        return null;
      }
      rethrow;
    }
  }

  Future<UserInfo?> getCurrentUser() async {
    return _tokenManager.getUserInfo();
  }

  Future<UserInfo> refreshCurrentUser() async {
    final accessToken = await _tokenManager.getAccessToken();
    if (accessToken == null) {
      throw StateError('No access token is stored.');
    }

    try {
      final userInfo = await getUserInfo(accessToken);
      await _tokenManager.saveUserInfo(userInfo);
      return userInfo;
    } on AuthApiException catch (error) {
      if (error.isInvalidToken) {
        await _tokenManager.clearAll();
      }
      rethrow;
    }
  }

  Future<void> logout() async {
    final accessToken = await _tokenManager.getAccessToken();
    if (accessToken != null) {
      try {
        final url = Uri.parse(
          '${AuthConfig.baseUrl}${AuthConfig.logoutEndpoint}',
        );
        await _httpClient.post(
          url,
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'client_id': AuthConfig.platformId}),
        );
      } on AuthApiException catch (error) {
        if (!error.isInvalidToken) {
          rethrow;
        }
      } catch (_) {
        // Ignore remote logout failures and always clear local state.
      }
    }

    await _tokenManager.clearAll();
    await _cleanupRuntime();
  }

  Future<void> _prepareCallbackRuntime(PendingAuthSession session) async {
    if (session.targetPlatform == PendingAuthTargetPlatform.android) {
      _linkSubscription = _appLinks.uriLinkStream.listen(
        (uri) {
          unawaited(_handleIncomingCallbackUri(uri));
        },
        onError: (error, stackTrace) {
          if (_activeLoginCompleter != null &&
              !_activeLoginCompleter!.isCompleted) {
            _activeLoginCompleter!.completeError(error, stackTrace);
          }
        },
      );
      return;
    }

    if (session.targetPlatform == PendingAuthTargetPlatform.desktop) {
      _loopbackServer = AuthLoopbackServer();
      await _loopbackServer!.start(
        host: AuthConfig.loopbackHost,
        port: session.desktopPort ?? AuthConfig.loopbackPort,
        path: AuthConfig.loopbackPath,
        onRequest: (uri) => _handleIncomingCallbackUri(
          Uri(
            scheme: 'http',
            host: AuthConfig.loopbackHost,
            port: session.desktopPort ?? AuthConfig.loopbackPort,
            path: AuthConfig.loopbackPath,
            queryParameters: uri.queryParameters,
          ),
        ),
      );
    }
  }

  Future<void> _handleIncomingCallbackUri(Uri uri) async {
    if (!_isDeepLinkCallback(uri) && !_isDesktopLoopbackCallback(uri)) {
      return;
    }

    try {
      final userInfo = await completeLoginFromCallbackUri(uri);
      if (_activeLoginCompleter != null &&
          !_activeLoginCompleter!.isCompleted) {
        _activeLoginCompleter!.complete(userInfo);
      }
    } catch (error, stackTrace) {
      if (_activeLoginCompleter != null &&
          !_activeLoginCompleter!.isCompleted) {
        _activeLoginCompleter!.completeError(error, stackTrace);
      }
    } finally {
      _activeLoginCompleter = null;
    }
  }

  Future<void> _waitForWebPopupCallback(
    WebAuthPopupSession popupSession,
  ) async {
    try {
      final callbackUri = await popupSession.waitForCallback();
      final userInfo = await completeLoginFromCallbackUri(callbackUri);
      if (_activeLoginCompleter != null &&
          !_activeLoginCompleter!.isCompleted) {
        _activeLoginCompleter!.complete(userInfo);
      }
    } catch (error, stackTrace) {
      if (_activeLoginCompleter != null &&
          !_activeLoginCompleter!.isCompleted) {
        _activeLoginCompleter!.completeError(error, stackTrace);
      }
    } finally {
      await popupSession.close();
      if (identical(_webPopupSession, popupSession)) {
        _webPopupSession = null;
      }
      _activeLoginCompleter = null;
    }
  }

  PendingAuthTargetPlatform _resolveTargetPlatform() {
    if (kIsWeb) {
      return PendingAuthTargetPlatform.web;
    }
    if (PlatformInfo.isAndroid) {
      return PendingAuthTargetPlatform.android;
    }
    if (PlatformInfo.isIOS) {
      throw UnsupportedError('SECTL login is not supported on iOS.');
    }
    if (PlatformInfo.isWindows ||
        PlatformInfo.isLinux ||
        PlatformInfo.isMacOS) {
      return PendingAuthTargetPlatform.desktop;
    }
    throw UnsupportedError('SECTL login is not supported on this platform.');
  }

  String _buildState(PendingAuthTargetPlatform targetPlatform) {
    final payload = <String, dynamic>{
      'n': _randomToken(byteLength: 12),
      't': targetPlatform.name,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };

    if (targetPlatform == PendingAuthTargetPlatform.web) {
      payload['w'] = AuthConfig.webAppUrl.isNotEmpty
          ? AuthConfig.webAppUrl
          : resolveCurrentWebAppUrl();
    }

    if (targetPlatform == PendingAuthTargetPlatform.desktop) {
      payload['p'] = AuthConfig.loopbackPort;
    }

    return encodeStatePayload(payload);
  }

  String _randomToken({required int byteLength}) {
    final random = Random.secure();
    final bytes = List<int>.generate(byteLength, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  bool _looksLikeWebOAuthCallback(Uri uri) {
    return uri.queryParameters.containsKey('code') ||
        uri.queryParameters.containsKey('error');
  }

  bool _isDeepLinkCallback(Uri uri) {
    return uri.scheme == AuthConfig.callbackScheme &&
        uri.host == AuthConfig.callbackHost &&
        uri.path == AuthConfig.callbackPath;
  }

  bool _isDesktopLoopbackCallback(Uri uri) {
    final host = uri.host.toLowerCase();
    return uri.scheme == 'http' &&
        (host == AuthConfig.loopbackHost || host == 'localhost') &&
        uri.path == AuthConfig.loopbackPath;
  }

  AuthApiException _parseError(http.Response response) {
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return AuthApiException(
        statusCode: response.statusCode,
        error: (data['error'] ?? 'http_${response.statusCode}').toString(),
        description: (data['error_description'] ?? 'Unknown error').toString(),
      );
    } catch (_) {
      return AuthApiException(
        statusCode: response.statusCode,
        error: 'http_${response.statusCode}',
        description: 'HTTP ${response.statusCode}',
      );
    }
  }

  Future<void> _cleanupRuntime({bool clearCompleter = true}) async {
    await _linkSubscription?.cancel();
    _linkSubscription = null;
    await _loopbackServer?.close();
    _loopbackServer = null;
    await _webPopupSession?.close();
    _webPopupSession = null;
    if (clearCompleter) {
      _activeLoginCompleter = null;
    }
  }

  void dispose() {
    _linkSubscription?.cancel();
    _loopbackServer?.close();
    _webPopupSession?.close();
    _httpClient.close();
    _linkSubscription = null;
    _loopbackServer = null;
    _webPopupSession = null;
    _activeLoginCompleter = null;
  }
}
