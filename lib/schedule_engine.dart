/// Pure scheduling logic: no Flutter imports, fully unit-testable.
library;

import 'format.dart';
import 'models.dart';

/// A template block placed on a real day, after extensions have been applied.
class PlannedBlock {
  final TemplateBlock block;
  final int start;
  final int end;
  final BlockDayState state;

  /// Minutes of this free block taken by an earlier extension.
  final int usedByExtension;

  const PlannedBlock({
    required this.block,
    required this.start,
    required this.end,
    required this.state,
    this.usedByExtension = 0,
  });

  String get id => block.id;
  String get name => block.name;
  bool get isFree => block.isFree;
  int get minutes => end - start;
  bool get isClosed => state.isClosed;
  BlockColor get color => state.colorOverride ?? block.color;
}

enum Phase {
  /// No template for today, or no blocks.
  empty,

  /// A focus block is running now.
  running,

  /// A focus block's time is up but it hasn't been reviewed.
  ended,

  /// Between blocks, or in free time; the next focus block is coming.
  upNext,

  /// Every focus block today is closed or past.
  dayDone,
}

class DaySnapshot {
  final List<PlannedBlock> blocks;
  final Phase phase;
  final PlannedBlock? current; // running or ended block
  final PlannedBlock? next; // next focus block that hasn't started
  final int now; // minutes after midnight

  const DaySnapshot({required this.blocks, required this.phase, this.current, this.next, required this.now});

  int get focusCount => blocks.where((b) => !b.isFree).length;
  int get closedCount => blocks.where((b) => !b.isFree && b.isClosed).length;
}

/// Lays out today's blocks.
///
/// Extension rule: extra time comes out of the free time right after a block
/// first; later blocks only move by whatever the free time can't cover.
/// Anything pushed past midnight is trimmed.
List<PlannedBlock> layoutDay(DayTemplate template, DayRecord record) {
  final out = <PlannedBlock>[];
  var carry = 0;
  for (final b in template.sortedBlocks) {
    final state = record.stateFor(b.id);
    var start = b.start;
    var end = b.end;
    var used = 0;
    if (b.isFree) {
      final len = end - start;
      used = carry < len ? carry : len;
      start += carry;
      carry -= used;
      if (start > end) start = end;
    } else {
      start += carry;
      end += carry + state.extendMinutes;
      carry += state.extendMinutes;
    }
    if (start > 1440) start = 1440;
    if (end > 1440) end = 1440;
    if (end < start) end = start;
    out.add(PlannedBlock(block: b, start: start, end: end, state: state, usedByExtension: used));
  }
  return out;
}

/// The record for [day]. A day that hasn't been saved yet is built fresh from
/// the weekday's template and already holds tasks carried over from the last
/// run of each block.
DayRecord dayRecordFor(AppData data, DateTime day) {
  final key = dateKey(day);
  final existing = data.days[key];
  if (existing != null) return existing;
  final t = data.templateForWeekday(day.weekday);
  if (t == null) return DayRecord(date: key);
  final blocks = <String, BlockDayState>{};
  for (final b in t.blocks) {
    final carried = data.carryOver[b.id];
    if (carried != null && carried.isNotEmpty) {
      blocks[b.id] = BlockDayState(tasks: carried);
    }
  }
  return DayRecord(date: key, templateId: t.id, blocks: blocks);
}

DayTemplate? templateOf(AppData data, DayRecord record) {
  if (record.templateId == null) return null;
  for (final t in data.templates) {
    if (t.id == record.templateId) return t;
  }
  return null;
}

/// Fills every gap between focus blocks with an explicit free block, so
/// extensions have free time to borrow from. Existing free blocks are kept.
List<TemplateBlock> fillGaps(List<TemplateBlock> blocks, String Function() newId) {
  final sorted = [...blocks]..sort((a, b) => a.start.compareTo(b.start));
  final out = <TemplateBlock>[];
  for (var i = 0; i < sorted.length; i++) {
    out.add(sorted[i]);
    if (i + 1 < sorted.length) {
      final gapStart = sorted[i].end;
      final gapEnd = sorted[i + 1].start;
      if (gapEnd > gapStart) {
        out.add(TemplateBlock(id: newId(), name: 'Free time', start: gapStart, end: gapEnd, kind: BlockKind.free));
      }
    }
  }
  return out;
}

/// The first block in [blocks] that overlaps [start]–[end], ignoring [exceptId].
TemplateBlock? findOverlap(List<TemplateBlock> blocks, int start, int end, {String? exceptId}) {
  for (final b in blocks) {
    if (b.id == exceptId) continue;
    if (start < b.end && end > b.start) return b;
  }
  return null;
}

DaySnapshot snapshot(DayTemplate? template, DayRecord record, int now) {
  if (template == null || template.blocks.isEmpty) {
    return DaySnapshot(blocks: const [], phase: Phase.empty, now: now);
  }
  final blocks = layoutDay(template, record);
  final focus = blocks.where((b) => !b.isFree).toList();

  // A running block always wins: blocks start on their own.
  for (final b in focus) {
    if (!b.isClosed && now >= b.start && now < b.end) {
      return DaySnapshot(blocks: blocks, phase: Phase.running, current: b, next: _nextAfter(focus, b), now: now);
    }
  }
  // Otherwise the most recent block whose time is up but was never reviewed
  // waits for "extend or move on", for up to two hours. Older unreviewed
  // blocks simply stay unreviewed.
  PlannedBlock? ended;
  for (final b in focus) {
    if (!b.isClosed && b.end > b.start && now >= b.end && now - b.end <= 120) ended = b;
  }
  if (ended != null) {
    final later = focus.where((b) => !b.isClosed && b.start > now).toList();
    return DaySnapshot(
      blocks: blocks,
      phase: Phase.ended,
      current: ended,
      next: later.isEmpty ? null : later.first,
      now: now,
    );
  }
  final upcoming = focus.where((b) => !b.isClosed && b.start > now).toList();
  if (upcoming.isNotEmpty) {
    return DaySnapshot(blocks: blocks, phase: Phase.upNext, next: upcoming.first, now: now);
  }
  return DaySnapshot(blocks: blocks, phase: Phase.dayDone, now: now);
}

PlannedBlock? _nextAfter(List<PlannedBlock> focus, PlannedBlock b) {
  final i = focus.indexOf(b);
  for (var j = i + 1; j < focus.length; j++) {
    if (!focus[j].isClosed) return focus[j];
  }
  return null;
}

/// Where each task sits inside its block, in order.
class TaskSlot {
  final TaskItem task;
  final int start;
  final int end;
  const TaskSlot(this.task, this.start, this.end);
}

List<TaskSlot> taskSlots(PlannedBlock block) {
  var t = block.start;
  return [
    for (final task in block.state.tasks) TaskSlot(task, t, t += task.minutes),
  ];
}

TaskSlot? currentTaskSlot(PlannedBlock block) {
  for (final s in taskSlots(block)) {
    if (!s.task.done) return s;
  }
  return null;
}

/// What extending by [minutes] would do, for the time's-up sheet.
class ExtendPreview {
  final int fromFree;
  final int shiftsLater;
  final int newEnd;
  const ExtendPreview(this.fromFree, this.shiftsLater, this.newEnd);

  String get describe {
    if (shiftsLater <= 0) return 'Taken from free time';
    if (fromFree == 0) return 'Later blocks move $shiftsLater min';
    return '$fromFree min from free time, later blocks +$shiftsLater';
  }
}

ExtendPreview previewExtend(DayTemplate template, DayRecord record, String blockId, int minutes) {
  final before = layoutDay(template, record);
  final st = record.stateFor(blockId);
  final after = layoutDay(template, record.withBlock(blockId, st.copyWith(extendMinutes: st.extendMinutes + minutes)));
  var fromFree = 0;
  var newEnd = 0;
  for (var i = 0; i < before.length; i++) {
    if (before[i].isFree) fromFree += before[i].minutes - after[i].minutes;
    if (after[i].id == blockId) newEnd = after[i].end;
  }
  return ExtendPreview(fromFree, minutes - fromFree, newEnd);
}

/// Consecutive days, counting back from today, with at least one block
/// reviewed as done or partly done. Today only counts once it qualifies,
/// so an unfinished today never breaks the streak.
int currentStreak(Map<String, DayRecord> days, DateTime today, String Function(DateTime) keyOf) {
  bool qualifies(DateTime d) {
    final r = days[keyOf(d)];
    if (r == null) return false;
    return r.blocks.values.any((s) => s.result == BlockResult.done || s.result == BlockResult.partly);
  }

  var d = DateTime(today.year, today.month, today.day);
  var streak = 0;
  if (qualifies(d)) streak++;
  d = d.subtract(const Duration(days: 1));
  while (qualifies(d)) {
    streak++;
    d = d.subtract(const Duration(days: 1));
  }
  return streak;
}

int longestStreak(Map<String, DayRecord> days) {
  final good = days.values
      .where((r) => r.blocks.values.any((s) => s.result == BlockResult.done || s.result == BlockResult.partly))
      .map((r) => DateTime.parse(r.date))
      .toList()
    ..sort();
  var best = 0;
  var run = 0;
  DateTime? prev;
  for (final d in good) {
    if (prev != null && d.difference(prev).inDays == 1) {
      run++;
    } else {
      run = 1;
    }
    if (run > best) best = run;
    prev = d;
  }
  return best;
}
