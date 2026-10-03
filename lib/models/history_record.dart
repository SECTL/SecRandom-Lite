class HistoryRecord {
  final int id;
  final String? uid;
  final String name;
  final int drawMethod;
  final String drawTime;
  final int drawPeopleNumbers;
  final String drawGroup;
  final String drawGender;
  final String className;

  HistoryRecord({
    required this.id,
    this.uid,
    required this.name,
    required this.drawMethod,
    required this.drawTime,
    required this.drawPeopleNumbers,
    required this.drawGroup,
    required this.drawGender,
    required this.className,
  });

  HistoryRecord copyWithUid(String value) {
    return HistoryRecord(
      id: id,
      uid: value,
      name: name,
      drawMethod: drawMethod,
      drawTime: drawTime,
      drawPeopleNumbers: drawPeopleNumbers,
      drawGroup: drawGroup,
      drawGender: drawGender,
      className: className,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (uid != null) 'uid': uid,
      'name': name,
      'draw_method': drawMethod,
      'draw_time': drawTime,
      'draw_people_numbers': drawPeopleNumbers,
      'draw_group': drawGroup,
      'draw_gender': drawGender,
      // 本地按班级分文件存储，className 是文件里的分组键；
      // 云端历史是扁平分片，必须显式带上，否则拉回后全部落到默认班级。
      'class_name': className,
    };
  }

  factory HistoryRecord.fromJson(Map<String, dynamic> json, {String? className}) {
    return HistoryRecord(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      uid: json['uid'] as String?,
      name: json['name'] ?? '',
      drawMethod: json['draw_method'] is int ? json['draw_method'] : int.tryParse(json['draw_method'].toString()) ?? 1,
      drawTime: json['draw_time'] ?? '',
      drawPeopleNumbers: json['draw_people_numbers'] is int ? json['draw_people_numbers'] : int.tryParse(json['draw_people_numbers'].toString()) ?? 1,
      drawGroup: json['draw_group'] ?? '未知',
      drawGender: json['draw_gender'] ?? '未知',
      className: className ?? json['class_name'] ?? '1',
    );
  }
}
