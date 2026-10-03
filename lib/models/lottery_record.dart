class LotteryRecord {
  final String id;
  final String? uid;
  final String poolName;
  final String prizeName;
  final String? studentName;
  final String? groupName;
  final String? gender;
  final DateTime drawTime;
  final int drawCount;
  final String? classFilter;
  final String? groupFilter;
  final String? genderFilter;

  LotteryRecord({
    required this.id,
    this.uid,
    required this.poolName,
    required this.prizeName,
    this.studentName,
    this.groupName,
    this.gender,
    required this.drawTime,
    this.drawCount = 1,
    this.classFilter,
    this.groupFilter,
    this.genderFilter,
  });

  LotteryRecord copyWithUid(String value) => LotteryRecord(
        id: id,
        uid: value,
        poolName: poolName,
        prizeName: prizeName,
        studentName: studentName,
        groupName: groupName,
        gender: gender,
        drawTime: drawTime,
        drawCount: drawCount,
        classFilter: classFilter,
        groupFilter: groupFilter,
        genderFilter: genderFilter,
      );

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (uid != null) 'uid': uid,
      'poolName': poolName,
      'prizeName': prizeName,
      'studentName': studentName,
      'groupName': groupName,
      'gender': gender,
      'drawTime': drawTime.toIso8601String(),
      'drawCount': drawCount,
      'classFilter': classFilter,
      'groupFilter': groupFilter,
      'genderFilter': genderFilter,
    };
  }

  factory LotteryRecord.fromJson(Map<String, dynamic> json) {
    return LotteryRecord(
      id: json['id'] as String,
      uid: json['uid'] as String?,
      poolName: json['poolName'] as String,
      prizeName: json['prizeName'] as String,
      studentName: json['studentName'] as String?,
      groupName: json['groupName'] as String?,
      gender: json['gender'] as String?,
      drawTime: DateTime.parse(json['drawTime'] as String),
      drawCount: json['drawCount'] as int? ?? 1,
      classFilter: json['classFilter'] as String?,
      groupFilter: json['groupFilter'] as String?,
      genderFilter: json['genderFilter'] as String?,
    );
  }

  LotteryRecord copyWith({
    String? id,
    String? uid,
    String? poolName,
    String? prizeName,
    String? studentName,
    String? groupName,
    String? gender,
    DateTime? drawTime,
    int? drawCount,
    String? classFilter,
    String? groupFilter,
    String? genderFilter,
  }) {
    return LotteryRecord(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      poolName: poolName ?? this.poolName,
      prizeName: prizeName ?? this.prizeName,
      studentName: studentName ?? this.studentName,
      groupName: groupName ?? this.groupName,
      gender: gender ?? this.gender,
      drawTime: drawTime ?? this.drawTime,
      drawCount: drawCount ?? this.drawCount,
      classFilter: classFilter ?? this.classFilter,
      groupFilter: groupFilter ?? this.groupFilter,
      genderFilter: genderFilter ?? this.genderFilter,
    );
  }
}
