class Student {
  final int id;

  /// 同步身份，生成后不变；旧数据按班级/本地 id/姓名派生。
  final String uid;
  final String name;
  final String gender;
  final String group;
  final String className; // New field to store class name independently
  final bool exist;

  /// 逻辑修订号（Lamport 计数器）；旧数据为 0。
  final int rev;

  /// 写入该修订的设备 ID；旧数据为空串。
  final String revBy;

  Student({
    required this.id,
    this.uid = '',
    required this.name,
    required this.gender,
    required this.group,
    this.className = '1', // Default class name
    required this.exist,
    this.rev = 0,
    this.revBy = '',
  });

  Student copyWith({
    int? id,
    String? uid,
    String? name,
    String? gender,
    String? group,
    String? className,
    bool? exist,
    int? rev,
    String? revBy,
  }) {
    return Student(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      name: name ?? this.name,
      gender: gender ?? this.gender,
      group: group ?? this.group,
      className: className ?? this.className,
      exist: exist ?? this.exist,
      rev: rev ?? this.rev,
      revBy: revBy ?? this.revBy,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (uid.isNotEmpty) 'uid': uid,
      'name': name,
      'gender': gender,
      'group': group,
      'class_name': className, // Save class name
      'exist': exist,
      if (rev > 0) 'rev': rev,
      if (rev > 0) 'rev_by': revBy,
    };
  }

  factory Student.fromJson(Map<String, dynamic> json) {
    return Student(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id'].toString()) ?? 0,
      uid: json['uid']?.toString() ?? '',
      name: json['name'] ?? '',
      gender: json['gender'] ?? '未知',
      group: json['group'] ?? '1',
      className: json['class_name'] ?? '1', // Load class name or default
      exist: json['exist'] is bool
          ? json['exist']
          : (json['exist'].toString().toLowerCase() == 'true'),
      rev: json['rev'] is int
          ? json['rev']
          : int.tryParse(json['rev']?.toString() ?? '') ?? 0,
      revBy: json['rev_by']?.toString() ?? '',
    );
  }
}
