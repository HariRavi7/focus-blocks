/// Pomodoro timer: settings, the running timer and the log of focus
/// sessions. Pure Dart, so it can be unit tested.
///
/// The timer is stored as an end time rather than a ticking counter, so it
/// keeps the right time while the app is closed or the Mac is asleep.
///
/// Every finished or stopped focus session is kept in a flat log with plain
/// fields (local ISO times, minutes, what you worked on). That keeps it easy
/// to export later, for example as daily notes in an Obsidian vault.
library;

import 'format.dart';

enum PomodoroPhase { focus, shortBreak, longBreak }

extension PomodoroPhaseText on PomodoroPhase {
  String get label => switch (this) {
        PomodoroPhase.focus => 'Focus',
        PomodoroPhase.shortBreak => 'Short break',
        PomodoroPhase.longBreak => 'Long break',
      };

  bool get isBreak => this != PomodoroPhase.focus;
}

class PomodoroSettings {
  final int focusMinutes;
  final int shortBreakMinutes;
  final int longBreakMinutes;

  /// Focus rounds before a long break.
  final int rounds;

  /// Start the break as soon as a focus round ends.
  final bool autoStartBreaks;

  /// Start the next focus round as soon as a break ends.
  final bool autoStartFocus;

  const PomodoroSettings({
    this.focusMinutes = 25,
    this.shortBreakMinutes = 5,
    this.longBreakMinutes = 15,
    this.rounds = 4,
    this.autoStartBreaks = true,
    this.autoStartFocus = false,
  });

  int minutesFor(PomodoroPhase p) => switch (p) {
        PomodoroPhase.focus => focusMinutes,
        PomodoroPhase.shortBreak => shortBreakMinutes,
        PomodoroPhase.longBreak => longBreakMinutes,
      };

  PomodoroSettings copyWith({
    int? focusMinutes,
    int? shortBreakMinutes,
    int? longBreakMinutes,
    int? rounds,
    bool? autoStartBreaks,
    bool? autoStartFocus,
  }) =>
      PomodoroSettings(
        focusMinutes: focusMinutes ?? this.focusMinutes,
        shortBreakMinutes: shortBreakMinutes ?? this.shortBreakMinutes,
        longBreakMinutes: longBreakMinutes ?? this.longBreakMinutes,
        rounds: rounds ?? this.rounds,
        autoStartBreaks: autoStartBreaks ?? this.autoStartBreaks,
        autoStartFocus: autoStartFocus ?? this.autoStartFocus,
      );

  Map<String, dynamic> toJson() => {
        'focusMinutes': focusMinutes,
        'shortBreakMinutes': shortBreakMinutes,
        'longBreakMinutes': longBreakMinutes,
        'rounds': rounds,
        'autoStartBreaks': autoStartBreaks,
        'autoStartFocus': autoStartFocus,
      };

  factory PomodoroSettings.fromJson(Map<String, dynamic> j) => PomodoroSettings(
        focusMinutes: j['focusMinutes'] as int? ?? 25,
        shortBreakMinutes: j['shortBreakMinutes'] as int? ?? 5,
        longBreakMinutes: j['longBreakMinutes'] as int? ?? 15,
        rounds: j['rounds'] as int? ?? 4,
        autoStartBreaks: j['autoStartBreaks'] as bool? ?? true,
        autoStartFocus: j['autoStartFocus'] as bool? ?? false,
      );
}

/// The timer that is running or paused right now.
class PomodoroTimer {
  final PomodoroPhase phase;

  /// Which focus round of the set this is (1-based). During a break, the
  /// round that just finished.
  final int round;

  /// Length of this phase in seconds.
  final int totalSeconds;

  /// When the phase ends. Null while paused (or not started yet).
  final DateTime? endsAt;

  /// Seconds left while paused.
  final int pausedSecondsLeft;

  /// When this phase was first started. Null until it is started.
  final DateTime? startedAt;

  /// What you're focusing on, e.g. "CCNA subnetting".
  final String label;

  /// The Focus Blocks block and task this round belongs to, if any.
  final String? blockId;
  final String? blockName;
  final String? taskId;
  final String? taskTitle;

  const PomodoroTimer({
    required this.phase,
    required this.round,
    required this.totalSeconds,
    this.endsAt,
    int? pausedSecondsLeft,
    this.startedAt,
    this.label = '',
    this.blockId,
    this.blockName,
    this.taskId,
    this.taskTitle,
  }) : pausedSecondsLeft = pausedSecondsLeft ?? totalSeconds;

  bool get running => endsAt != null;
  bool get started => startedAt != null;

  int secondsLeft(DateTime now) {
    final e = endsAt;
    if (e == null) return pausedSecondsLeft;
    final s = (e.difference(now).inMilliseconds / 1000).ceil();
    return s < 0 ? 0 : s;
  }

  int secondsDone(DateTime now) => totalSeconds - secondsLeft(now);

  /// 0 → 1 through the phase.
  double progress(DateTime now) => totalSeconds <= 0 ? 1 : (secondsDone(now) / totalSeconds).clamp(0.0, 1.0);

  bool isOver(DateTime now) => running && secondsLeft(now) <= 0;

  PomodoroTimer withLabel(String label) => PomodoroTimer(
        phase: phase,
        round: round,
        totalSeconds: totalSeconds,
        endsAt: endsAt,
        pausedSecondsLeft: pausedSecondsLeft,
        startedAt: startedAt,
        label: label.trim(),
        blockId: blockId,
        blockName: blockName,
        taskId: taskId,
        taskTitle: taskTitle,
      );

  /// A phase that hasn't started yet, resized to [seconds].
  PomodoroTimer withLength(int seconds) => _copy(totalSeconds: seconds, pausedSecondsLeft: seconds);

  PomodoroTimer _copy({
    PomodoroPhase? phase,
    int? round,
    int? totalSeconds,
    DateTime? endsAt,
    bool clearEndsAt = false,
    int? pausedSecondsLeft,
    DateTime? startedAt,
    bool clearStartedAt = false,
  }) =>
      PomodoroTimer(
        phase: phase ?? this.phase,
        round: round ?? this.round,
        totalSeconds: totalSeconds ?? this.totalSeconds,
        endsAt: clearEndsAt ? null : (endsAt ?? this.endsAt),
        pausedSecondsLeft: pausedSecondsLeft ?? this.pausedSecondsLeft,
        startedAt: clearStartedAt ? null : (startedAt ?? this.startedAt),
        label: label,
        blockId: blockId,
        blockName: blockName,
        taskId: taskId,
        taskTitle: taskTitle,
      );

  Map<String, dynamic> toJson() => {
        'phase': phase.name,
        'round': round,
        'totalSeconds': totalSeconds,
        if (endsAt != null) 'endsAt': endsAt!.toIso8601String(),
        'pausedSecondsLeft': pausedSecondsLeft,
        if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
        'label': label,
        if (blockId != null) 'blockId': blockId,
        if (blockName != null) 'blockName': blockName,
        if (taskId != null) 'taskId': taskId,
        if (taskTitle != null) 'taskTitle': taskTitle,
      };

  factory PomodoroTimer.fromJson(Map<String, dynamic> j) => PomodoroTimer(
        phase: PomodoroPhase.values.byName(j['phase'] as String? ?? 'focus'),
        round: j['round'] as int? ?? 1,
        totalSeconds: j['totalSeconds'] as int? ?? 1500,
        endsAt: j['endsAt'] == null ? null : DateTime.parse(j['endsAt'] as String),
        pausedSecondsLeft: j['pausedSecondsLeft'] as int?,
        startedAt: j['startedAt'] == null ? null : DateTime.parse(j['startedAt'] as String),
        label: j['label'] as String? ?? '',
        blockId: j['blockId'] as String?,
        blockName: j['blockName'] as String?,
        taskId: j['taskId'] as String?,
        taskTitle: j['taskTitle'] as String?,
      );
}

/// One focus round in the log.
class PomodoroSession {
  final String id;

  /// Local day it started, yyyy-mm-dd.
  final String date;
  final DateTime startedAt;
  final DateTime endedAt;

  /// Length the round was set to.
  final int plannedMinutes;

  /// Minutes actually spent focusing (pauses don't count).
  final int focusedMinutes;

  /// True when the timer ran out; false when stopped or skipped early.
  final bool completed;
  final String label;
  final String? blockId;
  final String? blockName;
  final String? taskTitle;

  const PomodoroSession({
    required this.id,
    required this.date,
    required this.startedAt,
    required this.endedAt,
    required this.plannedMinutes,
    required this.focusedMinutes,
    required this.completed,
    this.label = '',
    this.blockId,
    this.blockName,
    this.taskTitle,
  });

  /// What to call this round: the label, else the task, else the block.
  String get title {
    if (label.trim().isNotEmpty) return label.trim();
    if (taskTitle != null && taskTitle!.isNotEmpty) return taskTitle!;
    if (blockName != null && blockName!.isNotEmpty) return blockName!;
    return 'Focus';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'plannedMinutes': plannedMinutes,
        'focusedMinutes': focusedMinutes,
        'completed': completed,
        'label': label,
        if (blockId != null) 'blockId': blockId,
        if (blockName != null) 'blockName': blockName,
        if (taskTitle != null) 'taskTitle': taskTitle,
      };

  factory PomodoroSession.fromJson(Map<String, dynamic> j) => PomodoroSession(
        id: j['id'] as String,
        date: j['date'] as String,
        startedAt: DateTime.parse(j['startedAt'] as String),
        endedAt: DateTime.parse(j['endedAt'] as String),
        plannedMinutes: j['plannedMinutes'] as int? ?? 25,
        focusedMinutes: j['focusedMinutes'] as int? ?? 0,
        completed: j['completed'] as bool? ?? false,
        label: j['label'] as String? ?? '',
        blockId: j['blockId'] as String?,
        blockName: j['blockName'] as String?,
        taskTitle: j['taskTitle'] as String?,
      );
}

// ---------- Timer actions ----------

/// A fresh focus round, not started yet.
PomodoroTimer newFocus(
  PomodoroSettings s, {
  int round = 1,
  String label = '',
  String? blockId,
  String? blockName,
  String? taskId,
  String? taskTitle,
}) =>
    PomodoroTimer(
      phase: PomodoroPhase.focus,
      round: round,
      totalSeconds: s.focusMinutes * 60,
      label: label.trim(),
      blockId: blockId,
      blockName: blockName,
      taskId: taskId,
      taskTitle: taskTitle,
    );

/// Starts or resumes the timer.
PomodoroTimer startTimer(PomodoroTimer t, DateTime now) {
  if (t.running) return t;
  return t._copy(endsAt: now.add(Duration(seconds: t.pausedSecondsLeft)), startedAt: t.startedAt ?? now);
}

PomodoroTimer pauseTimer(PomodoroTimer t, DateTime now) {
  if (!t.running) return t;
  return t._copy(clearEndsAt: true, pausedSecondsLeft: t.secondsLeft(now));
}

/// The phase that follows [t]. Starts running from [at] when the settings
/// say so; otherwise waits for Start.
PomodoroTimer nextPhase(PomodoroTimer t, PomodoroSettings s, DateTime at) {
  final PomodoroPhase phase;
  final int round;
  if (t.phase == PomodoroPhase.focus) {
    phase = t.round >= s.rounds ? PomodoroPhase.longBreak : PomodoroPhase.shortBreak;
    round = t.round;
  } else {
    phase = PomodoroPhase.focus;
    round = t.phase == PomodoroPhase.longBreak ? 1 : t.round + 1;
  }
  final total = s.minutesFor(phase) * 60;
  final auto = phase.isBreak ? s.autoStartBreaks : s.autoStartFocus;
  final next = t._copy(
    phase: phase,
    round: round,
    totalSeconds: total,
    clearEndsAt: true,
    pausedSecondsLeft: total,
    clearStartedAt: true,
  );
  return auto ? startTimer(next, at) : next;
}

/// The log entry for a focus round that ended at [at]. Null for breaks, and
/// for rounds stopped before a full minute of focus.
PomodoroSession? sessionFor(PomodoroTimer t, DateTime at, {required bool completed, required String id}) {
  if (t.phase != PomodoroPhase.focus || t.startedAt == null) return null;
  final focusedSeconds = completed ? t.totalSeconds : t.secondsDone(at);
  final minutes = (focusedSeconds / 60).round();
  if (minutes < 1) return null;
  final start = t.startedAt!;
  return PomodoroSession(
    id: id,
    date: dateKey(start),
    startedAt: start,
    endedAt: at,
    plannedMinutes: (t.totalSeconds / 60).round(),
    focusedMinutes: minutes,
    completed: completed,
    label: t.label,
    blockId: t.blockId,
    blockName: t.blockName,
    taskTitle: t.taskTitle,
  );
}

class PomodoroAdvance {
  final PomodoroTimer timer;
  final List<PomodoroSession> sessions;

  /// The phases that ran out, in order.
  final List<PomodoroPhase> ended;
  const PomodoroAdvance(this.timer, this.sessions, this.ended);
}

/// Moves a running timer past every phase that has run out by [now]. Each
/// next phase starts from the moment the last one ended, so a Mac that slept
/// through a break catches up correctly.
PomodoroAdvance advanceTimer(PomodoroTimer t, PomodoroSettings s, DateTime now, String Function() newId) {
  var cur = t;
  final sessions = <PomodoroSession>[];
  final ended = <PomodoroPhase>[];
  for (var i = 0; i < 64 && cur.isOver(now); i++) {
    final at = cur.endsAt!;
    final session = sessionFor(cur, at, completed: true, id: newId());
    if (session != null) sessions.add(session);
    ended.add(cur.phase);
    cur = nextPhase(cur, s, at);
  }
  return PomodoroAdvance(cur, sessions, ended);
}

// ---------- Display ----------

/// 1500 → "25:00", 3725 → "1:02:05".
String formatClock(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final ss = (s % 60).toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '${m.toString().padLeft(2, '0')}:$ss';
}

/// Short text for the Mac menu bar, e.g. "Focus 18:42" or "Paused 12:00".
String pomodoroMenuTitle(PomodoroTimer t, DateTime now) {
  final clock = formatClock(t.secondsLeft(now));
  if (!t.running) return t.started ? 'Paused $clock' : '${t.phase.isBreak ? 'Break' : 'Focus'} $clock';
  return '${t.phase.isBreak ? 'Break' : 'Focus'} $clock';
}

/// What the timer is for, shown under the clock.
String pomodoroSubject(PomodoroTimer t) {
  if (t.label.isNotEmpty) return t.label;
  if (t.taskTitle != null) return t.taskTitle!;
  if (t.blockName != null) return t.blockName!;
  return '';
}

/// Message for the alert when a phase runs out.
({String title, String body}) phaseEndMessage(PomodoroTimer t, PomodoroSettings s) {
  if (t.phase == PomodoroPhase.focus) {
    final long = t.round >= s.rounds;
    final mins = long ? s.longBreakMinutes : s.shortBreakMinutes;
    return (
      title: 'Focus round done',
      body: long ? 'Set of ${s.rounds} done. Take a $mins min long break.' : 'Nice work. Take a $mins min break.',
    );
  }
  return (title: 'Break over', body: 'Ready for the next ${s.focusMinutes} min focus round?');
}

// ---------- Stats ----------

class PomodoroStats {
  final int today;
  final int todayMinutes;
  final int week;
  final int weekMinutes;
  final int total;
  final int totalMinutes;
  const PomodoroStats({
    this.today = 0,
    this.todayMinutes = 0,
    this.week = 0,
    this.weekMinutes = 0,
    this.total = 0,
    this.totalMinutes = 0,
  });
}

/// Completed rounds count as pomodoros; minutes include rounds stopped early.
PomodoroStats pomodoroStats(List<PomodoroSession> log, DateTime today) {
  final todayKey = dateKey(today);
  final monday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
  final weekKeys = {for (var i = 0; i < 7; i++) dateKey(DateTime(monday.year, monday.month, monday.day + i))};
  var t = 0, tm = 0, w = 0, wm = 0, all = 0, allm = 0;
  for (final s in log) {
    final c = s.completed ? 1 : 0;
    all += c;
    allm += s.focusedMinutes;
    if (weekKeys.contains(s.date)) {
      w += c;
      wm += s.focusedMinutes;
    }
    if (s.date == todayKey) {
      t += c;
      tm += s.focusedMinutes;
    }
  }
  return PomodoroStats(today: t, todayMinutes: tm, week: w, weekMinutes: wm, total: all, totalMinutes: allm);
}
