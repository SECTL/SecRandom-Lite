import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:secrandom_lite/models/app_config.dart';
import 'package:secrandom_lite/models/student.dart';
import 'package:secrandom_lite/providers/app_provider.dart';
import 'package:secrandom_lite/widgets/name_display.dart';

class _FakeNameDisplayProvider extends AppProvider {
  _FakeNameDisplayProvider({required AnimationMode mode}) : _rollcallAnimationMode = mode;

  final AnimationMode _rollcallAnimationMode;

  bool _isRolling = false;
  List<Student> _currentSelection = [];
  final List<Student> _filteredStudents = [
    Student(id: 1, name: 'Alice', gender: 'F', group: '1', className: '1', exist: true),
    Student(id: 2, name: 'Bob', gender: 'M', group: '1', className: '1', exist: true),
    Student(id: 3, name: 'Carol', gender: 'F', group: '2', className: '1', exist: true),
  ];
  late Student _finalStudent = _filteredStudents.last;

  @override
  AnimationMode get rollcallAnimationMode => _rollcallAnimationMode;

  @override
  bool get isRolling => _isRolling;

  @override
  List<Student> get currentSelection => _currentSelection;

  @override
  List<Student> get filteredStudents => _filteredStudents;

  @override
  int get selectCount => 1;

  @override
  double get rollcallResultFontSize => 48;

  void setFinalStudent(Student student) {
    _finalStudent = student;
  }

  @override
  Future<void> startRollCall() async {
    _currentSelection = [];
    _isRolling = true;
    notifyListeners();

    if (_rollcallAnimationMode == AnimationMode.none) {
      await finalizeRollCall();
    }
  }

  @override
  Future<void> finalizeRollCall({int? sessionId}) async {
    _currentSelection = [_finalStudent];
    _isRolling = false;
    notifyListeners();
  }

  Future<void> finalizeRollCallWithDelay() async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    await finalizeRollCall();
  }
}

Future<void> _pumpNameDisplay(
  WidgetTester tester,
  _FakeNameDisplayProvider provider,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AppProvider>.value(
      value: provider,
      child: const MaterialApp(
        home: Scaffold(
          body: NameDisplay(),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder _studentText(String name) => find.text(name);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'manualStop and auto modes animate only while rolling and stop on finalize',
    (tester) async {
      for (final mode in [AnimationMode.manualStop, AnimationMode.auto]) {
        final provider = _FakeNameDisplayProvider(mode: mode);
        provider.setFinalStudent(provider.filteredStudents.last);

        await _pumpNameDisplay(tester, provider);
        expect(find.text('准备点名'), findsOneWidget);

        await provider.startRollCall();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(provider.isRolling, isTrue, reason: mode.name);
        expect(
          _studentText('Alice').evaluate().isNotEmpty ||
              _studentText('Bob').evaluate().isNotEmpty ||
              _studentText('Carol').evaluate().isNotEmpty,
          isTrue,
          reason: mode.name,
        );

        await provider.finalizeRollCall();
        await tester.pump();

        expect(_studentText('Carol'), findsOneWidget, reason: mode.name);

        await tester.pump(const Duration(milliseconds: 250));

        expect(_studentText('Carol'), findsOneWidget, reason: mode.name);
        expect(_studentText('Alice'), findsNothing, reason: mode.name);
        expect(_studentText('Bob'), findsNothing, reason: mode.name);

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
        );
        await tester.pump();
        provider.dispose();
      }
    },
  );

  testWidgets(
    'none mode skips rolling animation and shows final selection directly',
    (tester) async {
      final provider = _FakeNameDisplayProvider(mode: AnimationMode.none);
      provider.setFinalStudent(provider.filteredStudents[1]);

      await _pumpNameDisplay(tester, provider);

      await provider.startRollCall();
      await tester.pump();

      expect(_studentText('Bob'), findsOneWidget);
      expect(_studentText('Alice'), findsNothing);
      expect(_studentText('Carol'), findsNothing);
      expect(find.text('准备点名'), findsNothing);

      await tester.pump(const Duration(milliseconds: 250));

      expect(_studentText('Bob'), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      await tester.pump();
      provider.dispose();
    },
  );

  testWidgets('disposing during rolling cancels timer safely', (tester) async {
    final provider = _FakeNameDisplayProvider(mode: AnimationMode.manualStop);

    await _pumpNameDisplay(tester, provider);

    await provider.startRollCall();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox.shrink())));
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
    provider.dispose();
  });

  testWidgets('finalize and dispose race leaves no hanging callbacks', (tester) async {
    final provider = _FakeNameDisplayProvider(mode: AnimationMode.manualStop);
    provider.setFinalStudent(provider.filteredStudents.first);

    await _pumpNameDisplay(tester, provider);

    await provider.startRollCall();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    unawaited(provider.finalizeRollCallWithDelay());
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox.shrink())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    provider.dispose();
  });
}
