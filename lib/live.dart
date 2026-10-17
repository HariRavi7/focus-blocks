/// What the reminders, the Android countdown notification, the home screen
/// widget and the Mac menu bar show. Pure Dart, so it can be unit tested.
library;

import 'format.dart';
import 'models.dart';
import 'pomodoro.dart';
import 'schedule_engine.dart';

/// [minutes] after midnight on [day], as a local DateTime.
DateTime atMinute(DateTime day, int minutes) => DateTime(day.year, day.month, day.day, 0, minutes);

class PlannedReminder {
  final int id;
  final DateTime at;
  final String title;
  final String body;
  const PlannedReminder(this.id, this.at, this.title, this.body);
}

/// Heads-up reminders for today and tomorrow:
/// 15 minutes before each block and each later task, 15 minutes before a
/// block ends, and when its time is up. Closed blocks and done tasks are
/// skipped. Ids start at 100; lower ids are kept for live notifications.
List<PlannedReminder> planReminders(AppData data, DateTime now, {int days = 2, int max = 48}) {
  if (!data.reminders) return const [];
  final found = <({DateTime at, String title, String body})>[];
  void add(DateTime at, String title, String body) {
    if (at.isAfter(now)) found.add((at: at, title: title, body: body));
  }

  for (var offset = 0; offset < days; offset++) {
    final day = DateTime(now.year, now.month, now.day + offset);
    final record = dayRecordFor(data, day);
    final template = templateOf(data, record);
    if (template == null) continue;
    for (final b in layoutDay(template, record)) {
      if (b.isFree || b.isClosed || b.minutes <= 0) continue;
      final start = atMinute(day, b.start);
      final end = atMinute(day, b.end);
      add(start.subtract(const Duration(minutes: 15)), '${b.name} starts in 15 min', formatRange(b.start, b.end));
      if (b.minutes >= 30) {
        add(end.subtract(const Duration(minutes: 15)), '15 min left in ${b.name}', 'Focus until ${formatTime(b.end)}');
      }
      add(end, "Time's up: ${b.name}", 'You showed up. Open to wrap up or extend.');
      for (final s in taskSlots(b)) {
        if (s.task.done || s.start <= b.start || s.start >= b.end) continue;
        add(atMinute(day, s.start).subtract(const Duration(minutes: 15)), '${s.task.title} starts in 15 min',
            'Next in ${b.name} · ${formatTime(s.start)}');
      }
    }
  }
  found.sort((a, b) => a.at.compareTo(b.at));
  return [
    for (var i = 0; i < found.length && i < max; i++) PlannedReminder(100 + i, found[i].at, found[i].title, found[i].body),
  ];
}

enum LiveKind { running, ended, upNext, idle }

/// A one-line summary of right now.
class LiveStatus {
  final LiveKind kind;
  final String? blockId;
  final String? blockName;
  final String? taskId;
  final String? taskTitle;
  final int start;
  final int end;
  final int now;
  final String? nextName;
  final int? nextStart;
  final DateTime day;

  const LiveStatus({
    required this.kind,
    required this.day,
    required this.now,
    this.blockId,
    this.blockName,
    this.taskId,
    this.taskTitle,
    this.start = 0,
    this.end = 0,
    this.nextName,
    this.nextStart,
  });

  int get total => end - start;
  int get minutesLeft => end - now < 0 ? 0 : end - now;
  int get elapsed => (now - start).clamp(0, total < 0 ? 0 : total).toInt();
  int get percent => total <= 0 ? 0 : (elapsed * 100 ~/ total);
  DateTime get endAt => atMinute(day, end);

  String get nextLine => nextName == null ? '' : 'Next: $nextName · ${formatTime(nextStart ?? 0)}';

  /// Short text next to the menu bar icon.
  String get menuBarTitle => switch (kind) {
        LiveKind.running => '$blockName · ${minutesLeft}m',
        LiveKind.ended => "$blockName · time's up",
        LiveKind.upNext => '$nextName ${formatTime(nextStart ?? 0)}',
        LiveKind.idle => '',
      };

  /// Changes whenever anything shown would change (at most once a minute).
  String get signature =>
      '${kind.name}|$blockId|$blockName|$taskId|$taskTitle|$start|$end|$now|$nextName|$nextStart|${day.day}';
}

LiveStatus liveStatus(DaySnapshot snap, DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  final next = snap.next;
  final cur = snap.current;
  switch (snap.phase) {
    case Phase.running:
    case Phase.ended:
      final slot = snap.phase == Phase.running ? currentTaskSlot(cur!) : null;
      return LiveStatus(
        kind: snap.phase == Phase.running ? LiveKind.running : LiveKind.ended,
        day: day,
        now: snap.now,
        blockId: cur!.id,
        blockName: cur.name,
        taskId: slot?.task.id,
        taskTitle: slot?.task.title,
        start: cur.start,
        end: cur.end,
        nextName: next?.name,
        nextStart: next?.start,
      );
    case Phase.upNext:
      return LiveStatus(kind: LiveKind.upNext, day: day, now: snap.now, nextName: next?.name, nextStart: next?.start);
    case Phase.dayDone:
    case Phase.empty:
      return LiveStatus(kind: LiveKind.idle, day: day, now: snap.now);
  }
}

/// The alert for when the running Pomodoro phase ends, or null when the
/// timer is paused or off.
PlannedReminder? pomodoroAlert(AppData data) {
  final t = data.pomodoro;
  final at = t?.endsAt;
  if (t == null || at == null) return null;
  final m = phaseEndMessage(t, data.pomodoroSettings);
  return PlannedReminder(2, at, m.title, m.body);
}
