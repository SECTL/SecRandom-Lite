import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_config.dart';
import '../providers/app_provider.dart';
import '../models/student.dart';

class NameDisplay extends StatefulWidget {
  final bool isWideScreen;

  const NameDisplay({super.key, this.isWideScreen = true});

  @override
  State<NameDisplay> createState() => _NameDisplayState();
}

class _NameDisplayState extends State<NameDisplay> {
  Timer? _timer;
  List<Student> _displayedStudents = [];
  final Random _random = Random();

  bool _shouldAnimate(AppProvider provider) {
    return provider.isRolling &&
        provider.rollcallAnimationMode != AnimationMode.none;
  }

  void _showFinalSelection(AppProvider provider) {
    _displayedStudents = List<Student>.from(provider.currentSelection);
  }

  @override
  void dispose() {
    _stopRollingAnimation();
    super.dispose();
  }

  void _startRollingAnimation(AppProvider provider) {
    if (_timer != null && _timer!.isActive) return;

    _timer = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      if (!mounted) {
        if (identical(_timer, timer)) {
          _stopRollingAnimation();
        } else {
          timer.cancel();
        }
        return;
      }

      if (!_shouldAnimate(provider)) {
        if (identical(_timer, timer)) {
          _stopRollingAnimation();
        } else {
          timer.cancel();
        }

        setState(() {
          _showFinalSelection(provider);
        });
        return;
      }

      final filtered = provider.filteredStudents;
      if (filtered.isEmpty) return;

      setState(() {
        _displayedStudents = List.generate(
          provider.selectCount,
          (_) => filtered[_random.nextInt(filtered.length)]
        );
      });
    });
  }

  void _stopRollingAnimation() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);
    final double resultFontSize = appProvider.rollcallResultFontSize;

    if (_shouldAnimate(appProvider)) {
      _startRollingAnimation(appProvider);
    } else {
      _stopRollingAnimation();
      _showFinalSelection(appProvider);
    }

    if (widget.isWideScreen) {
      return Padding(
        padding: const EdgeInsets.all(32.0),
        child: Center(
          child: _displayedStudents.isEmpty
              ? SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.touch_app, size: 64, color: Theme.of(context).disabledColor),
                      const SizedBox(height: 16),
                      Text(
                        '准备点名',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Theme.of(context).disabledColor,
                        ),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 16.0,
                    runSpacing: 16.0,
                    children: _displayedStudents.map((student) {
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (Widget child, Animation<double> animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.0, 0.2),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: Padding(
                          key: ValueKey<String>("${student.id}-${student.name}"),
                          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                          child: Text(
                            student.name,
                            style: TextStyle(
                              fontSize: resultFontSize,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).textTheme.bodyLarge?.color,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
        ),
      );
    } else {
      return Center(
        child: _displayedStudents.isEmpty
            ? SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.touch_app, size: 64, color: Theme.of(context).disabledColor),
                    const SizedBox(height: 16),
                    Text(
                      '准备点名',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Theme.of(context).disabledColor,
                      ),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                child: Center(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 16.0,
                    runSpacing: 16.0,
                    children: _displayedStudents.map((student) {
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (Widget child, Animation<double> animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.0, 0.2),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: Padding(
                          key: ValueKey<String>("${student.id}-${student.name}"),
                          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                          child: Text(
                            student.name,
                            style: TextStyle(
                              fontSize: resultFontSize,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).textTheme.bodyLarge?.color,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
      );
    }
  }
}
