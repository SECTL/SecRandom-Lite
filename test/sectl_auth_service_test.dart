import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secrandom_lite/models/auth_token.dart';
import 'package:secrandom_lite/models/pending_auth_session.dart';
import 'package:secrandom_lite/models/user_info.dart';
import 'package:secrandom_lite/services/auth/auth_config.dart';
import 'package:secrandom_lite/services/auth/auth_web_security.dart';
import 'package:secrandom_lite/services/auth/key_value_store.dart';
import 'package:secrandom_lite/services/auth/sectl_auth_service.dart';
import 'package:secrandom_lite/services/auth/token_manager.dart';

void main() {
  final standardUuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-'
    r'[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{12}$',
  );

  group('SectlAuthService', () {
    test('authorization URL includes PKCE challenge and bridge redirect', () {
      const verifier = 'verifier-1234567890';
      final service = SectlAuthService(
        tokenManager: TokenManager(store: InMemoryKeyValueStore()),
      );
      final session = PendingAuthSession(
        state: 'state-123',
        codeVerifier: verifier,
        targetPlatform: PendingAuthTargetPlatform.web,
        redirectUri: AuthConfig.webOauthRedirectUri,
        createdAt: DateTime.now(),
      );

      final url = Uri.parse(service.getAuthorizationUrl(session));

      expect(url.queryParameters['state'], 'state-123');
      expect(url.queryParameters['code_challenge_method'], 'S256');
      expect(
        url.queryParameters['code_challenge'],
        SectlAuthService.generateCodeChallenge(verifier),
      );
      expect(
        url.queryParameters['redirect_uri'],
        'https://secrandom-online.sectl.top/auth_callback_web.html',
      );
    });

    test('exchangeCode sends code_verifier and omits client_secret', () async {
      Map<String, dynamic>? capturedBody;
      final service = SectlAuthService(
        tokenManager: TokenManager(store: InMemoryKeyValueStore()),
        httpClient: MockClient((request) async {
          if (request.url.toString() == AuthConfig.publicIpLookupUrl) {
            return http.Response(jsonEncode({'ip': '203.0.113.10'}), 200);
          }
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'access_token': 'access-token',
              'refresh_token': 'refresh-token',
              'token_type': 'Bearer',
              'expires_in': 3600,
            }),
            200,
          );
        }),
      );

      await service.exchangeCode(
        'auth-code',
        redirectUri: AuthConfig.webOauthRedirectUri,
        codeVerifier: 'pkce-verifier',
      );

      expect(capturedBody?['grant_type'], 'authorization_code');
      expect(capturedBody?['code'], 'auth-code');
      expect(capturedBody?['code_verifier'], 'pkce-verifier');
      expect(capturedBody?['device_uuid'], matches(standardUuidPattern));
      expect(capturedBody?['ip_address'], '203.0.113.10');
      expect(capturedBody?.containsKey('client_secret'), isFalse);
    });

    test('exchangeCode normalizes composite access token response', () async {
      final service = SectlAuthService(
        tokenManager: TokenManager(store: InMemoryKeyValueStore()),
        httpClient: MockClient((request) async {
          if (request.url.toString() == AuthConfig.publicIpLookupUrl) {
            return http.Response(jsonEncode({'ip': '203.0.113.10'}), 200);
          }

          return http.Response(
            jsonEncode({
              'access_token': 'jwt-token-part|embedded-refresh-token',
              'token_type': 'Bearer',
              'expires_in': 3600,
            }),
            200,
          );
        }),
      );

      final token = await service.exchangeCode(
        'auth-code',
        redirectUri: AuthConfig.webOauthRedirectUri,
        codeVerifier: 'pkce-verifier',
      );

      expect(token.accessToken, 'jwt-token-part');
      expect(token.refreshToken, 'embedded-refresh-token');
    });

    test('refreshToken sends device_uuid and ip_address', () async {
      Map<String, dynamic>? capturedBody;
      final service = SectlAuthService(
        tokenManager: TokenManager(store: InMemoryKeyValueStore()),
        httpClient: MockClient((request) async {
          if (request.url.toString() == AuthConfig.publicIpLookupUrl) {
            return http.Response(jsonEncode({'ip': '203.0.113.11'}), 200);
          }

          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'access_token': 'access-token',
              'refresh_token': 'refresh-token',
              'token_type': 'Bearer',
              'expires_in': 3600,
            }),
            200,
          );
        }),
      );

      await service.refreshToken('stored-refresh-token');

      expect(capturedBody?['grant_type'], 'refresh_token');
      expect(capturedBody?['refresh_token'], 'stored-refresh-token');
      expect(capturedBody?['device_uuid'], matches(standardUuidPattern));
      expect(capturedBody?['ip_address'], '203.0.113.11');
    });

    test(
      'AuthToken.fromJson keeps explicit refresh_token when present',
      () async {
        final token = AuthToken.fromJson({
          'access_token': 'jwt-token-part|embedded-refresh-token',
          'refresh_token': 'explicit-refresh-token',
          'token_type': 'Bearer',
          'expires_in': 3600,
        });

        expect(token.accessToken, 'jwt-token-part');
        expect(token.refreshToken, 'explicit-refresh-token');
      },
    );

    test('UserInfo.fromJson tolerates nullable backend metadata fields', () {
      final userInfo = UserInfo.fromJson({
        'user_id': 'user_123',
        'email': 'user@example.com',
        'name': 'Test User',
        'github_username': null,
        'permission': null,
        'role': null,
        'avatar_url': null,
        'background_url': null,
        'bio': null,
        'tags': null,
        'gender': null,
        'gender_visible': null,
        'birth_date': null,
        'birth_calendar_type': null,
        'birth_year_visible': null,
        'birth_visible': null,
        'location': null,
        'location_visible': null,
        'website': null,
        'email_visible': null,
        'developed_platforms': null,
        'contributed_platforms': null,
        'user_type': null,
        'created_at': null,
        'platform_id': null,
        'login_time': null,
      });

      expect(userInfo.permission, 'user');
      expect(userInfo.role, '普通用户');
      expect(userInfo.bio, '');
      expect(userInfo.gender, 'secret');
      expect(userInfo.createdAt, '');
      expect(userInfo.platformId, '');
      expect(userInfo.loginTime, '');
    });

    test(
      'invalid persisted device_uuid is replaced with standard UUID',
      () async {
        final store = InMemoryKeyValueStore();
        await store.write(
          key: 'sectl_device_uuid',
          value: '69d054360032cf00c164_deadbeefdeadbeefdeadbeefdeadbeef',
        );

        final tokenManager = TokenManager(store: store);
        final deviceUuid = await tokenManager.getOrCreateDeviceUuid();

        expect(deviceUuid, matches(standardUuidPattern));
        expect(await store.read(key: 'sectl_device_uuid'), deviceUuid);
      },
    );

    test('trusted web callback URI only accepts configured app origin', () {
      final trustedUri = parseTrustedWebAppCallbackUri(
        'https://secrandom-online.sectl.top/?code=abc&state=state-123#ignored',
      );
      final untrustedUri = parseTrustedWebAppCallbackUri(
        'https://evil.example/?code=abc&state=state-123',
      );

      expect(trustedUri, isNotNull);
      expect(trustedUri?.origin, 'https://secrandom-online.sectl.top');
      expect(trustedUri?.fragment, isEmpty);
      expect(untrustedUri, isNull);
    });

    test(
      'trusted web callback URI rejects credential-bearing redirect URLs',
      () {
        final uri = parseTrustedWebAppCallbackUri(
          'https://user:pass@secrandom-online.sectl.top/?code=abc',
        );

        expect(uri, isNull);
      },
    );

    test(
      'trusted web popup callback message requires origin and popup source',
      () {
        expect(
          isTrustedWebPopupCallbackMessage(
            messageType: 'sectl-auth-callback',
            href:
                'https://secrandom-online.sectl.top/?code=abc&state=state-123',
            eventOrigin: 'https://secrandom-online.sectl.top',
            isFromExpectedPopupWindow: true,
          ),
          isTrue,
        );

        expect(
          isTrustedWebPopupCallbackMessage(
            messageType: 'sectl-auth-callback',
            href:
                'https://secrandom-online.sectl.top/?code=abc&state=state-123',
            eventOrigin: 'https://evil.example',
            isFromExpectedPopupWindow: true,
          ),
          isFalse,
        );

        expect(
          isTrustedWebPopupCallbackMessage(
            messageType: 'sectl-auth-callback',
            href:
                'https://secrandom-online.sectl.top/?code=abc&state=state-123',
            eventOrigin: 'https://secrandom-online.sectl.top',
            isFromExpectedPopupWindow: false,
          ),
          isFalse,
        );
      },
    );

    test(
      'completeLoginFromCallbackUri clears pending session on auth error',
      () async {
        final tokenManager = TokenManager(store: InMemoryKeyValueStore());
        await tokenManager.savePendingAuthSession(
          PendingAuthSession(
            state: 'state-value',
            codeVerifier: 'verifier',
            targetPlatform: PendingAuthTargetPlatform.web,
            redirectUri: AuthConfig.webOauthRedirectUri,
            createdAt: DateTime.now(),
          ),
        );

        final service = SectlAuthService(tokenManager: tokenManager);

        await expectLater(
          service.completeLoginFromCallbackUri(
            Uri.parse(
              'https://example.com/?error=access_denied&error_description=denied&state=state-value',
            ),
          ),
          throwsA(isA<AuthApiException>()),
        );

        expect(await tokenManager.getPendingAuthSession(), isNull);
      },
    );

    test(
      'restoreValidSession clears local auth state on invalid token',
      () async {
        final tokenManager = TokenManager(store: InMemoryKeyValueStore());
        await tokenManager.saveToken(
          await SectlAuthService(
            tokenManager: tokenManager,
            httpClient: MockClient((request) async {
              return http.Response(
                jsonEncode({
                  'access_token': 'unused',
                  'refresh_token': 'unused',
                  'token_type': 'Bearer',
                  'expires_in': 3600,
                }),
                200,
              );
            }),
          ).exchangeCode(
            'seed-code',
            redirectUri: AuthConfig.webOauthRedirectUri,
            codeVerifier: 'seed-verifier',
          ),
        );

        final service = SectlAuthService(
          tokenManager: tokenManager,
          httpClient: MockClient((request) async {
            if (request.url.path.endsWith('/api/oauth/userinfo')) {
              return http.Response(
                jsonEncode({
                  'error': 'invalid_token',
                  'error_description':
                      'The access token is invalid or has expired',
                }),
                401,
              );
            }
            return http.Response('{}', 404);
          }),
        );

        final restored = await service.restoreValidSession();

        expect(restored, isNull);
        expect(await tokenManager.getToken(), isNull);
        expect(await tokenManager.getUserInfo(), isNull);
      },
    );
  });
}
