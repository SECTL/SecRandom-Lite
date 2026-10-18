import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:secrandom_lite/services/auth/auth_error_messages.dart';
import 'package:secrandom_lite/services/auth/sectl_auth_service.dart';

void main() {
  group('describeAuthError', () {
    test('maps cancel exception', () {
      expect(
        describeAuthError(const LoginCancelledException()),
        '已取消登录',
      );
    });

    test('maps timeout', () {
      expect(describeAuthError(TimeoutException('x')), '登录超时，请重试');
    });

    test('maps unsupported platform', () {
      expect(describeAuthError(UnsupportedError('iOS')), '当前平台暂不支持登录');
    });

    test('maps invalid token', () {
      expect(
        describeAuthError(
          const AuthApiException(
            statusCode: 401,
            error: 'invalid_token',
            description: 'expired',
          ),
        ),
        '登录已失效，请重新登录',
      );
    });

    test('maps access denied', () {
      expect(
        describeAuthError(
          const AuthApiException(
            statusCode: 400,
            error: 'access_denied',
            description: 'User denied',
          ),
        ),
        '已取消授权',
      );
    });

    test('maps unknown errors to generic message', () {
      expect(describeAuthError(Exception('boom')), '登录失败，请稍后重试');
    });
  });
}
