import 'dart:convert';
import 'package:http/http.dart' as http;

import '../auth/auth_config.dart';
import '../auth/token_manager.dart';
import '../../utils/logger.dart';

/// SECTL 云 API 异常
class CloudApiException implements Exception {
  const CloudApiException({
    required this.statusCode,
    required this.error,
    this.description = '',
  });

  final int statusCode;
  final String error;
  final String description;

  bool get isInvalidToken =>
      statusCode == 401 || error.toLowerCase() == 'invalid_token';
  bool get isInsufficientScope =>
      statusCode == 403 || error.toLowerCase() == 'insufficient_scope';
  bool get isNotFound => error.toLowerCase() == 'not_found';

  @override
  String toString() => 'CloudApiException($statusCode): $error $description';
}

/// SECTL 云 KV 单条数据
class CloudKvEntry {
  const CloudKvEntry({
    required this.key,
    required this.value,
    required this.size,
    required this.isJson,
    this.createdAt,
    this.updatedAt,
  });

  final String key;
  final dynamic value;
  final int size;
  final bool isJson;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory CloudKvEntry.fromJson(Map<String, dynamic> json) {
    return CloudKvEntry(
      key: json['key'] as String,
      value: json['value'],
      size: json['size'] as int? ?? 0,
      isJson: json['is_json'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }
}

/// SECTL 云 KV 列表响应
class CloudKvList {
  const CloudKvList({required this.entries, required this.total, required this.hasMore});

  final List<CloudKvEntry> entries;
  final int total;
  final bool hasMore;
}

/// SECTL 云存储用量
class CloudStorageUsage {
  const CloudStorageUsage({
    required this.usedStorage,
    required this.totalStorage,
    required this.availableStorage,
    required this.percentage,
    required this.fileCount,
  });

  final int usedStorage;
  final int totalStorage;
  final int availableStorage;
  final int percentage;
  final int fileCount;

  factory CloudStorageUsage.fromJson(Map<String, dynamic> json) {
    return CloudStorageUsage(
      usedStorage: json['used_storage'] as int? ?? 0,
      totalStorage: json['total_storage'] as int? ?? 0,
      availableStorage: json['available_storage'] as int? ?? 0,
      percentage: json['percentage'] as int? ?? 0,
      fileCount: json['file_count'] as int? ?? 0,
    );
  }
}

/// SECTL 云 KV API 封装
///
/// 使用 OAuth Bearer Token 认证，user_id 从 token claims 推导。
/// 所有读操作需要 `cloud:read`，写操作需要 `cloud:write`。
class SectlCloudApi {
  SectlCloudApi({TokenManager? tokenManager, http.Client? httpClient})
      : _tokenManager = tokenManager ?? TokenManager(),
        _httpClient = httpClient ?? http.Client();

  final TokenManager _tokenManager;
  final http.Client _httpClient;

  String get _baseUrl => AuthConfig.baseUrl;
  String get _clientId => AuthConfig.platformId;

  // ── KV 操作 ──────────────────────────────────────────────

  /// 创建或更新 KV
  Future<CloudKvEntry> putKv({
    required String key,
    required dynamic value,
    int? ttl,
  }) async {
    final response = await _post('/api/cloud/kv', {
      'client_id': _clientId,
      'key': key,
      'value': value,
      if (ttl != null) 'ttl': ttl,
    });
    final data = _decode(response);
    logger.d('Cloud KV put: $key (${data['size']} bytes)');
    return CloudKvEntry.fromJson({
      'key': key,
      'value': value,
      'size': data['size'] ?? 0,
      'is_json': data['is_json'] ?? true,
      'created_at': data['created_at'],
      'updated_at': data['updated_at'],
    });
  }

  /// 获取 KV 列表
  Future<CloudKvList> listKv({int limit = 100, int offset = 0}) async {
    final response = await _get('/api/cloud/kv', {
      'client_id': _clientId,
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
    final data = _decode(response);
    final list = (data['kv_list'] as List? ?? [])
        .map((e) => CloudKvEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    return CloudKvList(
      entries: list,
      total: data['total'] as int? ?? 0,
      hasMore: data['has_more'] as bool? ?? false,
    );
  }

  /// 获取单个 KV
  Future<CloudKvEntry> getKv(String key, {String? field}) async {
    final queryParams = {'client_id': _clientId};
    if (field != null) queryParams['field'] = field;

    final response = await _get('/api/cloud/kv/$key', queryParams);
    final data = _decode(response);
    return CloudKvEntry.fromJson(data);
  }

  /// 获取单个 KV 的值（便捷方法）
  Future<dynamic> getKvValue(String key) async {
    final entry = await getKv(key);
    return entry.value;
  }

  /// 更新 KV 的某个 JSON 字段（增量）
  Future<void> patchKvField({
    required String key,
    required String field,
    required dynamic value,
  }) async {
    await _patch('/api/cloud/kv/$key', {
      'client_id': _clientId,
      'field': field,
      'value': value,
    });
    logger.d('Cloud KV patch: $key.$field');
  }

  /// 删除 KV
  Future<void> deleteKv(String key) async {
    await _delete('/api/cloud/kv/$key', {'client_id': _clientId});
    logger.d('Cloud KV delete: $key');
  }

  // ── 存储用量 ──────────────────────────────────────────────

  /// 获取存储使用情况
  Future<CloudStorageUsage> getStorageUsage() async {
    final response = await _get('/api/cloud/storage/usage', {
      'client_id': _clientId,
    });
    return CloudStorageUsage.fromJson(_decode(response));
  }

  // ── 文件操作 ──────────────────────────────────────────────

  /// 上传文件（multipart/form-data），返回响应 JSON
  Future<Map<String, dynamic>> uploadFile({
    required List<int> bytes,
    required String filename,
    String mimeType = 'application/json',
  }) async {
    final headers = await _authHeaders();
    headers.remove('Content-Type');
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/api/cloud/upload'),
    )
      ..fields['client_id'] = _clientId
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
      ))
      ..headers.addAll(headers);
    final streamed = await _httpClient.send(request);
    final response = await http.Response.fromStream(streamed);
    _checkError(response);
    logger.d('Cloud file upload: $filename (${bytes.length} bytes)');
    return _decode(response);
  }

  /// 文件列表（最多 1000 条）
  Future<List<Map<String, dynamic>>> listFiles() async {
    final response = await _get('/api/cloud/files', {
      'client_id': _clientId,
      'limit': '1000',
    });
    final data = _decode(response);
    return ((data['files'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  /// 获取文件下载链接
  Future<String> getFileDownloadUrl(String fileId) async {
    final response = await _get('/api/cloud/files/$fileId/download', {
      'client_id': _clientId,
    });
    final data = _decode(response);
    final url = data['download_url'] as String?;
    if (url == null || url.isEmpty) {
      throw const CloudApiException(
        statusCode: 500,
        error: 'internal_error',
        description: '下载链接缺失',
      );
    }
    return url;
  }

  /// 按下载链接读取文件字节
  Future<List<int>> downloadFileBytes(String downloadUrl) async {
    final response = await _httpClient.get(Uri.parse(downloadUrl));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudApiException(
        statusCode: response.statusCode,
        error: 'download_failed',
      );
    }
    return response.bodyBytes;
  }

  /// 删除文件
  Future<void> deleteFile(String fileId) async {
    await _delete('/api/cloud/files/$fileId', {'client_id': _clientId});
    logger.d('Cloud file delete: $fileId');
  }

  // ── 内部 HTTP 方法 ──────────────────────────────────────────

  Future<Map<String, String>> _authHeaders() async {
    final token = await _tokenManager.getAccessToken();
    if (token == null || token.isEmpty) {
      throw const CloudApiException(
        statusCode: 401,
        error: 'invalid_token',
        description: '未登录或 Token 已失效',
      );
    }
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Future<http.Response> _get(String path, Map<String, String> params) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: params);
    final response = await _httpClient.get(uri, headers: headers);
    _checkError(response);
    return response;
  }

  Future<http.Response> _post(String path, Map<String, dynamic> body) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$_baseUrl$path');
    final response = await _httpClient.post(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );
    _checkError(response);
    return response;
  }

  Future<http.Response> _patch(String path, Map<String, dynamic> body) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$_baseUrl$path');
    final response = await _httpClient.patch(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );
    _checkError(response);
    return response;
  }

  Future<http.Response> _delete(String path, Map<String, dynamic> body) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$_baseUrl$path');
    final response = await _httpClient.delete(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );
    _checkError(response);
    return response;
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.isEmpty) return {};
    try {
      return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      throw CloudApiException(
        statusCode: response.statusCode,
        error: 'internal_error',
        description: '响应解析失败: $e',
      );
    }
  }

  void _checkError(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    String error = 'internal_error';
    String description = 'HTTP ${response.statusCode}';

    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      error = data['error'] as String? ?? error;
      description = data['error_description'] as String? ?? description;
    } catch (_) {
      // body 不是 JSON，用默认描述
    }

    throw CloudApiException(
      statusCode: response.statusCode,
      error: error,
      description: description,
    );
  }
}
