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
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      userId: json['user_id'] as String,
      email: json['email'] as String,
      name: json['name'] as String,
      githubUsername: json['github_username'] as String?,
      permission: json['permission'].toString(),
      role: json['role'] as String,
      avatarUrl: json['avatar_url'] as String?,
      backgroundUrl: json['background_url'] as String?,
      bio: json['bio'] as String? ?? '',
      tags: json['tags'] is List ? (json['tags'] as List<dynamic>).map((e) => e.toString()).toList() : [],
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
      developedPlatforms: (json['developed_platforms'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      contributedPlatforms: (json['contributed_platforms'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      userType: json['user_type'] as String? ?? 'normal',
      createdAt: json['created_at'] as String,
      platformId: json['platform_id'] as String,
      loginTime: json['login_time'] as String,
    );
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
    };
  }

  String toJsonString() => jsonEncode(toJson());

  factory UserInfo.fromJsonString(String jsonString) {
    return UserInfo.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }
}
