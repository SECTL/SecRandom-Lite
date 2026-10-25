import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secrandom_lite/services/auth/auth_config.dart';
import 'package:secrandom_lite/services/auth/key_value_store.dart';
import 'package:secrandom_lite/services/auth/token_manager.dart';
import 'package:secrandom_lite/services/cloud/cloud_api.dart';

void main() {
  late TokenManager tokenManager;
  late int refreshCallCount;

  setUp(() {
    refreshCallCount = 0;
    tokenManager = TokenManager(
      store: InMemoryKeyValueStore({
        AuthConfig.accessTokenKey: 'old-access',
        AuthConfig.refreshTokenKey: 'stored-refresh',
      }),
    );
  });

  http.Client buildClient({
    bool refreshSucceeds = true,
    void Function(Map<String, dynamic>? refreshBody)? onRefresh,
  }) {
    return MockClient((request) async {
      if (request.url.toString() == AuthConfig.publicIpLookupUrl) {
        return http.Response(jsonEncode({'ip': '203.0.113.30'}), 200);
      }

      if (request.url.path == AuthConfig.refreshEndpoint) {
        refreshCallCount++;
        final body =
            jsonDecode(request.body) as Map<String, dynamic>;
        onRefresh?.call(body);
        if (!refreshSucceeds) {
          return http.Response(
            jsonEncode({
              'error': 'invalid_grant',
              'error_description': 'refresh token revoked',
            }),
            400,
          );
        }
        return http.Response(
          jsonEncode({
            'access_token': 'new-access',
            'refresh_token': 'new-refresh',
            'token_type': 'Bearer',
            'expires_in': 3600,
          }),
          200,
        );
      }

      final auth = request.headers['authorization'];
      if (auth != 'Bearer new-access') {
        return http.Response(
          jsonEncode({
            'error': 'invalid_token',
            'error_description': 'The access token is invalid or has expired',
          }),
          401,
        );
      }

      return http.Response(
        jsonEncode({
          'key': request.url.pathSegments.last,
          'value': {'ok': true},
          'size': 12,
          'is_json': true,
        }),
        200,
      );
    });
  }

  test('401 后自动用 refresh token 换新并重放请求', () async {
    Map<String, dynamic>? refreshBody;
    final api = SectlCloudApi(
      httpClient: buildClient(onRefresh: (body) => refreshBody = body),
      tokenManager: tokenManager,
    );

    final value = await api.getKvValue('srlite.test.key');

    expect(value, {'ok': true});
    expect(refreshCallCount, 1);
    expect(refreshBody?['grant_type'], 'refresh_token');
    expect(refreshBody?['refresh_token'], 'stored-refresh');
    expect(await tokenManager.getAccessToken(), 'new-access');
    expect(await tokenManager.getRefreshToken(), 'new-refresh');
  });

  test('并发 401 只触发一次刷新（singleflight）', () async {
    final api = SectlCloudApi(
      httpClient: buildClient(),
      tokenManager: tokenManager,
    );

    final results = await Future.wait([
      api.getKvValue('srlite.test.a'),
      api.getKvValue('srlite.test.b'),
      api.getKvValue('srlite.test.c'),
    ]);

    expect(results, everyElement({'ok': true}));
    expect(refreshCallCount, 1);
  });

  test('刷新失败时抛出 401 且不重放', () async {
    final api = SectlCloudApi(
      httpClient: buildClient(refreshSucceeds: false),
      tokenManager: tokenManager,
    );

    await expectLater(
      api.getKvValue('srlite.test.key'),
      throwsA(
        isA<CloudApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.error, 'error', 'invalid_token'),
      ),
    );
    expect(refreshCallCount, 1);
  });

  test('本地无 refresh token 时 401 直接失败', () async {
    final bareManager = TokenManager(
      store: InMemoryKeyValueStore({AuthConfig.accessTokenKey: 'old-access'}),
    );
    final api = SectlCloudApi(
      httpClient: buildClient(),
      tokenManager: bareManager,
    );

    await expectLater(
      api.getKvValue('srlite.test.key'),
      throwsA(isA<CloudApiException>().having((e) => e.statusCode, 'statusCode', 401)),
    );
    expect(refreshCallCount, 0);
  });
}
