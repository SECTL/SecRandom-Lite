import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:secrandom_lite/models/app_config.dart';
import 'package:secrandom_lite/providers/app_provider.dart';
import 'package:secrandom_lite/widgets/control_panel.dart';

class _FakeAppProvider extends AppProvider {
  _FakeAppProvider({required AnimationMode mode}) : _rollcallAnimationMode = mode;

  final AnimationMode _rollcallAnimationMode;
  bool _isRolling = false;
  int _selectCount = 2;
  final int _totalCount = 4;
  String? _selectedClass = '1';
  String? _selectedGroup;
  String? _selectedGender;
  final List<String> _groups = ['1', '2'];
  final Map<String, List<String>> _classGroups = {
    '1': ['1', '2'],
    '2': ['A'],
  };

  int startCalls = 0;
  int stopCalls = 0;

  @override
  bool get isRolling => _isRolling;

  @override
  AnimationMode get rollcallAnimationMode => _rollcallAnimationMode;

  @override
  int get selectCount => _selectCount;

  @override
  int get totalCount => _totalCount;

  @override
  int get remainingCount => _totalCount;

  @override
  String? get selectedClass => _selectedClass;

  @override
  String? get selectedGroup => _selectedGroup;

  @override
  String? get selectedGender => _selectedGender;

  @override
  List<String> get groups => _groups;

  @override
  List<String> getGroupsForClass(String? className) {
    return _classGroups[className] ?? const [];
  }

  @override
  void setSelectCount(int count) {
    _selectCount = count;
    notifyListeners();
  }

  @override
  void setSelectedClass(String? className) {
    _selectedClass = className;
    _selectedGroup = null;
    _selectedGender = null;
    notifyListeners();
  }

  @override
  void setSelectedGroup(String? groupName) {
    _selectedGroup = groupName;
    notifyListeners();
  }

  @override
  void setSelectedGender(String? gender) {
    _selectedGender = gender;
    notifyListeners();
  }

  @override
  Future<void> startRollCall() async {
    startCalls++;
    if (_isRolling) {
      return;
    }

    _isRolling = true;
    notifyListeners();

    if (_rollcallAnimationMode == AnimationMode.none) {
      _isRolling = false;
      notifyListeners();
    }
  }

  @override
  Future<void> stopRollCall() async {
    stopCalls++;
    if (!_isRolling) {
      return;
    }

    _isRolling = false;
    notifyListeners();
  }

  void finalizeRollingRound() {
    _isRolling = false;
    notifyListeners();
  }
}

Future<void> _pumpControlPanel(
  WidgetTester tester,
  _FakeAppProvider provider,
  ControlPanelLayoutMode layoutMode,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AppProvider>.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 640,
            child: ControlPanel(layoutMode: layoutMode),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder _startButtonFinder() => find.byKey(ControlPanel.startButtonKey);

FilledButton _startButtonWidget(WidgetTester tester) {
  return tester.widget<FilledButton>(_startButtonFinder());
}

DropdownButtonFormField<String> _dropdownField(
  WidgetTester tester,
  Key key,
) {
  return tester.widget<DropdownButtonFormField<String>>(find.byKey(key));
}

IconButton _iconButton(WidgetTester tester, Key key) {
  return tester.widget<IconButton>(find.byKey(key));
}

void _expectButtonState(
  WidgetTester tester, {
  required String label,
  required bool enabled,
}) {
  expect(find.text(label), findsOneWidget);
  expect(_startButtonWidget(tester).onPressed == null, !enabled);
}

void _expectCandidateControlsLocked(WidgetTester tester, {required bool locked}) {
  expect(
    _iconButton(tester, ControlPanel.decrementSelectCountKey).onPressed == null,
    locked,
  );
  expect(
    _iconButton(tester, ControlPanel.incrementSelectCountKey).onPressed == null,
    locked,
  );
  expect(
    _dropdownField(tester, ControlPanel.classDropdownKey).onChanged == null,
    locked,
  );
  expect(
    _dropdownField(tester, ControlPanel.groupDropdownKey).onChanged == null,
    locked,
  );
  expect(
    _dropdownField(tester, ControlPanel.genderDropdownKey).onChanged == null,
    locked,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final layouts = <String, ControlPanelLayoutMode>{
    'normal': ControlPanelLayoutMode.normal,
    'compact': ControlPanelLayoutMode.compact,
    'ultraCompact': ControlPanelLayoutMode.ultraCompact,
  };

  testWidgets(
    'manualStop mode toggles start button to stop and unlocks after stop in all layouts',
    (tester) async {
      for (final entry in layouts.entries) {
        final provider = _FakeAppProvider(mode: AnimationMode.manualStop);

        await _pumpControlPanel(tester, provider, entry.value);

        _expectButtonState(tester, label: '开始', enabled: true);
        _expectCandidateControlsLocked(tester, locked: false);

        await tester.tap(_startButtonFinder());
        await tester.pump();

        expect(provider.startCalls, 1, reason: entry.key);
        _expectButtonState(tester, label: '停止', enabled: true);
        _expectCandidateControlsLocked(tester, locked: true);

        await tester.tap(_startButtonFinder());
        await tester.pump();

        expect(provider.stopCalls, 1, reason: entry.key);
        _expectButtonState(tester, label: '开始', enabled: true);
        _expectCandidateControlsLocked(tester, locked: false);
      }
    },
  );

  testWidgets(
    'auto mode disables the button while rolling and unlocks controls after finalize in all layouts',
    (tester) async {
      for (final entry in layouts.entries) {
        final provider = _FakeAppProvider(mode: AnimationMode.auto);

        await _pumpControlPanel(tester, provider, entry.value);

        await tester.tap(_startButtonFinder());
        await tester.pump();

        expect(provider.startCalls, 1, reason: entry.key);
        _expectButtonState(tester, label: '点名中...', enabled: false);
        _expectCandidateControlsLocked(tester, locked: true);

        provider.finalizeRollingRound();
        await tester.pump();

        _expectButtonState(tester, label: '开始', enabled: true);
        _expectCandidateControlsLocked(tester, locked: false);
      }
    },
  );

  testWidgets(
    'none mode finalizes immediately without leaving controls locked in all layouts',
    (tester) async {
      for (final entry in layouts.entries) {
        final provider = _FakeAppProvider(mode: AnimationMode.none);

        await _pumpControlPanel(tester, provider, entry.value);

        await tester.tap(_startButtonFinder());
        await tester.pump();

        expect(provider.startCalls, 1, reason: entry.key);
        expect(provider.isRolling, isFalse, reason: entry.key);
        expect(provider.stopCalls, 0, reason: entry.key);
        _expectButtonState(tester, label: '开始', enabled: true);
        _expectCandidateControlsLocked(tester, locked: false);
        expect(find.text('点名中...'), findsNothing);
      }
    },
  );
}
