import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secrandom_lite/services/auth/auth_config.dart';
import 'package:secrandom_lite/services/auth/key_value_store.dart';
import 'package:secrandom_lite/services/auth/token_manager.dart';
import 'package:secrandom_lite/services/cloud/cloud_api.dart';

void main() {
  test('uploadFile 通过 query 传 client_id，multipart 不含 client_id 字段', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({'success': true, 'file_id': 'cf_1'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = SectlCloudApi(
      httpClient: client,
      tokenManager: TokenManager(
        store: InMemoryKeyValueStore({
          AuthConfig.accessTokenKey: 'test-token',
        }),
      ),
    );

    await api.uploadFile(bytes: utf8.encode('{}'), filename: 'b.json');

    expect(captured.url.path, '/api/cloud/upload');
    expect(captured.url.queryParameters['client_id'], AuthConfig.platformId);
    expect(captured.headers['Authorization'], 'Bearer test-token');
    expect(captured.body.contains('name="client_id"'), isFalse,
        reason: 'multipart 字段会触发服务端 canonical 比较导致 403');
    expect(captured.body.contains('name="file"'), isTrue);
  });
}
