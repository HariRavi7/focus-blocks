import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart';

import '../format.dart';
import '../live.dart';
import '../pomodoro.dart';

/// The Mac menu bar item. The native side (macos/Runner/MainFlutterWindow.swift)
/// draws it; this sends the title and menu, and receives clicks.
class MenuBarService {
  MenuBarService._();
  static final instance = MenuBarService._();

  static const _channel = MethodChannel('focus_blocks/menu_bar');
  final _actions = StreamController<String>.broadcast();
  String? _sig;
  bool _listening = false;

  bool get supported => !kIsWeb && Platform.isMacOS;

  /// Menu items clicked ("done", "extend", "wrap", "pomo_start",
  /// "pomo_pause", "pomo_skip", "pomo_stop").
  Stream<String> get actions => _actions.stream;

  void init() {
    if (!supported || _listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'action' && call.arguments is String) _actions.add(call.arguments as String);
      return null;
    });
  }

  /// While a Pomodoro is on, the title shows its countdown instead of the
  /// block; the menu leads with the timer controls.
  void update(LiveStatus s, {PomodoroTimer? pomodoro, DateTime? now}) {
    if (!supported) return;
    final title = pomodoro == null ? s.menuBarTitle : pomodoroMenuTitle(pomodoro, now ?? DateTime.now());
    final payload = <String, Object?>{'title': title, 'items': menuItems(s, pomodoro)};
    final sig = jsonEncode(payload);
    if (sig == _sig) return;
    _sig = sig;
    _channel.invokeMethod<void>('update', payload).catchError((Object e) {
      // Native side not installed yet (setup script not run): ignore.
      debugPrint('Menu bar unavailable: $e');
    });
  }

  static Map<String, Object?> _info(String label) => {'label': label, 'enabled': false};
  static Map<String, Object?> _action(String id, String label) => {'id': id, 'label': label};
  static const Map<String, Object?> _separator = {'separator': true};

  /// The menu. Kept free of the seconds countdown, so it only changes when
  /// something in it does (the title carries the countdown).
  static List<Map<String, Object?>> menuItems(LiveStatus s, PomodoroTimer? p) {
    final items = <Map<String, Object?>>[];
    if (p != null) {
      final subject = pomodoroSubject(p);
      final round = p.phase.isBreak ? p.phase.label : 'Focus · round ${p.round}';
      items.add(_info(subject.isEmpty ? round : '$round · $subject'));
      if (p.running) {
        items.add(_info('Ends at ${formatTime(p.endsAt!.hour * 60 + p.endsAt!.minute)}'));
        items.add(_action('pomo_pause', 'Pause'));
      } else {
        items.add(_action('pomo_start', p.started ? 'Resume' : (p.phase.isBreak ? 'Start break' : 'Start focus')));
      }
      items.add(_action('pomo_skip', p.phase.isBreak ? 'Skip break' : 'Skip to break'));
      items.add(_action('pomo_stop', 'Stop Pomodoro'));
      items.add(_separator);
    }
    switch (s.kind) {
      case LiveKind.running:
        items.add(_info('${s.blockName} · until ${formatTime(s.end)}'));
        items.add(_info('${s.minutesLeft} min left'));
        if (s.taskTitle != null) {
          items.add(_separator);
          items.add(_info('In progress: ${s.taskTitle}'));
          items.add(_action('done', 'Mark “${s.taskTitle}” done'));
        }
        items.add(_action('extend', 'Extend by 15 min'));
        if (p == null) items.add(_action('pomo_start', 'Start a Pomodoro'));
      case LiveKind.ended:
        items.add(_info("${s.blockName} · time's up"));
        items.add(_action('wrap', 'Wrap up…'));
      case LiveKind.upNext:
        items.add(_info('Up next: ${s.nextName} at ${formatTime(s.nextStart ?? 0)}'));
        if (p == null) items.add(_action('pomo_start', 'Start a Pomodoro'));
      case LiveKind.idle:
        items.add(_info("That's the day. Nothing else planned."));
        if (p == null) items.add(_action('pomo_start', 'Start a Pomodoro'));
    }
    if (s.kind != LiveKind.upNext && s.nextName != null) {
      items.add(_separator);
      items.add(_info(s.nextLine));
    }
    items.add(_separator);
    items.add(_action('open', 'Open Focus Blocks'));
    items.add(_action('quit', 'Quit Focus Blocks'));
    return items;
  }
}
