import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_state.dart';
import '../live.dart';
import 'home_widget_sync.dart';
import 'menu_bar.dart';
import 'notifications.dart';

/// Keeps the menu bar, notifications and home screen widget in step with
/// the app. Each service skips work when nothing it shows has changed, so
/// [push] is cheap to call on every clock tick.
class PlatformSync {
  PlatformSync(this.ref);
  final WidgetRef ref;
  final _subs = <StreamSubscription<String>>[];

  Future<void> start({required void Function(String action) onAction}) async {
    MenuBarService.instance.init();
    _subs.add(MenuBarService.instance.actions.listen(onAction));
    _subs.add(NotificationService.instance.actions.listen(onAction));
    await NotificationService.instance.init();
    final launch = NotificationService.instance.takeLaunchAction();
    if (launch != null) onAction(launch);
    final data = ref.read(appProvider).valueOrNull;
    if (data != null && data.reminders) await NotificationService.instance.requestPermission();
  }

  void push(TodayView? view) {
    final data = ref.read(appProvider).valueOrNull;
    if (view == null || data == null) return;
    final status = liveStatus(view.snap, view.date);
    MenuBarService.instance.update(status, pomodoro: data.pomodoro, now: view.date);
    HomeWidgetSync.instance.update(
      status,
      streak: view.streak,
      reviewed: view.snap.closedCount,
      total: view.snap.focusCount,
    );
    final n = NotificationService.instance;
    if (!n.supported) return;
    n.schedulePomodoro(pomodoroAlert(data));
    if (data.reminders) {
      n.schedule(planReminders(data, view.date));
      n.showOngoing(status);
    } else {
      n.clearAll();
    }
  }

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }
}
