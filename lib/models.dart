/// Data model for Focus Blocks.
///
/// Times of day are stored as minutes after midnight (0–1440) so the
/// schedule maths stays simple and time-zone free.
library;

enum BlockKind { focus, free }

/// Colors a block can use. `auto` picks one from the block's time of day.
enum BlockColor { auto, amber, teal, indigo, cyan }

/// How a block ended once it was reviewed or skipped.
enum BlockResult { done, partly, no, skipped }

class TemplateBlock {
  final String id;
  final String name;
  final int start; // minutes after midnight
  final int end; // minutes after midnight, > start
  final BlockKind kind;
  final BlockColor color;

  const TemplateBlock({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
    this.kind = BlockKind.focus,
    this.color = BlockColor.auto,
  });

  int get minutes => end - start;
  bool get isFree => kind == BlockKind.free;

  TemplateBlock copyWith({String? name, int? start, int? end, BlockKind? kind, BlockColor? color}) => TemplateBlock(
        id: id,
        name: name ?? this.name,
        start: start ?? this.start,
        end: end ?? this.end,
        kind: kind ?? this.kind,
        color: color ?? this.color,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'start': start,
        'end': end,
        'kind': kind.name,
        'color': color.name,
      };

  factory TemplateBlock.fromJson(Map<String, dynamic> j) => TemplateBlock(
        id: j['id'] as String,
        name: j['name'] as String,
        start: j['start'] as int,
        end: j['end'] as int,
        kind: BlockKind.values.byName(j['kind'] as String? ?? 'focus'),
        color: BlockColor.values.byName(j['color'] as String? ?? 'auto'),
      );
}

/// A named day plan, assigned to days of the week.
/// `weekdays` uses [DateTime.weekday]: 1 = Monday … 7 = Sunday.
class DayTemplate {
  final String id;
  final String name;
  final List<int> weekdays;
  final List<TemplateBlock> blocks;

  const DayTemplate({required this.id, required this.name, required this.weekdays, required this.blocks});

  List<TemplateBlock> get sortedBlocks => [...blocks]..sort((a, b) => a.start.compareTo(b.start));

  DayTemplate copyWith({String? name, List<int>? weekdays, List<TemplateBlock>? blocks}) => DayTemplate(
        id: id,
        name: name ?? this.name,
        weekdays: weekdays ?? this.weekdays,
        blocks: blocks ?? this.blocks,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'weekdays': weekdays,
        'blocks': blocks.map((b) => b.toJson()).toList(),
      };

  factory DayTemplate.fromJson(Map<String, dynamic> j) => DayTemplate(
        id: j['id'] as String,
        name: j['name'] as String,
        weekdays: (j['weekdays'] as List).cast<int>(),
        blocks: (j['blocks'] as List).map((e) => TemplateBlock.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class TaskItem {
  final String id;
  final String title;
  final int minutes;
  final bool done;

  const TaskItem({required this.id, required this.title, this.minutes = 15, this.done = false});

  TaskItem copyWith({String? title, int? minutes, bool? done}) =>
      TaskItem(id: id, title: title ?? this.title, minutes: minutes ?? this.minutes, done: done ?? this.done);

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'minutes': minutes, 'done': done};

  factory TaskItem.fromJson(Map<String, dynamic> j) => TaskItem(
        id: j['id'] as String,
        title: j['title'] as String,
        minutes: j['minutes'] as int? ?? 15,
        done: j['done'] as bool? ?? false,
      );
}

/// What happened to one block on one day.
class BlockDayState {
  final int extendMinutes;
  final List<TaskItem> tasks;
  final BlockResult? result;
  final String? skipReason;
  final String? skipNote;
  final BlockColor? colorOverride;

  const BlockDayState({
    this.extendMinutes = 0,
    this.tasks = const [],
    this.result,
    this.skipReason,
    this.skipNote,
    this.colorOverride,
  });

  bool get isClosed => result != null;

  BlockDayState copyWith({
    int? extendMinutes,
    List<TaskItem>? tasks,
    BlockResult? result,
    String? skipReason,
    String? skipNote,
    BlockColor? colorOverride,
  }) =>
      BlockDayState(
        extendMinutes: extendMinutes ?? this.extendMinutes,
        tasks: tasks ?? this.tasks,
        result: result ?? this.result,
        skipReason: skipReason ?? this.skipReason,
        skipNote: skipNote ?? this.skipNote,
        colorOverride: colorOverride ?? this.colorOverride,
      );

  Map<String, dynamic> toJson() => {
        'extendMinutes': extendMinutes,
        'tasks': tasks.map((t) => t.toJson()).toList(),
        if (result != null) 'result': result!.name,
        if (skipReason != null) 'skipReason': skipReason,
        if (skipNote != null) 'skipNote': skipNote,
        if (colorOverride != null) 'colorOverride': colorOverride!.name,
      };

  factory BlockDayState.fromJson(Map<String, dynamic> j) => BlockDayState(
        extendMinutes: j['extendMinutes'] as int? ?? 0,
        tasks: ((j['tasks'] as List?) ?? const []).map((e) => TaskItem.fromJson(e as Map<String, dynamic>)).toList(),
        result: j['result'] == null ? null : BlockResult.values.byName(j['result'] as String),
        skipReason: j['skipReason'] as String?,
        skipNote: j['skipNote'] as String?,
        colorOverride: j['colorOverride'] == null ? null : BlockColor.values.byName(j['colorOverride'] as String),
      );
}

/// One calendar day: which template ran and how each block went.
class DayRecord {
  final String date; // yyyy-mm-dd
  final String? templateId;
  final Map<String, BlockDayState> blocks; // keyed by TemplateBlock.id

  const DayRecord({required this.date, this.templateId, this.blocks = const {}});

  BlockDayState stateFor(String blockId) => blocks[blockId] ?? const BlockDayState();

  DayRecord withBlock(String blockId, BlockDayState state) =>
      DayRecord(date: date, templateId: templateId, blocks: {...blocks, blockId: state});

  Map<String, dynamic> toJson() => {
        'date': date,
        if (templateId != null) 'templateId': templateId,
        'blocks': blocks.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory DayRecord.fromJson(Map<String, dynamic> j) => DayRecord(
        date: j['date'] as String,
        templateId: j['templateId'] as String?,
        blocks: ((j['blocks'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k as String, BlockDayState.fromJson(v as Map<String, dynamic>))),
      );
}

class AppData {
  final bool onboarded;
  final List<DayTemplate> templates;
  final Map<String, DayRecord> days; // keyed by yyyy-mm-dd

  /// Unfinished tasks waiting for the next run of a template block.
  final Map<String, List<TaskItem>> carryOver;
  final List<String> customQuotes;

  /// 15-minute heads-up reminders, the countdown notification and the widget.
  final bool reminders;

  const AppData({
    this.onboarded = false,
    this.templates = const [],
    this.days = const {},
    this.carryOver = const {},
    this.customQuotes = const [],
    this.reminders = true,
  });

  AppData copyWith({
    bool? onboarded,
    List<DayTemplate>? templates,
    Map<String, DayRecord>? days,
    Map<String, List<TaskItem>>? carryOver,
    List<String>? customQuotes,
    bool? reminders,
  }) =>
      AppData(
        onboarded: onboarded ?? this.onboarded,
        templates: templates ?? this.templates,
        days: days ?? this.days,
        carryOver: carryOver ?? this.carryOver,
        customQuotes: customQuotes ?? this.customQuotes,
        reminders: reminders ?? this.reminders,
      );

  DayTemplate? templateForWeekday(int weekday) {
    for (final t in templates) {
      if (t.weekdays.contains(weekday)) return t;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'onboarded': onboarded,
        'templates': templates.map((t) => t.toJson()).toList(),
        'days': days.map((k, v) => MapEntry(k, v.toJson())),
        'carryOver': carryOver.map((k, v) => MapEntry(k, v.map((t) => t.toJson()).toList())),
        'customQuotes': customQuotes,
        'reminders': reminders,
      };

  factory AppData.fromJson(Map<String, dynamic> j) => AppData(
        onboarded: j['onboarded'] as bool? ?? false,
        templates: ((j['templates'] as List?) ?? const [])
            .map((e) => DayTemplate.fromJson(e as Map<String, dynamic>))
            .toList(),
        days: ((j['days'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k as String, DayRecord.fromJson(v as Map<String, dynamic>))),
        carryOver: ((j['carryOver'] as Map?) ?? const {}).map((k, v) => MapEntry(
              k as String,
              (v as List).map((e) => TaskItem.fromJson(e as Map<String, dynamic>)).toList(),
            )),
        customQuotes: ((j['customQuotes'] as List?) ?? const []).cast<String>(),
        reminders: j['reminders'] as bool? ?? true,
      );
}
