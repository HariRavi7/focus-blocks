import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'format.dart';
import 'models.dart';
import 'pomodoro.dart';
import 'schedule_engine.dart';
import 'storage.dart';

final storeProvider = Provider<LocalStore>((ref) => LocalStore());

/// Ticks once a second. Everything time-based reads from here, so the
/// whole UI moves together.
final clockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now());
});

final appProvider = AsyncNotifierProvider<AppController, AppData>(AppController.new);

/// Today's computed view: blocks, phase, current and next block.
final todayProvider = Provider<TodayView?>((ref) {
  final data = ref.watch(appProvider).valueOrNull;
  final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
  if (data == null) return null;
  final record = AppController.recordFor(data, now);
  final template = AppController.templateFor(data, record);
  return TodayView(
    date: now,
    record: record,
    template: template,
    snap: snapshot(template, record, minutesOfDay(now)),
    streak: currentStreak(data.days, now, dateKey),
  );
});

/// The Pomodoro timer as of this second, plus settings and today's numbers.
final pomodoroProvider = Provider<PomodoroView?>((ref) {
  final data = ref.watch(appProvider).valueOrNull;
  final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
  if (data == null) return null;
  return PomodoroView(
    now: now,
    timer: data.pomodoro,
    settings: data.pomodoroSettings,
    stats: pomodoroStats(data.pomodoros, now),
    today: data.pomodoros.where((p) => p.date == dateKey(now)).toList(),
  );
});

class PomodoroView {
  final DateTime now;
  final PomodoroTimer? timer;
  final PomodoroSettings settings;
  final PomodoroStats stats;
  final List<PomodoroSession> today; // oldest first
  const PomodoroView({
    required this.now,
    required this.timer,
    required this.settings,
    required this.stats,
    required this.today,
  });

  int get secondsLeft => timer?.secondsLeft(now) ?? settings.focusMinutes * 60;
}

class TodayView {
  final DateTime date;
  final DayRecord record;
  final DayTemplate? template;
  final DaySnapshot snap;
  final int streak;
  const TodayView({required this.date, required this.record, required this.template, required this.snap, required this.streak});
}

class RemovedTask {
  final String blockId;
  final TaskItem task;
  final int index;
  const RemovedTask(this.blockId, this.task, this.index);
}

class AppController extends AsyncNotifier<AppData> {
  int _idSeq = 0;

  @override
  Future<AppData> build() => ref.read(storeProvider).load();

  AppData get _data => state.valueOrNull ?? const AppData();

  String newId(String prefix) => '$prefix${DateTime.now().microsecondsSinceEpoch}${_idSeq++}';

  Future<void> _commit(AppData next) async {
    state = AsyncData(next);
    await ref.read(storeProvider).save(next);
  }

  // ---------- Day records ----------

  /// The record for [now]'s date. Not saved until something changes; a fresh
  /// day already includes tasks carried over from the last run of each block.
  static DayRecord recordFor(AppData data, DateTime now) => dayRecordFor(data, now);

  static DayTemplate? templateFor(AppData data, DayRecord record) => templateOf(data, record);

  /// Changes one block in today's record and saves.
  /// [carryFor] sets the tasks waiting for this block's next run
  /// (empty list clears them; null leaves them alone).
  Future<void> _updateBlock(String blockId, BlockDayState Function(BlockDayState) change,
      {List<TaskItem>? carryFor}) async {
    final data = _data;
    final record = recordFor(data, DateTime.now());
    final updated = record.withBlock(blockId, change(record.stateFor(blockId)));
    final nextCarry = Map<String, List<TaskItem>>.from(data.carryOver);
    // Saving a fresh day consumes the carried-over tasks it pulled in.
    if (!data.days.containsKey(record.date)) {
      for (final id in record.blocks.keys) {
        nextCarry.remove(id);
      }
    }
    if (carryFor != null) {
      if (carryFor.isEmpty) {
        nextCarry.remove(blockId);
      } else {
        nextCarry[blockId] = carryFor;
      }
    }
    await _commit(data.copyWith(days: {...data.days, record.date: updated}, carryOver: nextCarry));
  }

  // ---------- Setup & templates ----------

  Future<void> finishSetup(List<DayTemplate> templates, {bool reminders = true}) async {
    await _commit(_data.copyWith(onboarded: true, templates: templates, reminders: reminders));
  }

  Future<void> setReminders(bool on) async {
    await _commit(_data.copyWith(reminders: on));
  }

  /// Saves a template. A weekday belongs to one template, so any day picked
  /// here is taken away from the others.
  Future<void> saveTemplate(DayTemplate t) async {
    final others = _data.templates
        .where((x) => x.id != t.id)
        .map((x) => x.copyWith(weekdays: x.weekdays.where((d) => !t.weekdays.contains(d)).toList()))
        .toList();
    final i = _data.templates.indexWhere((x) => x.id == t.id);
    final list = [...others];
    if (i < 0) {
      list.add(t);
    } else {
      list.insert(i.clamp(0, list.length).toInt(), t);
    }
    await _commit(_data.copyWith(templates: list));
  }

  Future<void> deleteTemplate(String id) async {
    await _commit(_data.copyWith(templates: _data.templates.where((t) => t.id != id).toList()));
  }

  /// Changing a block's color updates its template, so it sticks.
  Future<void> setBlockColor(String blockId, BlockColor color) async {
    final templates = _data.templates
        .map((t) => t.copyWith(blocks: t.blocks.map((b) => b.id == blockId ? b.copyWith(color: color) : b).toList()))
        .toList();
    await _commit(_data.copyWith(templates: templates));
  }

  // ---------- Tasks ----------

  Future<void> addTask(String blockId, String title, int minutes, {bool rightAfterCurrent = false}) async {
    final task = TaskItem(id: newId('t'), title: title.trim(), minutes: minutes);
    await _updateBlock(blockId, (s) {
      final list = [...s.tasks];
      final firstOpen = list.indexWhere((t) => !t.done);
      if (rightAfterCurrent && firstOpen >= 0) {
        list.insert(firstOpen + 1, task);
      } else {
        list.add(task);
      }
      return s.copyWith(tasks: list);
    });
  }

  /// Keeps a task for the next time this block runs, without touching today.
  Future<void> saveForLater(String blockId, String title, int minutes) async {
    final data = _data;
    final task = TaskItem(id: newId('t'), title: title.trim(), minutes: minutes);
    final record = recordFor(data, DateTime.now());
    var days = data.days;
    final carry = Map<String, List<TaskItem>>.from(data.carryOver);
    // Save today first, so the task isn't pulled into today's fresh record.
    if (!days.containsKey(record.date)) {
      days = {...days, record.date: record};
      for (final id in record.blocks.keys) {
        carry.remove(id);
      }
    }
    carry[blockId] = [...(carry[blockId] ?? const <TaskItem>[]), task];
    await _commit(data.copyWith(days: days, carryOver: carry));
  }

  Future<void> toggleTask(String blockId, String taskId) async {
    await _updateBlock(
      blockId,
      (s) => s.copyWith(tasks: s.tasks.map((t) => t.id == taskId ? t.copyWith(done: !t.done) : t).toList()),
    );
  }

  Future<RemovedTask?> removeTask(String blockId, String taskId) async {
    RemovedTask? removed;
    await _updateBlock(blockId, (s) {
      final list = [...s.tasks];
      final i = list.indexWhere((t) => t.id == taskId);
      if (i >= 0) {
        removed = RemovedTask(blockId, list.removeAt(i), i);
      }
      return s.copyWith(tasks: list);
    });
    return removed;
  }

  Future<void> undoRemove(RemovedTask r) async {
    await _updateBlock(r.blockId, (s) {
      final list = [...s.tasks];
      list.insert(r.index.clamp(0, list.length).toInt(), r.task);
      return s.copyWith(tasks: list);
    });
  }

  Future<void> adjustTaskMinutes(String blockId, String taskId, int delta) async {
    await _updateBlock(
      blockId,
      (s) => s.copyWith(
        tasks: s.tasks
            .map((t) => t.id == taskId ? t.copyWith(minutes: (t.minutes + delta).clamp(5, 240).toInt()) : t)
            .toList(),
      ),
    );
  }

  // ---------- Block outcomes ----------

  Future<void> extend(String blockId, int minutes) async {
    await _updateBlock(blockId, (s) => s.copyWith(extendMinutes: s.extendMinutes + minutes));
  }

  Future<void> review(String blockId, BlockResult result) => _close(blockId, (s) => s.copyWith(result: result));

  Future<void> skip(String blockId, String reason, String? note) => _close(
        blockId,
        (s) => s.copyWith(
          result: BlockResult.skipped,
          skipReason: reason,
          skipNote: (note == null || note.trim().isEmpty) ? null : note.trim(),
        ),
      );

  /// Closes a block and carries its unfinished tasks to the next time the
  /// same block runs.
  Future<void> _close(String blockId, BlockDayState Function(BlockDayState) change) async {
    final record = recordFor(_data, DateTime.now());
    final open = record.stateFor(blockId).tasks.where((t) => !t.done).toList();
    await _updateBlock(blockId, change, carryFor: open);
  }

  // ---------- Pomodoro ----------

  PomodoroTimer? get _pomodoro => _data.pomodoro;

  /// Starts a focus round, or resumes a paused timer. A new round picks up
  /// [label] and the block and task it belongs to.
  Future<void> startPomodoro({
    String label = '',
    String? blockId,
    String? blockName,
    String? taskId,
    String? taskTitle,
  }) async {
    final now = DateTime.now();
    final cur = _pomodoro;
    final PomodoroTimer next;
    if (cur == null) {
      next = startTimer(
        newFocus(_data.pomodoroSettings,
            label: label, blockId: blockId, blockName: blockName, taskId: taskId, taskTitle: taskTitle),
        now,
      );
    } else {
      next = startTimer(cur, now);
    }
    await _commit(_data.copyWith(pomodoro: next));
  }

  Future<void> pausePomodoro() async {
    final cur = _pomodoro;
    if (cur == null) return;
    await _commit(_data.copyWith(pomodoro: pauseTimer(cur, DateTime.now())));
  }

  Future<void> togglePomodoro() async {
    final cur = _pomodoro;
    if (cur != null && cur.running) return pausePomodoro();
    return startPomodoro();
  }

  /// Ends this phase now and moves to the next one. A focus round cut short
  /// is still logged with the minutes you put in.
  Future<void> skipPomodoro() async {
    final cur = _pomodoro;
    if (cur == null) return;
    final now = DateTime.now();
    final session = sessionFor(cur, now, completed: false, id: newId('p'));
    await _commit(_data.copyWith(
      pomodoro: nextPhase(cur, _data.pomodoroSettings, now),
      pomodoros: session == null ? null : [..._data.pomodoros, session],
    ));
  }

  /// Stops the timer. A focus round cut short is still logged.
  Future<void> stopPomodoro() async {
    final cur = _pomodoro;
    if (cur == null) return;
    final session = sessionFor(cur, DateTime.now(), completed: false, id: newId('p'));
    await _commit(_data.copyWith(
      clearPomodoro: true,
      pomodoros: session == null ? null : [..._data.pomodoros, session],
    ));
  }

  /// Changes what the current round is for.
  Future<void> setPomodoroLabel(String label) async {
    final cur = _pomodoro;
    if (cur == null) return;
    await _commit(_data.copyWith(pomodoro: cur.withLabel(label)));
  }

  /// Saves new lengths. A phase that hasn't started yet takes the new length.
  Future<void> setPomodoroSettings(PomodoroSettings s) async {
    var cur = _pomodoro;
    if (cur != null && !cur.started) {
      cur = cur.withLength(s.minutesFor(cur.phase) * 60);
    }
    await _commit(_data.copyWith(pomodoroSettings: s, pomodoro: cur));
  }

  /// Called every tick: moves past any phase that has run out and logs the
  /// finished focus rounds. Returns what happened, or null if nothing did.
  Future<PomodoroAdvance?> advancePomodoro(DateTime now) async {
    final cur = _pomodoro;
    if (cur == null || !cur.isOver(now)) return null;
    final a = advanceTimer(cur, _data.pomodoroSettings, now, () => newId('p'));
    await _commit(_data.copyWith(pomodoro: a.timer, pomodoros: [..._data.pomodoros, ...a.sessions]));
    return a;
  }
}
