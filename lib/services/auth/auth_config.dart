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
    defaultValue: 'https://secrandom-lite.sectl.cn/auth_callback',
  );

  static const String authCallbackWebUrl = String.fromEnvironment(
    'SECTL_AUTH_CALLBACK_WEB_URL',
    defaultValue: 'https://secrandom-lite.sectl.cn/auth_callback_web.html',
  );

  static const String authCallbackWindowsUrl = String.fromEnvironment(
    'SECTL_AUTH_CALLBACK_WINDOWS_URL',
    defaultValue: 'https://secrandom-lite.sectl.cn/auth_callback_windows.html',
  );

  static const String authCallbackAndroidUrl = String.fromEnvironment(
    'SECTL_AUTH_CALLBACK_ANDROID_URL',
    defaultValue: 'https://secrandom-lite.sectl.cn/auth_callback_android',
  );

  static const String webAppUrl = String.fromEnvironment(
    'SECTL_WEB_APP_URL',
    defaultValue: 'https://secrandom-lite.sectl.cn/',
  );

  static String get baseUrl =>
      useMockAuth ? mockAuthBaseUrl : 'https://appwrite.sectl.cn';

  static String get authUrl =>
      useMockAuth ? mockAuthBaseUrl : 'https://sectl.cn';

  static const String authorizeEndpoint = '/oauth/authorize';
  static const String oauthScopes = 'user:read cloud:read cloud:write';
  static const String tokenEndpoint = '/api/oauth/token';
  static const String refreshEndpoint = '/api/oauth/refresh';
  static const String userInfoEndpoint = '/api/oauth/userinfo';
  static const String logoutEndpoint = '/api/oauth/logout';
  static const String publicIpLookupUrl = String.fromEnvironment(
    'SECTL_PUBLIC_IP_URL',
    defaultValue: 'https://api64.ipify.org?format=json',
  );

  static const String callbackScheme = 'secrandom';
  static const String callbackHost = 'auth';
  static const String callbackPath = '/callback';

  static const String loopbackHost = '127.0.0.1';
  static const int windowsLoopbackPort = int.fromEnvironment(
    'SECTL_WINDOWS_LOOPBACK_PORT',
    defaultValue: 8788,
  );
  static const String loopbackPath = '/callback';

  static const int webAuthCookieMaxAgeDays = 30;
  static const String webCookieAuthSignalKey = 'oauth_cookie';
  static const String webCookieAuthSignalValue = '1';

  static const String accessTokenKey = 'sectl_access_token';
  static const String refreshTokenKey = 'sectl_refresh_token';
  static const String tokenExpiresAtKey = 'sectl_token_expires_at';
  static const String userInfoKey = 'sectl_user_info';
  static const String pendingAuthSessionKey = 'sectl_pending_auth_session';
  static const String deviceUuidKey = 'sectl_device_uuid';

  static String get oauthRedirectUri {
    if (useMockAuth &&
        authCallbackBridgeUrl ==
            'https://secrandom-lite.sectl.cn/auth_callback') {
      return '$mockAuthBaseUrl/auth_callback.html';
    }
    return authCallbackBridgeUrl;
  }

  static String get webOauthRedirectUri {
    if (useMockAuth &&
        authCallbackWebUrl ==
            'https://secrandom-lite.sectl.cn/auth_callback_web.html') {
      return '$mockAuthBaseUrl/auth_callback_web.html';
    }
    return authCallbackWebUrl;
  }

  static String get androidOauthRedirectUri {
    // Android 使用 Web 跳板页接收 OAuth 回调，再通过 Deep Link 唤起应用。
    // 与桌面端的 auth_callback_windows.html 模式一致，避免 SECTL 平台
    // 对自定义 scheme 回调地址的校验问题。
    if (useMockAuth &&
        authCallbackAndroidUrl ==
            'https://secrandom-lite.sectl.cn/auth_callback_android') {
      return '$mockAuthBaseUrl/auth_callback_android.html';
    }
    return authCallbackAndroidUrl;
  }

  static String get windowsOauthRedirectUri {
    // 指向 Web 完成页，由页面把 code/state 转发到本地 loopback。
    // 浏览器始终停留在友好结果页，避免直接打开 127.0.0.1 出现「连接被拒绝」。
    if (useMockAuth &&
        authCallbackWindowsUrl ==
            'https://secrandom-lite.sectl.cn/auth_callback_windows.html') {
      return '$mockAuthBaseUrl/auth_callback_windows.html';
    }
    return authCallbackWindowsUrl;
  }

  static String get deepLinkCallbackUri =>
      '$callbackScheme://$callbackHost$callbackPath';

  static String loopbackCallbackUri(int port) =>
      'http://$loopbackHost:$port$loopbackPath';
}
