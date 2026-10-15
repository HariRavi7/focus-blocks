import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import '../schedule_engine.dart';
import '../theme.dart';
import 'common.dart';
import 'now_view.dart';
import 'templates_screen.dart';

/// Phone: Today's schedule as its own screen.
class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(todayProvider);
    return Scaffold(
      body: GlassBackdrop(
        color: backdropColorFor(view),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 20, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.chevron_left_rounded),
                    label: const Text('Now', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  ),
                ),
              ),
              const Expanded(child: ScheduleList(showTitle: true)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The list of today's blocks. Tap a card once for its time and color,
/// tap again for its tasks.
class ScheduleList extends ConsumerStatefulWidget {
  final bool showTitle;
  final bool compact;
  const ScheduleList({super.key, this.showTitle = false, this.compact = false});

  @override
  ConsumerState<ScheduleList> createState() => _ScheduleListState();
}

class _ScheduleListState extends ConsumerState<ScheduleList> {
  String? _openId;
  int _level = 0;

  void _tap(PlannedBlock b) {
    setState(() {
      if (_openId != b.id) {
        _openId = b.id;
        _level = 1;
      } else if (_level == 1 && !b.isFree) {
        _level = 2;
      } else {
        _openId = null;
        _level = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(todayProvider);
    if (view == null) return const SizedBox.shrink();
    final snap = view.snap;
    final t = view.template;
    final summary = t == null
        ? 'Free day · no template runs today'
        : '${t.name} template · ${snap.closedCount} of ${snap.focusCount} blocks reviewed';

    return ListView(
      padding: EdgeInsets.fromLTRB(widget.compact ? 16 : 20, 4, widget.compact ? 16 : 20, 24),
      children: [
        if (widget.showTitle) ...[
          const Text("Today's schedule", style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.6)),
          const SizedBox(height: 4),
        ] else ...[
          const SizedBox(height: 18),
          const Text("Today's schedule", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
        ],
        Row(
          children: [
            Expanded(child: Text(summary, style: const TextStyle(fontSize: 13, color: Brand.muted))),
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TemplatesScreen())),
              child: const Text('Templates', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (snap.blocks.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Text('Nothing planned. Days without a template are free days.',
                style: TextStyle(color: Brand.muted, height: 1.4)),
          ),
        for (final b in snap.blocks)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _BlockCard(
              block: b,
              view: view,
              level: _openId == b.id ? _level : 0,
              onTap: () => _tap(b),
            ),
          ),
      ],
    );
  }
}

class _BlockCard extends ConsumerStatefulWidget {
  final PlannedBlock block;
  final TodayView view;
  final int level;
  final VoidCallback onTap;
  const _BlockCard({required this.block, required this.view, required this.level, required this.onTap});

  @override
  ConsumerState<_BlockCard> createState() => _BlockCardState();
}

class _BlockCardState extends ConsumerState<_BlockCard> {
  final _newTask = TextEditingController();

  @override
  void dispose() {
    _newTask.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final title = _newTask.text.trim();
    if (title.isEmpty) return;
    _newTask.clear();
    await ref.read(appProvider.notifier).addTask(widget.block.id, title, 15);
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.block;
    final snap = widget.view.snap;
    final pal = paletteFor(b);
    final isRunning = snap.phase == Phase.running && snap.current?.id == b.id;
    final result = b.state.result;

    Widget? status;
    if (isRunning) {
      status = _tag('Now · until ${formatTime(b.end)}', pal.ink, pal.dot.withValues(alpha: 0.18));
    } else if (result == BlockResult.done) {
      status = _tag('Done', const Color(0xFF1B5952), const Color(0xFFE5F5F2));
    } else if (result == BlockResult.partly) {
      status = _tag('Partly', const Color(0xFF1B5952), const Color(0xFFE5F5F2));
    } else if (result == BlockResult.no) {
      status = _tag('Not met', Brand.muted, Colors.white.withValues(alpha: 0.7));
    } else if (result == BlockResult.skipped) {
      status = _tag('Skipped', Brand.warn, const Color(0xFFFFF1E8));
    } else if (b.isFree && b.usedByExtension > 0) {
      status = Text(b.minutes == 0 ? 'Used by extension' : '${b.usedByExtension} min used by extension',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Brand.muted));
    } else if (!b.isFree && b.state.tasks.isNotEmpty) {
      final n = b.state.tasks.length;
      status = Text('$n ${n == 1 ? 'task' : 'tasks'}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Brand.muted));
    }

    final fill = b.isFree ? Colors.white.withValues(alpha: 0.32) : pal.tint.withValues(alpha: 0.42);
    final border = isRunning ? pal.dot.withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.75);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: border, width: isRunning ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: b.isFree ? Colors.transparent : pal.dot,
                                  border: b.isFree ? Border.all(color: Brand.line, width: 1.5) : null,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  b.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: b.isFree ? FontWeight.w500 : FontWeight.w700,
                                    color: b.isFree ? Brand.muted : Brand.ink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.only(left: 20),
                            child: Text(formatRange(b.start, b.end),
                                style: const TextStyle(fontSize: 13, color: Brand.muted)),
                          ),
                        ],
                      ),
                    ),
                    if (status != null) Padding(padding: const EdgeInsets.only(left: 8), child: status),
                  ],
                ),
              ),
            ),
            if (widget.level >= 1) _levelOne(b),
            if (widget.level >= 2) _levelTwo(b, pal),
          ],
        ),
      ),
      ),
    );
  }

  Widget _tag(String text, Color fg, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
      );

  Widget _levelOne(PlannedBlock b) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 0, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${formatDuration(b.minutes)} · ${b.isFree ? 'Free time' : 'Focus'}',
              style: const TextStyle(fontSize: 13, color: Brand.muted)),
          if (!b.isFree) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('Color', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(width: 10),
                for (final c in BlockColor.values) _swatch(b, c),
              ],
            ),
          ],
          if (widget.level == 1) ...[
            const SizedBox(height: 8),
            Text(b.isFree ? 'Free time has no tasks.' : 'Tap the card again to break it into tasks.',
                style: const TextStyle(fontSize: 12, color: Brand.muted)),
          ],
        ],
      ),
    );
  }

  Widget _swatch(PlannedBlock b, BlockColor c) {
    final selected = b.block.color == c;
    final pal = BlockPalette.of(c, b.block.start);
    final label = c == BlockColor.auto ? 'Auto (${pal.label})' : pal.label;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Color $label',
      child: InkResponse(
        radius: 20,
        onTap: () => ref.read(appProvider.notifier).setBlockColor(b.id, c),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: pal.dot,
              border: Border.all(color: selected ? Brand.ink : Colors.white, width: selected ? 2 : 1.5),
            ),
            child: c == BlockColor.auto
                ? const Center(
                    child: Text('A', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)))
                : null,
          ),
        ),
      ),
    );
  }

  Widget _levelTwo(PlannedBlock b, BlockPalette pal) {
    final c = ref.read(appProvider.notifier);
    final tasks = b.state.tasks;
    final planned = tasks.fold<int>(0, (a, t) => a + t.minutes);
    final over = planned > b.minutes;
    final note = over
        ? 'Tasks add up to ${formatDuration(planned)}, ${planned - b.minutes} min more than the block'
        : 'Planned ${formatDuration(planned)} of ${formatDuration(b.minutes)}'
            '${planned < b.minutes ? ' · ${b.minutes - planned} min open' : ''}';
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: Text('No tasks yet. Finishing the block is the task.',
                  style: TextStyle(fontSize: 13, color: Brand.muted)),
            ),
          for (final t in tasks)
            Row(
              key: ValueKey(t.id),
              children: [
                GlassTick(
                  color: pal.dot,
                  done: t.done,
                  size: 24,
                  label: t.done ? 'Mark ${t.title} not done' : 'Mark ${t.title} done',
                  onDone: () => c.toggleTask(b.id, t.id),
                  onUndo: () => c.toggleTask(b.id, t.id),
                ),
                Expanded(
                  child: Text(
                    t.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      color: t.done ? Brand.muted : Brand.ink,
                      decoration: t.done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                MinuteStepper(
                  minutes: t.minutes,
                  taskTitle: t.title,
                  onLess: () => c.adjustTaskMinutes(b.id, t.id, -5),
                  onMore: () => c.adjustTaskMinutes(b.id, t.id, 5),
                ),
                IconButton(
                  tooltip: 'Remove ${t.title}',
                  icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Brand.muted),
                  onPressed: () async {
                    final removed = await c.removeTask(b.id, t.id);
                    if (removed != null && mounted) {
                      showToast(context, 'Removed ${t.title}', onUndo: () => c.undoRemove(removed));
                    }
                  },
                ),
              ],
            ),
          if (tasks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
              child: Text(note,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: over ? Brand.warn : Brand.muted)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newTask,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'Add a task (15 min)', isDense: true),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
                  onPressed: _add,
                  child: const Text('Add'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
