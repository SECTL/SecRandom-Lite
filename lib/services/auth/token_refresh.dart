import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/auth_token.dart';
import '../../utils/logger.dart';
import 'auth_config.dart';
import 'client_ip.dart';
import 'token_manager.dart';

/// 进程级 singleflight：并发的刷新请求共享同一次 refresh_token 兑换，
/// 避免 refresh token 轮换时后到的请求用已作废的 token 再次刷新而失败。
Future<AuthToken?>? _inFlightRefresh;

Map<String, dynamic> buildRefreshPayload({
  required String refreshToken,
  required String deviceUuid,
  required String ipAddress,
}) {
  return {
    'grant_type': 'refresh_token',
    'refresh_token': refreshToken,
    'client_id': AuthConfig.platformId,
    'device_uuid': deviceUuid,
    'ip_address': ipAddress,
  };
}

/// 解析出口公网 IP；查询失败时回退到本机 IP / 127.0.0.1。
Future<String> resolvePublicIpAddress(http.Client httpClient) async {
  try {
    final response = await httpClient
        .get(Uri.parse(AuthConfig.publicIpLookupUrl))
        .timeout(const Duration(seconds: 5));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) {
        final ip = data['ip'];
        if (ip is String && ip.isNotEmpty) {
          return ip;
        }
      }
    }
  } catch (_) {
    // Fall back to local IP resolution.
  }

  final localIp = await getLocalIpAddress();
  if (localIp != null && localIp.isNotEmpty) {
    return localIp;
  }

  return '127.0.0.1';
}

/// 用 refresh token 换取新 access token 并落盘（含浏览器 cookie 同步）。
///
/// 进程内同一时刻只会有一次真实请求，其余调用方等待同一结果。
/// 返回 null 表示刷新失败（网络错误、服务端拒绝或本地无 refresh token）。
Future<AuthToken?> refreshStoredToken({
  required http.Client httpClient,
  required TokenManager tokenManager,
  required String refreshToken,
}) {
  final inflight = _inFlightRefresh;
  if (inflight != null) return inflight;

  final future = _doRefresh(
    httpClient: httpClient,
    tokenManager: tokenManager,
    refreshToken: refreshToken,
  );
  _inFlightRefresh = future;
  return future.whenComplete(() => _inFlightRefresh = null);
}

Future<AuthToken?> _doRefresh({
  required http.Client httpClient,
  required TokenManager tokenManager,
  required String refreshToken,
}) async {
  try {
    final deviceUuid = await tokenManager.getOrCreateDeviceUuid();
    final ipAddress = await resolvePublicIpAddress(httpClient);
    final url = Uri.parse(
      '${AuthConfig.baseUrl}${AuthConfig.refreshEndpoint}',
    );
    final response = await httpClient.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(
        buildRefreshPayload(
          refreshToken: refreshToken,
          deviceUuid: deviceUuid,
          ipAddress: ipAddress,
        ),
      ),
    );

    if (response.statusCode != 200) {
      logger.w(
        'Token refresh rejected: HTTP ${response.statusCode} ${response.body}',
      );
      return null;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = AuthToken.fromJson(data);
    await tokenManager.saveToken(token);
    logger.d('Token refreshed, expires at ${token.expiresAt}');
    return token;
  } catch (error) {
    logger.w('Token refresh failed: $error');
    return null;
  }
}
