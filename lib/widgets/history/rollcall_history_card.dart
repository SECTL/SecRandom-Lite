import 'package:flutter/material.dart';
import '../../models/history_record.dart';
import '../../models/student.dart';

class RollcallHistoryCard extends StatelessWidget {
  final HistoryRecord record;
  final Map<String, Student> studentMap;

  const RollcallHistoryCard({
    super.key,
    required this.record,
    required this.studentMap,
  });

  String _formatDrawTime() {
    return record.drawTime;
  }

  @override
  Widget build(BuildContext context) {
    final names = record.name.split(',').map((e) => e.trim()).toList();
    final students = names
        .map((name) => studentMap[name])
        .whereType<Student>()
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _formatDrawTime(),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: students.map((student) {
                return _buildStudentChip(context, student);
              }).toList(),
            ),
            if (record.drawGroup != '未知' || record.drawGender != '未知') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (record.drawGroup != '未知') ...[
                    Icon(Icons.group_outlined,
                        size: 14, color: Theme.of(context).textTheme.bodySmall?.color),
                    const SizedBox(width: 4),
                    Text(
                      '小组: ${record.drawGroup}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 16),
                  ],
                  if (record.drawGender != '未知') ...[
                    Icon(Icons.wc_outlined,
                        size: 14, color: Theme.of(context).textTheme.bodySmall?.color),
                    const SizedBox(width: 4),
                    Text(
                      '性别: ${record.drawGender}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStudentChip(BuildContext context, Student student) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: student.gender == '男'
                ? Colors.blue.withValues(alpha: 0.15)
                : Colors.pink.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              student.id.toString(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: student.gender == '男' ? Colors.blue : Colors.pink,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              student.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 2),
            Text(
              '性别：${student.gender} | 小组：${student.group}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}
