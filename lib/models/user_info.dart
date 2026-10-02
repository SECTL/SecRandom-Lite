import 'dart:convert';

/// SECTL 用户信息模型
class UserInfo {
  final String userId;
  final String email;
  final String name;
  final String? githubUsername;
  final String permission;
  final String role;
  final String? avatarUrl;
  final String? backgroundUrl;
  final String bio;
  final List<String> tags;
  final String gender;
  final bool genderVisible;
  final String? birthDate;
  final String? birthCalendarType;
  final bool birthYearVisible;
  final bool birthVisible;
  final String? location;
  final bool locationVisible;
  final String? website;
  final bool emailVisible;
  final List<String> developedPlatforms;
  final List<String> contributedPlatforms;
  final String userType;
  final String createdAt;
  final String platformId;
  final String loginTime;
  final bool isDeveloper;
  final bool isContributor;
  final String responsibility;

  UserInfo({
    required this.userId,
    required this.email,
    required this.name,
    this.githubUsername,
    required this.permission,
    required this.role,
    this.avatarUrl,
    this.backgroundUrl,
    required this.bio,
    required this.tags,
    required this.gender,
    required this.genderVisible,
    this.birthDate,
    this.birthCalendarType,
    required this.birthYearVisible,
    required this.birthVisible,
    this.location,
    required this.locationVisible,
    this.website,
    required this.emailVisible,
    required this.developedPlatforms,
    required this.contributedPlatforms,
    required this.userType,
    required this.createdAt,
    required this.platformId,
    required this.loginTime,
    this.isDeveloper = false,
    this.isContributor = false,
    this.responsibility = '',
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      userId: _stringValue(json['user_id']),
      email: _stringValue(json['email']),
      name: _stringValue(json['name'], fallback: '用户'),
      githubUsername: json['github_username'] as String?,
      permission: _permissionValue(json['permission']),
      role: _stringValue(json['role'], fallback: '普通用户'),
      avatarUrl: json['avatar_url'] as String?,
      backgroundUrl: json['background_url'] as String?,
      bio: json['bio'] as String? ?? '',
      tags: json['tags'] is List
          ? (json['tags'] as List<dynamic>).map((e) => e.toString()).toList()
          : [],
      gender: json['gender'] as String? ?? 'secret',
      genderVisible: json['gender_visible'] as bool? ?? false,
      birthDate: json['birth_date'] as String?,
      birthCalendarType: json['birth_calendar_type'] as String?,
      birthYearVisible: json['birth_year_visible'] as bool? ?? false,
      birthVisible: json['birth_visible'] as bool? ?? false,
      location: json['location'] as String?,
      locationVisible: json['location_visible'] as bool? ?? false,
      website: json['website'] as String?,
      emailVisible: json['email_visible'] as bool? ?? false,
      developedPlatforms:
          (json['developed_platforms'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      contributedPlatforms:
          (json['contributed_platforms'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      userType: json['user_type'] as String? ?? 'normal',
      createdAt: _stringValue(json['created_at']),
      platformId: _stringValue(json['platform_id']),
      loginTime: _stringValue(json['login_time']),
      isDeveloper: json['is_developer'] as bool? ?? false,
      isContributor: json['is_contributor'] as bool? ?? false,
      responsibility: _stringValue(json['responsibility']),
    );
  }

  /// API 文档中 permission 为数字等级（默认 1），兼容历史字符串取值。
  static String _permissionValue(Object? value) {
    if (value == null) return '1';
    if (value is num) return value.toInt().toString();
    final text = value.toString().trim();
    return text.isEmpty ? '1' : text;
  }

  static String _stringValue(Object? value, {String fallback = ''}) {
    if (value == null) {
      return fallback;
    }

    final text = value.toString();
    return text.isEmpty ? fallback : text;
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'email': email,
      'name': name,
      'github_username': githubUsername,
      'permission': permission,
      'role': role,
      'avatar_url': avatarUrl,
      'background_url': backgroundUrl,
      'bio': bio,
      'tags': tags,
      'gender': gender,
      'gender_visible': genderVisible,
      'birth_date': birthDate,
      'birth_calendar_type': birthCalendarType,
      'birth_year_visible': birthYearVisible,
      'birth_visible': birthVisible,
      'location': location,
      'location_visible': locationVisible,
      'website': website,
      'email_visible': emailVisible,
      'developed_platforms': developedPlatforms,
      'contributed_platforms': contributedPlatforms,
      'user_type': userType,
      'created_at': createdAt,
      'platform_id': platformId,
      'login_time': loginTime,
      'is_developer': isDeveloper,
      'is_contributor': isContributor,
      'responsibility': responsibility,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  factory UserInfo.fromJsonString(String jsonString) {
    return UserInfo.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }
}
