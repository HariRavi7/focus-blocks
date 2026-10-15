import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_state.dart';
import '../format.dart';
import '../schedule_engine.dart';
import '../theme.dart';
import 'common.dart';

/// Right-hand slide-in panel for adding tasks to the current block.
class AddTaskPanel extends StatelessWidget {
  const AddTaskPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Drawer(
      width: math.min(420.0, w * 0.92),
      backgroundColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(left: Radius.circular(24))),
      child: const ClearGlass(
        opacity: 0.9,
        radius: BorderRadius.horizontal(left: Radius.circular(24)),
        child: SafeArea(child: _PanelBody()),
      ),
    );
  }
}

class _PanelBody extends ConsumerStatefulWidget {
  const _PanelBody();

  @override
  ConsumerState<_PanelBody> createState() => _PanelBodyState();
}

enum _Pos { next, end }

enum _Over { extend, later, anyway }

class _PanelBodyState extends ConsumerState<_PanelBody> {
  final _title = TextEditingController();
  int _minutes = 15;
  _Pos _pos = _Pos.next;
  _Over _over = _Over.extend;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(todayProvider);
    final block = view?.snap.current;
    final template = view?.template;
    if (view == null || block == null || template == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _closeRow(context, 'Add a task', ''),
            const SizedBox(height: 24),
            const Text('No block is running right now. Add tasks to later blocks from Today\'s schedule.',
                style: TextStyle(color: Brand.muted, height: 1.4)),
          ],
        ),
      );
    }

    final pal = paletteFor(block);
    final tasks = block.state.tasks;
    final blockMin = block.minutes;
    final planned = tasks.fold<int>(0, (a, t) => a + t.minutes);
    final overBy = planned + _minutes - blockMin;
    final firstOpen = tasks.indexWhere((t) => !t.done);
    final canGoNext = firstOpen >= 0;
    final pos = canGoNext ? _pos : _Pos.end;

    // Where the new task lands.
    final order = <({String id, int minutes, bool done})>[
      for (final t in tasks) (id: t.id, minutes: t.minutes, done: t.done),
    ];
    const newId = '__new';
    final entry = (id: newId, minutes: _minutes, done: false);
    if (pos == _Pos.next) {
      order.insert(firstOpen + 1, entry);
    } else {
      order.add(entry);
    }
    var acc = block.start;
    var landStart = block.start;
    for (final o in order) {
      if (o.id == newId) {
        landStart = acc;
        break;
      }
      acc += o.minutes;
    }
    final landEnd = landStart + _minutes;
    final fitNote = overBy > 0
        ? 'Planned ${planned + _minutes} of $blockMin min · $overBy min over'
        : 'Planned ${planned + _minutes} of $blockMin min · ${-overBy} min open';
    final hasTitle = _title.text.trim().isNotEmpty;

    String buttonLabel() {
      if (overBy <= 0) return 'Add task';
      return switch (_over) {
        _Over.extend => 'Add and extend $overBy min',
        _Over.later => 'Save for next time',
        _Over.anyway => 'Add anyway',
      };
    }

    Future<void> confirm() async {
      if (!hasTitle || _saving) return;
      setState(() => _saving = true);
      final c = ref.read(appProvider.notifier);
      final title = _title.text.trim();
      final scaffold = Scaffold.of(context);
      String message;
      if (overBy > 0 && _over == _Over.later) {
        await c.saveForLater(block.id, title, _minutes);
        message = 'Saved for the next ${block.name}';
      } else {
        await c.addTask(block.id, title, _minutes, rightAfterCurrent: pos == _Pos.next);
        if (overBy > 0 && _over == _Over.extend) await c.extend(block.id, overBy);
        message = 'Added: $title';
      }
      if (!mounted) return;
      scaffold.closeEndDrawer();
      showToast(context, message);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 10, 0),
          child: _closeRow(context, 'Add to ${block.name}', '${formatRange(block.start, block.end)} · ${formatDuration(blockMin)}'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                label: fitNote,
                child: SizedBox(
                  height: 8,
                  child: Row(
                    children: [
                      for (var i = 0; i < order.length; i++) ...[
                        if (i > 0) const SizedBox(width: 3),
                        Expanded(
                          flex: math.max(1, order[i].minutes),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color: order[i].id == newId
                                  ? (overBy > 0 ? const Color(0xFFEA7A2E) : pal.dot)
                                  : pal.dot.withValues(alpha: order[i].done ? 0.55 : 0.28),
                            ),
                          ),
                        ),
                      ],
                      if (overBy < 0) ...[
                        const SizedBox(width: 3),
                        Expanded(
                          flex: -overBy,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color: Brand.line.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(fitNote,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500, color: overBy > 0 ? Brand.warn : Brand.muted)),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
            children: [
              if (tasks.isNotEmpty) ...[
                const SectionLabel('In this block'),
                const SizedBox(height: 6),
                for (final t in tasks)
                  _TaskLine(
                    key: ValueKey(t.id),
                    title: t.title,
                    minutes: t.minutes,
                    done: t.done,
                    color: pal.dot,
                    onLess: () => ref.read(appProvider.notifier).adjustTaskMinutes(block.id, t.id, -5),
                    onMore: () => ref.read(appProvider.notifier).adjustTaskMinutes(block.id, t.id, 5),
                    onRemove: () async {
                      final c = ref.read(appProvider.notifier);
                      final removed = await c.removeTask(block.id, t.id);
                      if (removed != null && context.mounted) {
                        showToast(context, 'Removed ${t.title}', onUndo: () => c.undoRemove(removed));
                      }
                    },
                  ),
                const SizedBox(height: 18),
              ],
              const SectionLabel('New task'),
              const SizedBox(height: 10),
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Task name', hintText: 'What needs doing?'),
                onSubmitted: (_) => confirm(),
              ),
              const SizedBox(height: 16),
              const Text('How long', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in const [5, 10, 15, 25, 45, 60])
                    ChoicePill(label: '$m min', selected: _minutes == m, onTap: () => setState(() => _minutes = m)),
                ],
              ),
              const SizedBox(height: 16),
              const Text('When', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (canGoNext)
                    ChoicePill(
                      label: 'Right after this one',
                      selected: pos == _Pos.next,
                      onTap: () => setState(() => _pos = _Pos.next),
                    ),
                  ChoicePill(label: 'At the end', selected: pos == _Pos.end, onTap: () => setState(() => _pos = _Pos.end)),
                ],
              ),
              const SizedBox(height: 10),
              Text('Lands at ${formatRange(landStart, landEnd)}', style: const TextStyle(fontSize: 13)),
              if (overBy > 0) ...[
                const SizedBox(height: 16),
                Text('This runs $overBy min past ${formatTime(block.end)}. What should happen?',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Brand.warn)),
                const SizedBox(height: 8),
                _OverOption(
                  label: 'Extend the block by $overBy min',
                  desc: previewExtend(template, view.record, block.id, overBy).describe,
                  selected: _over == _Over.extend,
                  onTap: () => setState(() => _over = _Over.extend),
                ),
                _OverOption(
                  label: 'Save it for the next ${block.name}',
                  desc: 'It waits for the next time this block runs',
                  selected: _over == _Over.later,
                  onTap: () => setState(() => _over = _Over.later),
                ),
                _OverOption(
                  label: 'Add it anyway',
                  desc: 'The block still ends at ${formatTime(block.end)}',
                  selected: _over == _Over.anyway,
                  onTap: () => setState(() => _over = _Over.anyway),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
          child: FilledButton(onPressed: hasTitle && !_saving ? confirm : null, child: Text(buttonLabel())),
        ),
      ],
    );
  }

  Widget _closeRow(BuildContext context, String title, String sub) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(sub, style: const TextStyle(fontSize: 13, color: Brand.muted)),
                ],
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: 'Close',
          onPressed: () => Scaffold.of(context).closeEndDrawer(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }
}

class _TaskLine extends StatelessWidget {
  final String title;
  final int minutes;
  final bool done;
  final Color color;
  final VoidCallback onLess;
  final VoidCallback onMore;
  final VoidCallback onRemove;
  const _TaskLine({
    super.key,
    required this.title,
    required this.minutes,
    required this.done,
    required this.color,
    required this.onLess,
    required this.onMore,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          if (done) ...[
            Icon(Icons.check_circle_rounded, size: 18, color: color),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: done ? Brand.muted : Brand.ink,
                decoration: done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (done)
            Text('$minutes min · done', style: const TextStyle(fontSize: 13, color: Brand.muted))
          else
            MinuteStepper(minutes: minutes, onLess: onLess, onMore: onMore, taskTitle: title),
          IconButton(
            tooltip: 'Remove $title',
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Brand.muted),
          ),
        ],
      ),
    );
  }
}

class _OverOption extends StatelessWidget {
  final String label;
  final String desc;
  final bool selected;
  final VoidCallback onTap;
  const _OverOption({required this.label, required this.desc, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? Brand.cyanSoft : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: selected ? Brand.cyanDeep : const Color(0xFFD6DDE1)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(desc, style: const TextStyle(fontSize: 13, color: Brand.muted)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
