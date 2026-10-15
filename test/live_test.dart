import 'package:flutter_test/flutter_test.dart';
import 'package:focus_blocks/live.dart';
import 'package:focus_blocks/models.dart';
import 'package:focus_blocks/schedule_engine.dart';

// Thursday 15 Oct 2026. Study 9:00–10:00 with two tasks, free, Work 10:30–11:40.
const study = TemplateBlock(id: 'a', name: 'Study', start: 540, end: 600);
const free = TemplateBlock(id: 'f', name: 'Free time', start: 600, end: 630, kind: BlockKind.free);
const work = TemplateBlock(id: 'b', name: 'Work', start: 630, end: 700);
const template = DayTemplate(id: 't', name: 'Weekday', weekdays: [1, 2, 3, 4, 5], blocks: [study, free, work]);

AppData data({bool reminders = true, Map<String, BlockDayState> today = const {}}) => AppData(
      onboarded: true,
      reminders: reminders,
      templates: const [template],
      days: {'2026-10-15': DayRecord(date: '2026-10-15', templateId: 't', blocks: today)},
    );

const tasks = BlockDayState(tasks: [
  TaskItem(id: '1', title: 'Read', minutes: 20),
  TaskItem(id: '2', title: 'Lab', minutes: 30),
]);

void main() {
  group('planReminders', () {
    test('heads-up, 15 min left, time is up and later tasks', () {
      final r = planReminders(data(today: {'a': tasks}), DateTime(2026, 10, 15, 8, 0), days: 1);
      final titles = r.map((x) => '${x.at.hour}:${x.at.minute.toString().padLeft(2, '0')} ${x.title}').toList();
      expect(titles, [
        '8:45 Study starts in 15 min',
        '9:05 Lab starts in 15 min',
        '9:45 15 min left in Study',
        "10:00 Time's up: Study",
        '10:15 Work starts in 15 min',
        '11:25 15 min left in Work',
        "11:40 Time's up: Work",
      ]);
      expect(r.first.id, 100);
    });

    test('skips what has passed and closed blocks', () {
      final r = planReminders(
        data(today: {'a': const BlockDayState(result: BlockResult.done)}),
        DateTime(2026, 10, 15, 10, 20),
        days: 1,
      );
      expect(r.map((x) => x.title), ['15 min left in Work', "Time's up: Work"]);
    });

    test('includes tomorrow, and nothing when reminders are off', () {
      expect(planReminders(data(), DateTime(2026, 10, 15, 23, 0)).first.at, DateTime(2026, 10, 16, 8, 45));
      expect(planReminders(data(reminders: false), DateTime(2026, 10, 15, 8, 0)), isEmpty);
    });
  });

  group('liveStatus', () {
    test('running block with a task', () {
      final d = data(today: {'a': tasks});
      final snap = snapshot(template, d.days['2026-10-15']!, 560);
      final s = liveStatus(snap, DateTime(2026, 10, 15, 9, 20));
      expect(s.kind, LiveKind.running);
      expect(s.taskTitle, 'Read');
      expect(s.minutesLeft, 40);
      expect(s.percent, 33);
      expect(s.menuBarTitle, 'Study · 40m');
      expect(s.endAt, DateTime(2026, 10, 15, 10, 0));
      expect(s.nextName, 'Work');
    });

    test('between blocks shows what is next', () {
      final d = data(today: {'a': const BlockDayState(result: BlockResult.done)});
      final s = liveStatus(snapshot(template, d.days['2026-10-15']!, 610), DateTime(2026, 10, 15, 10, 10));
      expect(s.kind, LiveKind.upNext);
      expect(s.menuBarTitle, 'Work 10:30 AM');
    });
  });
}
