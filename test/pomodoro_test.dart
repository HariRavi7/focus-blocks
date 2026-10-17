import 'package:flutter_test/flutter_test.dart';
import 'package:focus_blocks/live.dart';
import 'package:focus_blocks/models.dart';
import 'package:focus_blocks/platform/menu_bar.dart';
import 'package:focus_blocks/pomodoro.dart';

const s = PomodoroSettings(); // 25 / 5 / 15, 4 rounds, breaks auto-start
final t0 = DateTime(2026, 10, 15, 9, 0);

var _seq = 0;
String id() => 'p${_seq++}';

void main() {
  test('start, pause and resume keep the right time', () {
    var t = startTimer(newFocus(s, label: 'CCNA subnetting'), t0);
    expect(t.running, isTrue);
    expect(t.secondsLeft(t0), 1500);
    expect(t.secondsLeft(t0.add(const Duration(minutes: 10))), 900);

    t = pauseTimer(t, t0.add(const Duration(minutes: 10)));
    expect(t.running, isFalse);
    // Time away while paused doesn't count.
    expect(t.secondsLeft(t0.add(const Duration(hours: 2))), 900);

    final back = t0.add(const Duration(minutes: 30));
    t = startTimer(t, back);
    expect(t.endsAt, back.add(const Duration(minutes: 15)));
    expect(t.startedAt, t0);
  });

  test('a finished focus round is logged and the break starts on its own', () {
    final t = startTimer(newFocus(s, label: 'Labs', blockId: 'a', blockName: 'Study'), t0);
    final a = advanceTimer(t, s, t0.add(const Duration(minutes: 26)), id);
    expect(a.ended, [PomodoroPhase.focus]);
    expect(a.sessions.single.completed, isTrue);
    expect(a.sessions.single.focusedMinutes, 25);
    expect(a.sessions.single.date, '2026-10-15');
    expect(a.sessions.single.blockName, 'Study');
    expect(a.timer.phase, PomodoroPhase.shortBreak);
    // The break counts from when focus ended, not from when we noticed.
    expect(a.timer.endsAt, t0.add(const Duration(minutes: 30)));
  });

  test('every 4th break is long, then the set starts over', () {
    var t = newFocus(s, round: 4);
    t = nextPhase(t, s, t0);
    expect(t.phase, PomodoroPhase.longBreak);
    expect(t.totalSeconds, 15 * 60);
    t = nextPhase(t, s, t0);
    expect(t.phase, PomodoroPhase.focus);
    expect(t.round, 1);
    // Focus doesn't auto-start by default.
    expect(t.running, isFalse);
  });

  test('a Mac that slept through focus and the break catches up', () {
    const auto = PomodoroSettings(autoStartFocus: true);
    final t = startTimer(newFocus(auto), t0);
    final a = advanceTimer(t, auto, t0.add(const Duration(minutes: 40)), id);
    expect(a.ended, [PomodoroPhase.focus, PomodoroPhase.shortBreak]);
    expect(a.timer.phase, PomodoroPhase.focus);
    expect(a.timer.round, 2);
    expect(a.timer.endsAt, t0.add(const Duration(minutes: 55)));
  });

  test('stopping early logs the minutes put in, under a minute logs nothing', () {
    final t = startTimer(newFocus(s), t0);
    final early = sessionFor(t, t0.add(const Duration(minutes: 12)), completed: false, id: 'x');
    expect(early!.completed, isFalse);
    expect(early.focusedMinutes, 12);
    expect(sessionFor(t, t0.add(const Duration(seconds: 20)), completed: false, id: 'y'), isNull);
    expect(sessionFor(newFocus(s), t0, completed: false, id: 'z'), isNull);
  });

  test('saves and loads with the rest of the data', () {
    final t = startTimer(newFocus(s, label: 'Notes', taskId: 't1', taskTitle: 'Read ch. 3'), t0);
    final session = sessionFor(t, t0.add(const Duration(minutes: 25)), completed: true, id: 'p1')!;
    final data = AppData(
      pomodoroSettings: const PomodoroSettings(focusMinutes: 50, rounds: 3),
      pomodoro: t,
      pomodoros: [session],
    );
    final back = AppData.fromJson(data.toJson());
    expect(back.pomodoroSettings.focusMinutes, 50);
    expect(back.pomodoroSettings.rounds, 3);
    expect(back.pomodoro!.endsAt, t.endsAt);
    expect(back.pomodoro!.taskTitle, 'Read ch. 3');
    expect(back.pomodoros.single.title, 'Notes');
    expect(back.pomodoros.single.startedAt, t0);
    // Old files without Pomodoro data still load.
    expect(AppData.fromJson(const {'onboarded': true}).pomodoro, isNull);
    expect(data.copyWith(clearPomodoro: true).pomodoro, isNull);
  });

  test('stats count completed rounds and all focused minutes', () {
    PomodoroSession p(String date, int minutes, bool done) => PomodoroSession(
          id: '$date-$minutes',
          date: date,
          startedAt: DateTime.parse('${date}T09:00:00'),
          endedAt: DateTime.parse('${date}T09:25:00'),
          plannedMinutes: 25,
          focusedMinutes: minutes,
          completed: done,
        );
    final log = [p('2026-10-15', 25, true), p('2026-10-15', 10, false), p('2026-10-12', 25, true), p('2026-10-01', 25, true)];
    final st = pomodoroStats(log, DateTime(2026, 10, 15, 18));
    expect(st.today, 1);
    expect(st.todayMinutes, 35);
    expect(st.week, 2);
    expect(st.weekMinutes, 60);
    expect(st.total, 3);
  });

  test('menu bar shows the countdown and timer controls', () {
    final t = startTimer(newFocus(s, label: 'Subnetting'), t0);
    final now = t0.add(const Duration(minutes: 6, seconds: 18));
    expect(pomodoroMenuTitle(t, now), 'Focus 18:42');
    expect(pomodoroMenuTitle(pauseTimer(t, now), now), 'Paused 18:42');
    expect(formatClock(3725), '1:02:05');

    final idle = LiveStatus(kind: LiveKind.idle, day: t0, now: 540);
    final items = MenuBarService.menuItems(idle, t);
    final ids = items.map((i) => i['id']).whereType<String>().toList();
    expect(items.first['label'], 'Focus · round 1 · Subnetting');
    expect(ids, ['pomo_pause', 'pomo_skip', 'pomo_stop', 'open', 'quit']);
    expect(MenuBarService.menuItems(idle, null).map((i) => i['id']), contains('pomo_start'));
  });

  test('alert at the end of the running phase only', () {
    final t = startTimer(newFocus(s), t0);
    final r = pomodoroAlert(AppData(pomodoro: t))!;
    expect(r.at, t0.add(const Duration(minutes: 25)));
    expect(r.title, 'Focus round done');
    expect(pomodoroAlert(AppData(pomodoro: pauseTimer(t, t0))), isNull);
    expect(pomodoroAlert(const AppData()), isNull);
  });
}
