import 'dart:async';

import 'sectl_auth_service.dart';

/// 将登录相关异常映射为可展示给用户的中文文案。
String describeAuthError(Object error) {
  if (error is LoginCancelledException) {
    return '已取消登录';
  }
  if (error is TimeoutException) {
    return '登录超时，请重试';
  }
  if (error is UnsupportedError) {
    return '当前平台暂不支持登录';
  }
  if (error is AuthApiException) {
    if (error.isInvalidToken) {
      return '登录已失效，请重新登录';
    }
    final code = error.error.toLowerCase();
    final description = error.description.toLowerCase();
    if (code.contains('access_denied') || description.contains('access_denied') ||
        description.contains('denied')) {
      return '已取消授权';
    }
    if (code.contains('network') || description.contains('network')) {
      return '网络异常，请稍后重试';
    }
    return '登录失败，请稍后重试';
  }
  if (error is StateError) {
    return '登录未完成，请重试';
  }
  return '登录失败，请稍后重试';
}
