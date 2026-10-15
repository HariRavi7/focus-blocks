import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:focus_blocks/format.dart';
import 'package:focus_blocks/models.dart';
import 'package:focus_blocks/schedule_engine.dart';

// 9:00–10:00 Study, 10:00–10:30 free, 10:30–11:40 Work.
const study = TemplateBlock(id: 'a', name: 'Study', start: 540, end: 600);
const free = TemplateBlock(id: 'f', name: 'Free time', start: 600, end: 630, kind: BlockKind.free);
const work = TemplateBlock(id: 'b', name: 'Work', start: 630, end: 700);
const template = DayTemplate(id: 't', name: 'Weekday', weekdays: [1, 2, 3, 4, 5], blocks: [work, study, free]);

DayRecord record([Map<String, BlockDayState> blocks = const {}]) =>
    DayRecord(date: '2026-10-15', templateId: 't', blocks: blocks);

PlannedBlock byId(List<PlannedBlock> l, String id) => l.firstWhere((b) => b.id == id);

void main() {
  group('layoutDay', () {
    test('keeps template times when nothing changed', () {
      final l = layoutDay(template, record());
      expect(l.map((b) => b.id).toList(), ['a', 'f', 'b']);
      expect([byId(l, 'a').start, byId(l, 'a').end], [540, 600]);
      expect([byId(l, 'b').start, byId(l, 'b').end], [630, 700]);
    });

    test('an extension eats free time first', () {
      final l = layoutDay(template, record({'a': const BlockDayState(extendMinutes: 15)}));
      expect(byId(l, 'a').end, 615);
      expect(byId(l, 'f').minutes, 15);
      expect(byId(l, 'f').usedByExtension, 15);
      expect([byId(l, 'b').start, byId(l, 'b').end], [630, 700]);
    });

    test('what free time cannot cover shifts later blocks', () {
      final l = layoutDay(template, record({'a': const BlockDayState(extendMinutes: 45)}));
      expect(byId(l, 'a').end, 645);
      expect(byId(l, 'f').minutes, 0);
      expect([byId(l, 'b').start, byId(l, 'b').end], [645, 715]);
    });

    test('anything past midnight is trimmed', () {
      const night = DayTemplate(id: 'n', name: 'Night', weekdays: [1], blocks: [
        TemplateBlock(id: 'x', name: 'Late', start: 1380, end: 1430),
      ]);
      final l = layoutDay(night, record({'x': const BlockDayState(extendMinutes: 30)}));
      expect(l.single.end, 1440);
    });
  });

  group('snapshot', () {
    test('a running block is current', () {
      final s = snapshot(template, record(), 550);
      expect(s.phase, Phase.running);
      expect(s.current?.id, 'a');
      expect(s.next?.id, 'b');
    });

    test('an unreviewed block that just ended waits for a decision', () {
      final s = snapshot(template, record(), 605);
      expect(s.phase, Phase.ended);
      expect(s.current?.id, 'a');
    });

    test('a running block wins over an older unreviewed one', () {
      final s = snapshot(template, record(), 640);
      expect(s.phase, Phase.running);
      expect(s.current?.id, 'b');
    });

    test('before the first block shows up next', () {
      final s = snapshot(template, record(), 500);
      expect(s.phase, Phase.upNext);
      expect(s.next?.id, 'a');
    });

    test('unreviewed blocks stop prompting after two hours', () {
      final s = snapshot(template, record({'a': const BlockDayState(result: BlockResult.done)}), 905);
      expect(s.phase, Phase.dayDone);
    });

    test('no template means an empty day', () {
      expect(snapshot(null, const DayRecord(date: '2026-10-18'), 600).phase, Phase.empty);
    });
  });

  group('tasks', () {
    test('slots run back to back from the block start', () {
      final r = record({
        'a': const BlockDayState(tasks: [
          TaskItem(id: '1', title: 'Read', minutes: 15, done: true),
          TaskItem(id: '2', title: 'Lab', minutes: 20),
        ]),
      });
      final a = byId(layoutDay(template, r), 'a');
      final slots = taskSlots(a);
      expect([slots[0].start, slots[0].end, slots[1].start, slots[1].end], [540, 555, 555, 575]);
      expect(currentTaskSlot(a)?.task.id, '2');
    });
  });

  group('previewExtend', () {
    test('fits in free time', () {
      final p = previewExtend(template, record(), 'a', 15);
      expect([p.fromFree, p.shiftsLater, p.newEnd], [15, 0, 615]);
      expect(p.describe, 'Taken from free time');
    });

    test('spills over', () {
      final p = previewExtend(template, record(), 'a', 45);
      expect([p.fromFree, p.shiftsLater, p.newEnd], [30, 15, 645]);
    });
  });

  group('streaks', () {
    DayRecord day(String date, BlockResult r) =>
        DayRecord(date: date, templateId: 't', blocks: {'a': BlockDayState(result: r)});

    test('counts back from today and ignores an unfinished today', () {
      final days = {
        '2026-10-13': day('2026-10-13', BlockResult.done),
        '2026-10-14': day('2026-10-14', BlockResult.partly),
      };
      expect(currentStreak(days, DateTime(2026, 10, 15), dateKey), 2);
      days['2026-10-15'] = day('2026-10-15', BlockResult.done);
      expect(currentStreak(days, DateTime(2026, 10, 15), dateKey), 3);
    });

    test('a skipped or missed day breaks it', () {
      final days = {
        '2026-10-12': day('2026-10-12', BlockResult.done),
        '2026-10-13': day('2026-10-13', BlockResult.skipped),
        '2026-10-14': day('2026-10-14', BlockResult.done),
      };
      expect(currentStreak(days, DateTime(2026, 10, 15), dateKey), 1);
      expect(longestStreak(days), 1);
    });
  });

  group('template helpers', () {
    test('fillGaps adds free time between focus blocks', () {
      var n = 0;
      final out = fillGaps([work, study], () => 'g${n++}');
      expect(out.length, 3);
      expect(out[1].isFree, isTrue);
      expect([out[1].start, out[1].end], [600, 630]);
    });

    test('findOverlap', () {
      expect(findOverlap([study, work], 590, 620)?.id, 'a');
      expect(findOverlap([study, work], 600, 630), isNull);
      expect(findOverlap([study], 550, 560, exceptId: 'a'), isNull);
    });
  });

  test('AppData survives a JSON round trip', () {
    final data = AppData(
      onboarded: true,
      templates: const [template],
      days: {
        '2026-10-15': record({
          'a': const BlockDayState(
            extendMinutes: 10,
            tasks: [TaskItem(id: '1', title: 'Read', minutes: 25)],
            result: BlockResult.skipped,
            skipReason: 'Plans changed',
          ),
        }),
      },
      carryOver: const {
        'a': [TaskItem(id: '2', title: 'Lab')],
      },
    );
    final back = AppData.fromJson(jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>);
    expect(back.onboarded, isTrue);
    expect(back.templates.single.blocks.length, 3);
    final s = back.days['2026-10-15']!.stateFor('a');
    expect([s.extendMinutes, s.tasks.single.minutes, s.result, s.skipReason], [10, 25, BlockResult.skipped, 'Plans changed']);
    expect(back.carryOver['a']!.single.minutes, 15);
  });

  test('formatting', () {
    expect(formatTime(0), '12:00 AM');
    expect(formatTime(1320), '10:00 PM');
    expect(formatDuration(90), '1 h 30 min');
    expect(formatWeekdays([1, 2, 3, 4, 5]), 'Mon–Fri');
    expect(formatWeekdays([6, 7]), 'Sat & Sun');
  });
}
