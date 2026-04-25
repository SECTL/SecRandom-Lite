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
  final int selectCount;
  final String? selectedClass;
  final List<String> groups;
  final Map<String, List<String>>
  classGroups; // Map of class name to list of groups
  final bool fairDrawEnabled;
  final bool nonRepeatEnabled;
  final double rollcallResultFontSize;
  final double lotteryResultFontSize;
  final AnimationMode rollcallAnimationMode;
  final AnimationMode lotteryAnimationMode;

  AppConfig({
    required this.themeMode,
    this.selectCount = 1,
    this.selectedClass,
    this.groups = const ['1'],
    this.classGroups = const {},
    this.fairDrawEnabled = true,
    this.nonRepeatEnabled = true,
    this.rollcallResultFontSize = 48,
    this.lotteryResultFontSize = 48,
    this.rollcallAnimationMode = AnimationMode.auto,
    this.lotteryAnimationMode = AnimationMode.auto,
  });

  Map<String, dynamic> toJson() {
    return {
      'theme_mode': themeMode,
      'select_count': selectCount,
      'selected_class': selectedClass,
      'groups': groups,
      'class_groups': classGroups,
      'fair_draw_enabled': fairDrawEnabled,
      'non_repeat_enabled': nonRepeatEnabled,
      'rollcall_result_font_size': rollcallResultFontSize,
      'lottery_result_font_size': lotteryResultFontSize,
      'rollcall_animation_mode': rollcallAnimationMode.toJsonValue(),
      'lottery_animation_mode': lotteryAnimationMode.toJsonValue(),
    };
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      themeMode: json['theme_mode'] ?? 'system',
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
      fairDrawEnabled: json['fair_draw_enabled'] as bool? ?? true,
      nonRepeatEnabled: json['non_repeat_enabled'] as bool? ?? true,
      rollcallResultFontSize:
          (json['rollcall_result_font_size'] as num?)?.toDouble() ?? 48,
      lotteryResultFontSize:
          (json['lottery_result_font_size'] as num?)?.toDouble() ?? 48,
      rollcallAnimationMode:
          AnimationModeX.fromJsonValue(json['rollcall_animation_mode']),
      lotteryAnimationMode:
          AnimationModeX.fromJsonValue(json['lottery_animation_mode']),
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
      fairDrawEnabled: true,
      nonRepeatEnabled: true,
      rollcallResultFontSize: 48,
      lotteryResultFontSize: 48,
      rollcallAnimationMode: AnimationMode.auto,
      lotteryAnimationMode: AnimationMode.auto,
    );
  }
}
