import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import '../schedule_engine.dart';
import '../theme.dart';
import 'common.dart';
import 'templates_screen.dart';

class _Suggestion {
  final String name;
  final int start;
  final int length;
  const _Suggestion(this.name, this.start, this.length);
}

const _suggestions = [
  [
    _Suggestion('Study', 390, 90),
    _Suggestion('Work', 570, 540),
    _Suggestion('Side project', 1230, 90),
    _Suggestion('Plan tomorrow', 1320, 15),
  ],
  [
    _Suggestion('Deep study', 480, 180),
    _Suggestion('Side project', 840, 180),
    _Suggestion('Workout', 1080, 60),
    _Suggestion('Weekly review', 1140, 30),
  ],
];

class _Draft {
  final TextEditingController name;
  Set<int> days;
  List<TemplateBlock> blocks = [];
  _Draft(String n, this.days) : name = TextEditingController(text: n);
}

/// First run: two templates, then go.
class SetupFlow extends ConsumerStatefulWidget {
  const SetupFlow({super.key});

  @override
  ConsumerState<SetupFlow> createState() => _SetupFlowState();
}

class _SetupFlowState extends ConsumerState<SetupFlow> {
  int _step = 0; // 0 welcome, 1 weekday, 2 weekend, 3 done
  bool _skipWeekend = false;
  int _seq = 0;
  final _drafts = [_Draft('Weekday', {1, 2, 3, 4, 5}), _Draft('Weekend', {6, 7})];

  String _id(String p) => '$p${DateTime.now().microsecondsSinceEpoch}${_seq++}';

  @override
  void initState() {
    super.initState();
    for (final d in _drafts) {
      d.name.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final d in _drafts) {
      d.name.dispose();
    }
    super.dispose();
  }

  List<DayTemplate> _build() {
    final weekday = _drafts[0];
    final out = <DayTemplate>[
      DayTemplate(
        id: _id('tpl'),
        name: weekday.name.text.trim().isEmpty ? 'Weekday' : weekday.name.text.trim(),
        weekdays: weekday.days.toList()..sort(),
        blocks: fillGaps(weekday.blocks, () => _id('b')),
      ),
    ];
    final weekend = _drafts[1];
    if (!_skipWeekend && weekend.blocks.isNotEmpty) {
      out.add(DayTemplate(
        id: _id('tpl'),
        name: weekend.name.text.trim().isEmpty ? 'Weekend' : weekend.name.text.trim(),
        weekdays: (weekend.days.difference(weekday.days).toList())..sort(),
        blocks: fillGaps(weekend.blocks, () => _id('b')),
      ));
    }
    return out;
  }

  bool get _canContinue {
    if (_step == 1 || _step == 2) {
      final d = _drafts[_step - 1];
      return d.blocks.any((b) => !b.isFree) && d.days.isNotEmpty;
    }
    return true;
  }

  void _next() {
    if (_step == 2) _skipWeekend = false;
    setState(() => _step++);
  }

  Future<void> _finish() async {
    await ref.read(appProvider.notifier).finishSetup(_build());
  }

  @override
  Widget build(BuildContext context) {
    final Widget content = switch (_step) {
      0 => _welcome(),
      1 => _templateStep(0),
      2 => _templateStep(1),
      _ => _done(),
    };
    return Scaffold(
      body: GlassBackdrop(
        color: Brand.cyan,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_step > 0) _topBar(),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: KeyedSubtree(key: ValueKey(_step), child: content),
                    ),
                  ),
                  Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 16), child: _bottom()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 20, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () => setState(() => _step--),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          const Spacer(),
          for (var i = 1; i <= 3; i++)
            Container(
              width: i == _step ? 20 : 8,
              height: 8,
              margin: const EdgeInsets.only(left: 6),
              decoration: BoxDecoration(
                color: i <= _step ? Brand.cyanDeep : Brand.line,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          const SizedBox(width: 10),
          Text('${_step.clamp(1, 3)} of 3', style: const TextStyle(fontSize: 13, color: Brand.muted)),
        ],
      ),
    );
  }

  Widget _bottom() {
    if (_step == 3) {
      return FilledButton(onPressed: _finish, child: const Text('Start my first day'));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          onPressed: _canContinue ? _next : null,
          child: Text(_step == 0 ? 'Get started' : 'Continue'),
        ),
        if (_step == 2)
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            onPressed: () => setState(() {
              _skipWeekend = true;
              _step = 3;
            }),
            child: const Text('Skip, keep weekends free'),
          ),
      ],
    );
  }

  Widget _welcome() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
      children: const [
        _WelcomeArt(),
        SizedBox(height: 36),
        Text('Plan your day in blocks.\nThen just show up.',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.8, height: 1.15)),
        SizedBox(height: 14),
        Text(
          "Let's set up two templates, one for weekdays and one for weekends. "
          'It takes about two minutes, and you can change everything later.',
          style: TextStyle(fontSize: 16, color: Brand.muted, height: 1.45),
        ),
      ],
    );
  }

  Widget _templateStep(int ti) {
    final d = _drafts[ti];
    final other = _drafts[1 - ti];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      children: [
        Text(ti == 0 ? 'Template 1 of 2' : 'Template 2 of 2',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Brand.cyanDeep)),
        const SizedBox(height: 6),
        Text(ti == 0 ? 'Build your weekday' : 'Now your weekend',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
        const SizedBox(height: 6),
        Text(
          ti == 0
              ? 'Split a normal workday into blocks. Each block is a promise to show up for that time.'
              : 'Usually lighter. Days you leave out of both templates become free days.',
          style: const TextStyle(fontSize: 14, color: Brand.muted, height: 1.45),
        ),
        const SizedBox(height: 18),
        TextField(controller: d.name, decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 16),
        const Text('Runs on', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        WeekdayPicker(
          selected: d.days,
          onToggle: (day) => setState(() {
            d.days = {...d.days};
            if (!d.days.remove(day)) {
              d.days.add(day);
              other.days = {...other.days}..remove(day);
            }
          }),
        ),
        const SizedBox(height: 18),
        const Row(
          children: [
            Expanded(child: Text('Your day', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
            Text('6 AM – midnight', style: TextStyle(fontSize: 12, color: Brand.muted)),
          ],
        ),
        const SizedBox(height: 8),
        TimelineStrip(blocks: d.blocks),
        const SizedBox(height: 18),
        const Text('Tap to add a starter block', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in _suggestions[ti]) _suggestionChip(d, s),
          ],
        ),
        const SizedBox(height: 18),
        BlockListEditor(blocks: d.blocks, onChanged: (b) => setState(() => d.blocks = b)),
      ],
    );
  }

  Widget _suggestionChip(_Draft d, _Suggestion s) {
    TemplateBlock? existing;
    for (final b in d.blocks) {
      if (b.name == s.name && b.start == s.start && b.end == s.start + s.length) existing = b;
    }
    final on = existing != null;
    return Semantics(
      button: true,
      selected: on,
      child: Material(
        color: on ? Brand.cyanSoft : Colors.white.withValues(alpha: 0.85),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: on ? Brand.cyanDeep : const Color(0xFFD6DDE1)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            if (on) {
              setState(() => d.blocks = d.blocks.where((b) => b.id != existing!.id).toList());
              return;
            }
            final clash = findOverlap(d.blocks, s.start, s.start + s.length);
            if (clash != null) {
              showToast(context, 'Overlaps ${clash.name}. Change or remove it first.');
              return;
            }
            setState(() => d.blocks = [
                  ...d.blocks,
                  TemplateBlock(id: _id('b'), name: s.name, start: s.start, end: s.start + s.length),
                ]..sort((a, b) => a.start.compareTo(b.start)));
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(formatRange(s.start, s.start + s.length), style: const TextStyle(fontSize: 12, color: Brand.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _done() {
    final templates = _build();
    final firstLine = _firstBlockLine(templates, DateTime.now());
    final assigned = {for (final t in templates) ...t.weekdays};
    final freeDays = [for (var d = 1; d <= 7; d++) if (!assigned.contains(d)) weekdayShort[d - 1]];

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 16),
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.5, end: 1),
          duration: const Duration(milliseconds: 480),
          curve: Curves.easeOutBack,
          builder: (_, v, child) => Align(alignment: Alignment.centerLeft, child: Transform.scale(scale: v, child: child)),
          child: const GlassTick(color: Brand.cyan, done: true, size: 56, label: 'Setup complete'),
        ),
        const SizedBox(height: 20),
        const Text("You're set.", style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.8)),
        const SizedBox(height: 8),
        Text(firstLine, style: const TextStyle(fontSize: 16, color: Brand.muted, height: 1.4)),
        const SizedBox(height: 22),
        for (final t in templates)
          _summaryRow(t.name, '${formatWeekdays(t.weekdays)} · ${t.blocks.where((b) => !b.isFree).length} blocks'),
        if (freeDays.isNotEmpty) _summaryRow('Free days', freeDays.join(', ')),
        const SizedBox(height: 22),
        const Text('Reminders and Google Calendar sync arrive in the next update.',
            style: TextStyle(fontSize: 13, color: Brand.muted)),
        const SizedBox(height: 28),
        const QuoteText(text: 'Show up today. That is the whole trick.', source: '', color: Brand.ink, size: 18),
      ],
    );
  }

  String _firstBlockLine(List<DayTemplate> templates, DateTime now) {
    for (var offset = 0; offset < 8; offset++) {
      final day = now.add(Duration(days: offset));
      for (final t in templates) {
        if (!t.weekdays.contains(day.weekday)) continue;
        for (final b in t.sortedBlocks) {
          if (b.isFree) continue;
          if (offset == 0 && b.start <= minutesOfDay(now)) continue;
          final when = offset == 0 ? 'today' : (offset == 1 ? 'tomorrow' : weekdayName(day.weekday));
          return 'First up: ${b.name}, $when at ${formatTime(b.start)}.';
        }
      }
    }
    return 'Your blocks start on their own. Just show up.';
  }

  Widget _summaryRow(String label, String value) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white),
        ),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
            Text(value, style: const TextStyle(color: Brand.muted)),
          ],
        ),
      );
}

class _WelcomeArt extends StatelessWidget {
  const _WelcomeArt();

  @override
  Widget build(BuildContext context) {
    Widget bar(Color c, double w) => Container(
          width: w,
          height: 14,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(7)),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bar(BlockPalette.amber.dot, 120),
        bar(BlockPalette.teal.dot, 200),
        bar(BlockPalette.indigo.dot, 90),
        bar(Brand.cyan, 150),
      ],
    );
  }
}
