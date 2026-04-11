import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secrandom_lite/models/pending_auth_session.dart';
import 'package:secrandom_lite/services/auth/auth_web_security.dart';
import 'package:secrandom_lite/services/auth/key_value_store.dart';
import 'package:secrandom_lite/services/auth/sectl_auth_service.dart';
import 'package:secrandom_lite/services/auth/token_manager.dart';

void main() {
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
        'https://secrandom-online.sectl.top/auth_callback',
      );
    });

    test('exchangeCode sends code_verifier and omits client_secret', () async {
      Map<String, dynamic>? capturedBody;
      final service = SectlAuthService(
        tokenManager: TokenManager(store: InMemoryKeyValueStore()),
        httpClient: MockClient((request) async {
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

      await service.exchangeCode('auth-code', codeVerifier: 'pkce-verifier');

      expect(capturedBody?['grant_type'], 'authorization_code');
      expect(capturedBody?['code'], 'auth-code');
      expect(capturedBody?['code_verifier'], 'pkce-verifier');
      expect(capturedBody?['device_uuid'], isNotNull);
      expect(capturedBody?.containsKey('client_secret'), isFalse);
    });

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
          ).exchangeCode('seed-code', codeVerifier: 'seed-verifier'),
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
