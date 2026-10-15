/// Progress numbers, computed from saved days. Pure Dart.
library;

import 'format.dart';
import 'models.dart';
import 'schedule_engine.dart';

class DayBar {
  final DateTime day;
  final int good; // blocks done or partly
  final int total; // focus blocks planned
  const DayBar(this.day, this.good, this.total);
}

class Stats {
  final int currentStreak;
  final int longestStreak;
  final int done;
  final int partly;
  final int missed;
  final int skipped;
  final int focusMinutes;
  final List<MapEntry<String, int>> minutesByName; // biggest first
  final List<MapEntry<String, int>> skipReasons; // most common first
  final List<DayBar> week; // Monday to Sunday of this week

  const Stats({
    required this.currentStreak,
    required this.longestStreak,
    required this.done,
    required this.partly,
    required this.missed,
    required this.skipped,
    required this.focusMinutes,
    required this.minutesByName,
    required this.skipReasons,
    required this.week,
  });
}

DayTemplate? _template(AppData data, String? id) {
  if (id == null) return null;
  for (final t in data.templates) {
    if (t.id == id) return t;
  }
  return null;
}

Stats computeStats(AppData data, DateTime today) {
  var done = 0, partly = 0, missed = 0, skipped = 0, focusMinutes = 0;
  final byName = <String, int>{};
  final reasons = <String, int>{};

  for (final record in data.days.values) {
    final t = _template(data, record.templateId);
    final planned = t == null ? const <PlannedBlock>[] : layoutDay(t, record);
    final minutesOf = {for (final p in planned) p.id: p.minutes};
    final nameOf = {for (final p in planned) p.id: p.name};
    record.blocks.forEach((id, s) {
      switch (s.result) {
        case BlockResult.done:
        case BlockResult.partly:
          if (s.result == BlockResult.done) {
            done++;
          } else {
            partly++;
          }
          final m = minutesOf[id] ?? 0;
          focusMinutes += m;
          final name = nameOf[id];
          if (name != null) byName[name] = (byName[name] ?? 0) + m;
        case BlockResult.no:
          missed++;
        case BlockResult.skipped:
          skipped++;
          final r = s.skipReason ?? 'Other';
          reasons[r] = (reasons[r] ?? 0) + 1;
        case null:
          break;
      }
    });
  }

  final monday = DateTime(today.year, today.month, today.day).subtract(Duration(days: today.weekday - 1));
  final week = <DayBar>[];
  for (var i = 0; i < 7; i++) {
    final day = DateTime(monday.year, monday.month, monday.day + i);
    final record = data.days[dateKey(day)];
    final t = record != null ? _template(data, record.templateId) : data.templateForWeekday(day.weekday);
    final total = t == null ? 0 : t.blocks.where((b) => !b.isFree).length;
    final good = record == null
        ? 0
        : record.blocks.values.where((s) => s.result == BlockResult.done || s.result == BlockResult.partly).length;
    week.add(DayBar(day, good, total));
  }

  List<MapEntry<String, int>> sorted(Map<String, int> m) => m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

  return Stats(
    currentStreak: currentStreak(data.days, today, dateKey),
    longestStreak: longestStreak(data.days),
    done: done,
    partly: partly,
    missed: missed,
    skipped: skipped,
    focusMinutes: focusMinutes,
    minutesByName: sorted(byName),
    skipReasons: sorted(reasons),
    week: week,
  );
}
