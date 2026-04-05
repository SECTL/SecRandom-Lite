class AuthConfig {
  static const bool useMockAuth = bool.fromEnvironment(
    'USE_MOCK_AUTH',
    defaultValue: false,
  );

  static const String mockAuthBaseUrl = String.fromEnvironment(
    'MOCK_AUTH_BASE_URL',
    defaultValue: 'http://localhost:8787',
  );

  static const String platformId = String.fromEnvironment(
    'SECTL_PLATFORM_ID',
    defaultValue: '69d054360032cf00c164',
  );

  static const String authCallbackBridgeUrl = String.fromEnvironment(
    'SECTL_AUTH_CALLBACK_BRIDGE_URL',
    defaultValue: 'https://secrandom-online.sectl.top/auth_callback',
  );

  static const String webAppUrl = String.fromEnvironment(
    'SECTL_WEB_APP_URL',
    defaultValue: 'https://secrandom-online.sectl.top/',
  );

  static String get baseUrl =>
      useMockAuth ? mockAuthBaseUrl : 'https://appwrite.sectl.top';

  static String get authUrl =>
      useMockAuth ? mockAuthBaseUrl : 'https://sectl.top';

  static const String authorizeEndpoint = '/oauth/authorize';
  static const String tokenEndpoint = '/api/oauth/token';
  static const String userInfoEndpoint = '/api/oauth/userinfo';
  static const String logoutEndpoint = '/api/oauth/logout';

  static const String callbackScheme = 'secrandom';
  static const String callbackHost = 'auth';
  static const String callbackPath = '/callback';

  static const String loopbackHost = '127.0.0.1';
  static const int loopbackPort = 8788;
  static const String loopbackPath = '/callback';

  static const String accessTokenKey = 'sectl_access_token';
  static const String refreshTokenKey = 'sectl_refresh_token';
  static const String tokenExpiresAtKey = 'sectl_token_expires_at';
  static const String userInfoKey = 'sectl_user_info';
  static const String pendingAuthSessionKey = 'sectl_pending_auth_session';

  static String get oauthRedirectUri {
    if (useMockAuth &&
        authCallbackBridgeUrl ==
            'https://secrandom-online.sectl.top/auth_callback') {
      return '$mockAuthBaseUrl/auth_callback.html';
    }
    return authCallbackBridgeUrl;
  }

  static String get deepLinkCallbackUri =>
      '$callbackScheme://$callbackHost$callbackPath';

  static String loopbackCallbackUri(int port) =>
      'http://$loopbackHost:$port$loopbackPath';
}
