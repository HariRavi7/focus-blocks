import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:home_widget/home_widget.dart';

import '../format.dart';
import '../live.dart';

/// Android home screen widget. The native side is FocusWidgetProvider.kt,
/// added by tool/setup_platforms.dart. Values are saved as strings.
class HomeWidgetSync {
  HomeWidgetSync._();
  static final instance = HomeWidgetSync._();

  String? _sig;
  Future<void> _queue = Future.value();

  bool get supported => !kIsWeb && Platform.isAndroid;

  void update(LiveStatus s, {required int streak, required int reviewed, required int total}) {
    if (!supported) return;
    final values = <String, String>{
      'fb_chip': switch (s.kind) {
        LiveKind.running => 'NOW',
        LiveKind.ended => "TIME'S UP",
        LiveKind.upNext => 'UP NEXT',
        LiveKind.idle => 'TODAY',
      },
      'fb_title': switch (s.kind) {
        LiveKind.running || LiveKind.ended => s.blockName ?? '',
        LiveKind.upNext => s.nextName ?? '',
        LiveKind.idle => "That's the day",
      },
      'fb_line': switch (s.kind) {
        LiveKind.running => s.taskTitle == null ? 'Finishing the block is the task.' : 'In progress: ${s.taskTitle}',
        LiveKind.ended => 'Tap to wrap up',
        LiveKind.upNext => 'Starts at ${formatTime(s.nextStart ?? 0)}',
        LiveKind.idle => total == 0 ? 'Free day' : '$reviewed of $total blocks reviewed',
      },
      'fb_progress': s.kind == LiveKind.running ? '${s.percent}' : '-1',
      'fb_footer': switch (s.kind) {
        LiveKind.running => 'Until ${formatTime(s.end)}${s.nextName == null ? '' : ' · then ${s.nextName}'}',
        LiveKind.ended => s.nextLine,
        LiveKind.upNext || LiveKind.idle => '',
      },
      'fb_streak': streak > 0 ? '$streak-day streak' : '',
    };
    final sig = values.entries.map((e) => '${e.key}=${e.value}').join('|');
    if (sig == _sig) return;
    _sig = sig;
    _queue = _queue.then((_) async {
      for (final e in values.entries) {
        await HomeWidget.saveWidgetData<String>(e.key, e.value);
      }
      await HomeWidget.updateWidget(androidName: 'FocusWidgetProvider');
    }).catchError((Object e) => debugPrint('Widget update failed: $e'));
  }
}
