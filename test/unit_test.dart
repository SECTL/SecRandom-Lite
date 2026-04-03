import 'package:flutter_test/flutter_test.dart';
import 'package:secrandom_lite/models/student.dart';
import 'package:secrandom_lite/models/history_record.dart';
import 'package:secrandom_lite/services/random_service.dart';
import 'package:secrandom_lite/services/data_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Student Model Tests', () {
    test('Student should be created correctly', () {
      final student = Student(id: 1, name: 'John', gender: 'Male', group: 'Class A', exist: true);
      expect(student.id, 1);
      expect(student.name, 'John');
    });

    test('Student serialization', () {
      final student = Student(id: 1, name: 'John', gender: 'Male', group: 'Class A', exist: true);
      final json = student.toJson();
      expect(json['id'], 1);
      expect(json['name'], 'John');
      
      final student2 = Student.fromJson(json);
      expect(student2.id, student.id);
      expect(student2.name, student.name);
    });
  });

  group('RandomService Tests', () {
    final randomService = RandomService();
    final students = List.generate(10, (i) => Student(id: i, name: 'S$i', gender: 'M', group: 'C1', exist: true));

    test('pickRandomStudents should return requested count', () {
      final picked = randomService.pickRandomStudents(students, 3);
      expect(picked.length, 3);
    });

    test('pickRandomStudents should return all if count > available', () {
      final picked = randomService.pickRandomStudents(students, 20);
      expect(picked.length, 10);
    });

    test('pickRandomStudents should return unique items', () {
      final picked = randomService.pickRandomStudents(students, 5);
      final ids = picked.map((s) => s.id).toSet();
      expect(ids.length, 5);
    });
  });

  group('DataService Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      try {
        final rootPath = path.dirname(Platform.resolvedExecutable);
        final dataDir = Directory(path.join(rootPath, 'data'));
        if (await dataDir.exists()) {
          await dataDir.delete(recursive: true);
        }
      } catch (e) {
      }
      try {
        final currentDir = Directory.current;
        final dataDir = Directory(path.join(currentDir.path, 'data'));
        if (await dataDir.exists()) {
          await dataDir.delete(recursive: true);
        }
      } catch (e) {
      }
    });

    test('loadStudents returns initial data when empty', () async {
      await Future.delayed(const Duration(milliseconds: 100));
      final service = DataService();
      final students = await service.loadStudents();
      expect(students.isNotEmpty, true);
      expect(students.length, 40); // Default count
    });

    test('save and load students', () async {
      await Future.delayed(const Duration(milliseconds: 100));
      final service = DataService();
      final newStudent = Student(id: 99, name: 'New Guy', gender: 'M', group: 'C1', exist: true);
      await service.saveStudents([newStudent]);
      
      final loaded = await service.loadStudents();
      expect(loaded.length, 1);
      expect(loaded.first.name, 'New Guy');
    });

    test('save and load history', () async {
      await Future.delayed(const Duration(milliseconds: 100));
      final service = DataService();
      final record = HistoryRecord(
        id: 1,
        name: 'Record 1',
        drawMethod: 1,
        drawTime: '2023-01-01',
        drawPeopleNumbers: 1,
        drawGroup: 'All',
        drawGender: 'All',
        className: '1',
      );
      await service.saveHistory([record]);
      
      final history = await service.loadHistory();
      expect(history.length, 1);
      expect(history.first.name, 'Record 1');
    });

    test('clear history for specific class', () async {
      await Future.delayed(const Duration(milliseconds: 100));
      final service = DataService();
      final records = [
        HistoryRecord(
          id: 1,
          name: 'Class1',
          drawMethod: 1,
          drawTime: '2023-01-01',
          drawPeopleNumbers: 1,
          drawGroup: 'All',
          drawGender: 'All',
          className: '1',
        ),
        HistoryRecord(
          id: 2,
          name: 'Class2',
          drawMethod: 1,
          drawTime: '2023-01-02',
          drawPeopleNumbers: 1,
          drawGroup: 'All',
          drawGender: 'All',
          className: '2',
        ),
      ];

      await service.saveHistory(records);
      await service.clearHistoryRecords(className: '1');

      final history = await service.loadHistory();
      expect(history.length, 1);
      expect(history.first.className, '2');
      expect(history.first.name, 'Class2');
    });

    test('clear all history records', () async {
      await Future.delayed(const Duration(milliseconds: 100));
      final service = DataService();
      final records = [
        HistoryRecord(
          id: 1,
          name: 'Class1',
          drawMethod: 1,
          drawTime: '2023-01-01',
          drawPeopleNumbers: 1,
          drawGroup: 'All',
          drawGender: 'All',
          className: '1',
        ),
        HistoryRecord(
          id: 2,
          name: 'Class2',
          drawMethod: 1,
          drawTime: '2023-01-02',
          drawPeopleNumbers: 1,
          drawGroup: 'All',
          drawGender: 'All',
          className: '2',
        ),
      ];

      await service.saveHistory(records);
      await service.clearHistoryRecords();

      final history = await service.loadHistory();
      expect(history, isEmpty);
    });
  });
}
