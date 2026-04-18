import 'dart:convert';

enum PendingAuthTargetPlatform { web, android, windows }

class PendingAuthSession {
  const PendingAuthSession({
    required this.state,
    required this.codeVerifier,
    required this.targetPlatform,
    required this.redirectUri,
    required this.createdAt,
    this.loopbackPort,
  });

  final String state;
  final String codeVerifier;
  final PendingAuthTargetPlatform targetPlatform;
  final String redirectUri;
  final int? loopbackPort;
  final DateTime createdAt;

  bool get isExpired =>
      DateTime.now().difference(createdAt) > const Duration(minutes: 15);

  Map<String, dynamic> toJson() {
    return {
      'state': state,
      'code_verifier': codeVerifier,
      'target_platform': targetPlatform.name,
      'redirect_uri': redirectUri,
      'loopback_port': loopbackPort,
      'created_at': createdAt.toIso8601String(),
    };
  }

  String toJsonString() => jsonEncode(toJson());

  factory PendingAuthSession.fromJson(Map<String, dynamic> json) {
    return PendingAuthSession(
      state: json['state'] as String,
      codeVerifier: json['code_verifier'] as String,
      targetPlatform: _parseTargetPlatform(json['target_platform'] as String?),
      redirectUri: (json['redirect_uri'] as String?) ?? '',
      loopbackPort: (json['loopback_port'] ?? json['desktop_port']) as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  factory PendingAuthSession.fromJsonString(String jsonString) {
    return PendingAuthSession.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );
  }

  static PendingAuthTargetPlatform _parseTargetPlatform(String? value) {
    if (value == PendingAuthTargetPlatform.web.name) {
      return PendingAuthTargetPlatform.web;
    }
    if (value == PendingAuthTargetPlatform.android.name) {
      return PendingAuthTargetPlatform.android;
    }
    if (value == PendingAuthTargetPlatform.windows.name || value == 'desktop') {
      return PendingAuthTargetPlatform.windows;
    }
    return PendingAuthTargetPlatform.web;
  }
}
