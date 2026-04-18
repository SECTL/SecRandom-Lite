/// OAuth Token 模型
class AuthToken {
  final String accessToken;
  final String? refreshToken;
  final String tokenType;
  final int expiresIn;
  final DateTime? expiresAt;

  AuthToken({
    required this.accessToken,
    this.refreshToken,
    required this.tokenType,
    required this.expiresIn,
    this.expiresAt,
  });

  factory AuthToken.fromJson(Map<String, dynamic> json) {
    final expiresIn = json['expires_in'] is int
        ? json['expires_in'] as int
        : int.parse(json['expires_in'].toString());
    final expiresAt = expiresIn > 0
        ? DateTime.now().add(Duration(seconds: expiresIn))
        : null;
    final rawAccessToken = json['access_token'] as String;
    final rawRefreshToken = json['refresh_token'] as String?;

    final tokenParts = rawAccessToken.split('|');
    final normalizedAccessToken = tokenParts.first;
    final normalizedRefreshToken =
        rawRefreshToken ?? (tokenParts.length > 1 ? tokenParts[1] : null);

    return AuthToken(
      accessToken: normalizedAccessToken,
      refreshToken: normalizedRefreshToken,
      tokenType: json['token_type'] as String? ?? 'Bearer',
      expiresIn: expiresIn,
      expiresAt: expiresAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'token_type': tokenType,
      'expires_in': expiresIn,
      'expires_at': expiresAt?.toIso8601String(),
    };
  }

  /// 检查 token 是否已过期
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// 检查 token 是否即将过期（5分钟内）
  bool get isExpiringSoon {
    if (expiresAt == null) return false;
    final fiveMinutesLater = DateTime.now().add(const Duration(minutes: 5));
    return fiveMinutesLater.isAfter(expiresAt!);
  }
}
