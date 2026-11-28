enum AnimationMode { auto, manualStop, none }

extension AnimationModeX on AnimationMode {
  String toJsonValue() => name;

  static AnimationMode fromJsonValue(dynamic value) {
    final raw = value?.toString();
    return AnimationMode.values.firstWhere(
      (mode) => mode.name == raw,
      orElse: () => AnimationMode.auto,
    );
  }
}

class AppConfig {
  final String themeMode; // 'system', 'light', 'dark'
  final int themeColor; // ARGB
  final int selectCount;
  final String? selectedClass;
  final List<String> groups;
  final Map<String, List<String>>
  classGroups; // Map of class name to list of groups
  final bool nonRepeatEnabled;
  final double rollcallResultFontSize;
  final AnimationMode rollcallAnimationMode;

  /// 默认主题色与 `main.dart` 原有的品牌蓝保持一致。
  static const int defaultThemeColor = 0xFF66CCFF;

  AppConfig({
    required this.themeMode,
    this.themeColor = defaultThemeColor,
    this.selectCount = 1,
    this.selectedClass,
    this.groups = const ['1'],
    this.classGroups = const {},
    this.nonRepeatEnabled = true,
    this.rollcallResultFontSize = 48,
    this.rollcallAnimationMode = AnimationMode.auto,
  });

  Map<String, dynamic> toJson() {
    return {
      'theme_mode': themeMode,
      'theme_color': themeColor,
      'select_count': selectCount,
      'selected_class': selectedClass,
      'groups': groups,
      'class_groups': classGroups,
      'non_repeat_enabled': nonRepeatEnabled,
      'rollcall_result_font_size': rollcallResultFontSize,
      'rollcall_animation_mode': rollcallAnimationMode.toJsonValue(),
    };
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      themeMode: json['theme_mode'] ?? 'system',
      themeColor: (json['theme_color'] as num?)?.toInt() ?? defaultThemeColor,
      selectCount: json['select_count'] ?? 1,
      selectedClass: json['selected_class'],
      groups:
          (json['groups'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          ['1'],
      classGroups:
          (json['class_groups'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(
              key,
              (value as List<dynamic>).map((e) => e.toString()).toList(),
            ),
          ) ??
          {},
      nonRepeatEnabled: json['non_repeat_enabled'] as bool? ?? true,
      rollcallResultFontSize:
          (json['rollcall_result_font_size'] as num?)?.toDouble() ?? 48,
      rollcallAnimationMode: AnimationModeX.fromJsonValue(
        json['rollcall_animation_mode'],
      ),
    );
  }

  // 默认配置
  factory AppConfig.defaultConfig() {
    return AppConfig(
      themeMode: 'system',
      selectCount: 1,
      selectedClass: null,
      groups: ['1'],
      classGroups: {},
      nonRepeatEnabled: true,
      rollcallResultFontSize: 48,
      rollcallAnimationMode: AnimationMode.auto,
    );
  }
}
