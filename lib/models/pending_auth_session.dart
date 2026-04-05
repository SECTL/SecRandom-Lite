import 'dart:convert';

enum PendingAuthTargetPlatform { web, android, desktop }

class PendingAuthSession {
  const PendingAuthSession({
    required this.state,
    required this.codeVerifier,
    required this.targetPlatform,
    required this.createdAt,
    this.desktopPort,
  });

  final String state;
  final String codeVerifier;
  final PendingAuthTargetPlatform targetPlatform;
  final int? desktopPort;
  final DateTime createdAt;

  bool get isExpired =>
      DateTime.now().difference(createdAt) > const Duration(minutes: 15);

  Map<String, dynamic> toJson() {
    return {
      'state': state,
      'code_verifier': codeVerifier,
      'target_platform': targetPlatform.name,
      'desktop_port': desktopPort,
      'created_at': createdAt.toIso8601String(),
    };
  }

  String toJsonString() => jsonEncode(toJson());

  factory PendingAuthSession.fromJson(Map<String, dynamic> json) {
    return PendingAuthSession(
      state: json['state'] as String,
      codeVerifier: json['code_verifier'] as String,
      targetPlatform: PendingAuthTargetPlatform.values.firstWhere(
        (value) => value.name == json['target_platform'],
      ),
      desktopPort: json['desktop_port'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  factory PendingAuthSession.fromJsonString(String jsonString) {
    return PendingAuthSession.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );
  }
}
