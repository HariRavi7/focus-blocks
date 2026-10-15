import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/painting.dart' show Color;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../format.dart';
import '../live.dart';

/// Reminders on iPhone, Android and Mac, plus the ongoing countdown
/// notification on Android.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  static const _ongoingId = 1;
  static const _reminderChannel = AndroidNotificationDetails(
    'reminders',
    'Reminders',
    channelDescription: 'Heads-up before blocks and tasks start, and when time is almost up',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
    color: Color(0xFF0E7490),
  );
  static const _reminderDetails = NotificationDetails(
    android: _reminderChannel,
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );

  final _plugin = FlutterLocalNotificationsPlugin();
  final _actions = StreamController<String>.broadcast();
  bool _ready = false;
  Future<void>? _initializing;
  AndroidScheduleMode _mode = AndroidScheduleMode.exactAllowWhileIdle;
  // Start with a value that never matches, so the first call always syncs
  // (and clears anything left over from the last run).
  String? _scheduledSig = '<startup>';
  String? _ongoingSig = '<startup>';
  String? _launchAction;
  Future<void> _queue = Future.value();

  bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  /// Buttons tapped on a notification ("done", "extend", "open").
  Stream<String> get actions => _actions.stream;

  /// The button that opened the app from a notification, if any. Read once.
  String? takeLaunchAction() {
    final a = _launchAction;
    _launchAction = null;
    return a;
  }

  Future<void> init() => _initializing ??= _init();

  Future<void> _init() async {
    if (!supported) return;
    try {
      tzdata.initializeTimeZones();
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: darwin,
          macOS: darwin,
        ),
        onDidReceiveNotificationResponse: _onResponse,
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final action = launch?.notificationResponse?.actionId;
      if (launch != null && launch.didNotificationLaunchApp && action != null && action.isNotEmpty) {
        _launchAction = action;
      }
      if (Platform.isAndroid) {
        final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        final exact = await android?.canScheduleExactNotifications() ?? false;
        if (!exact) _mode = AndroidScheduleMode.inexactAllowWhileIdle;
      }
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  void _onResponse(NotificationResponse r) {
    final a = r.actionId;
    if (a != null && a.isNotEmpty) _actions.add(a);
  }

  /// Asks the system for permission. Safe to call more than once.
  Future<bool> requestPermission() async {
    await init();
    if (!_ready) return false;
    try {
      if (Platform.isAndroid) {
        final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        final ok = await android?.requestNotificationsPermission() ?? false;
        final exact = await android?.canScheduleExactNotifications() ?? false;
        _mode = exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle;
        return ok;
      }
      if (Platform.isIOS) {
        return await _plugin
                .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      }
      if (Platform.isMacOS) {
        return await _plugin
                .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      }
    } catch (e) {
      debugPrint('Notification permission failed: $e');
    }
    return false;
  }

  /// Replaces the scheduled reminders with [list]. Does nothing when the list
  /// hasn't changed since the last call.
  void schedule(List<PlannedReminder> list) {
    final sig = list.map((r) => '${r.at.millisecondsSinceEpoch}|${r.title}|${r.body}').join(';');
    if (sig == _scheduledSig) return;
    _scheduledSig = sig;
    _queue = _queue.then((_) => _schedule(list)).catchError((Object e) => debugPrint('Scheduling failed: $e'));
  }

  Future<void> _schedule(List<PlannedReminder> list) async {
    await init();
    if (!_ready) return;
    final pending = await _plugin.pendingNotificationRequests();
    for (final p in pending) {
      if (p.id >= 100) await _plugin.cancel(id: p.id);
    }
    for (final r in list) {
      final when = tz.TZDateTime.from(r.at, tz.UTC);
      try {
        await _plugin.zonedSchedule(
          id: r.id,
          title: r.title,
          body: r.body,
          scheduledDate: when,
          notificationDetails: _reminderDetails,
          androidScheduleMode: _mode,
        );
      } on PlatformException {
        // Exact alarms not allowed: fall back to inexact for the rest.
        if (_mode == AndroidScheduleMode.inexactAllowWhileIdle) rethrow;
        _mode = AndroidScheduleMode.inexactAllowWhileIdle;
        await _plugin.zonedSchedule(
          id: r.id,
          title: r.title,
          body: r.body,
          scheduledDate: when,
          notificationDetails: _reminderDetails,
          androidScheduleMode: _mode,
        );
      }
    }
  }

  /// Android only: a silent, ongoing notification with a live countdown and
  /// progress bar for the running block, with Mark done / +15 min / Open.
  void showOngoing(LiveStatus s) {
    if (kIsWeb || !Platform.isAndroid) return;
    final running = s.kind == LiveKind.running;
    final sig = running ? '${s.blockId}|${s.blockName}|${s.taskId}|${s.taskTitle}|${s.end}|${s.percent ~/ 2}' : null;
    if (sig == _ongoingSig) return;
    _ongoingSig = sig;
    _queue = _queue.then((_) => running ? _showOngoing(s) : _cancelOngoing()).catchError(
          (Object e) => debugPrint('Ongoing notification failed: $e'),
        );
  }

  Future<void> _cancelOngoing() async {
    await init();
    if (_ready) await _plugin.cancel(id: _ongoingId);
  }

  Future<void> _showOngoing(LiveStatus s) async {
    await init();
    if (!_ready) return;
    final endMs = s.endAt.millisecondsSinceEpoch;
    final left = endMs - DateTime.now().millisecondsSinceEpoch;
    final details = AndroidNotificationDetails(
      'focus',
      'Current block',
      channelDescription: 'Shows the block you are in, with a countdown',
      importance: Importance.low,
      priority: Priority.low,
      category: AndroidNotificationCategory.progress,
      visibility: NotificationVisibility.public,
      color: const Color(0xFF0E7490),
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      silent: true,
      showWhen: true,
      when: endMs,
      usesChronometer: true,
      chronometerCountDown: true,
      showProgress: true,
      maxProgress: 100,
      progress: s.percent,
      timeoutAfter: left > 1000 ? left : 1000,
      actions: [
        if (s.taskId != null)
          const AndroidNotificationAction('done', 'Mark done', showsUserInterface: true, cancelNotification: false),
        const AndroidNotificationAction('extend', '+15 min', showsUserInterface: true, cancelNotification: false),
        const AndroidNotificationAction('open', 'Open', showsUserInterface: true, cancelNotification: false),
      ],
    );
    await _plugin.show(
      id: _ongoingId,
      title: s.taskTitle == null ? s.blockName : '${s.blockName} · ${s.taskTitle}',
      body: 'Focus until ${formatTime(s.end)}',
      notificationDetails: NotificationDetails(android: details),
    );
  }

  /// Turns everything off (reminders setting switched off).
  void clearAll() {
    if (_scheduledSig == null && _ongoingSig == null) return;
    _scheduledSig = null;
    _ongoingSig = null;
    _queue = _queue.then((_) async {
      await init();
      if (_ready) await _plugin.cancelAll();
    }).catchError((Object e) => debugPrint('Clearing notifications failed: $e'));
  }
}
