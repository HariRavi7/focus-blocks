import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import '../schedule_engine.dart';
import '../theme.dart';
import 'common.dart';

String _newId(String prefix) => '$prefix${DateTime.now().microsecondsSinceEpoch}';

/// All templates, and which days they run on.
class TemplatesScreen extends ConsumerWidget {
  final bool embedded;
  const TemplatesScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appProvider).valueOrNull ?? const AppData();
    final assigned = {for (final t in data.templates) ...t.weekdays};
    final freeDays = [for (var d = 1; d <= 7; d++) if (!assigned.contains(d)) d];

    final body = ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const Text('Templates', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.6)),
        const SizedBox(height: 4),
        const Text('Each day runs one template. Days without one are free days.',
            style: TextStyle(fontSize: 14, color: Brand.muted, height: 1.4)),
        const SizedBox(height: 18),
        for (final t in data.templates)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _TemplateCard(
              template: t,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TemplateEditor(template: t))),
            ),
          ),
        if (freeDays.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14, top: 2),
            child: Text('Free days: ${freeDays.map((d) => weekdayShort[d - 1]).join(', ')}',
                style: const TextStyle(fontSize: 13, color: Brand.muted)),
          ),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TemplateEditor())),
          icon: const Icon(Icons.add_rounded),
          label: const Text('New template'),
        ),
      ],
    );

    if (embedded) return SafeArea(child: body);
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.white, surfaceTintColor: Colors.white, elevation: 0),
      body: body,
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final DayTemplate template;
  final VoidCallback onTap;
  const _TemplateCard({required this.template, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final blocks = template.sortedBlocks;
    final focus = blocks.where((b) => !b.isFree).toList();
    final span = blocks.isEmpty ? 'No blocks yet' : formatRange(blocks.first.start, blocks.last.end);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE2E8EB))),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(template.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                  Text(formatWeekdays(template.weekdays),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Brand.cyanDeep)),
                ],
              ),
              const SizedBox(height: 4),
              Text('${focus.length} ${focus.length == 1 ? 'block' : 'blocks'} · $span',
                  style: const TextStyle(fontSize: 13, color: Brand.muted)),
              const SizedBox(height: 12),
              TimelineStrip(blocks: blocks),
            ],
          ),
        ),
      ),
    );
  }
}

/// A thin strip showing a day's blocks from 6 AM to midnight.
class TimelineStrip extends StatelessWidget {
  final List<TemplateBlock> blocks;
  const TimelineStrip({super.key, required this.blocks});

  @override
  Widget build(BuildContext context) {
    const dayStart = 360;
    const dayEnd = 1440;
    final sorted = [...blocks]..sort((a, b) => a.start.compareTo(b.start));
    final children = <Widget>[];
    var cursor = dayStart;
    for (final b in sorted) {
      final s = b.start < dayStart ? dayStart : b.start;
      if (b.end <= s) continue;
      if (s > cursor) children.add(Expanded(flex: s - cursor, child: const SizedBox()));
      final start = s < cursor ? cursor : s;
      if (b.end > start) {
        children.add(Expanded(
          flex: b.end - start,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: b.isFree ? Brand.line.withValues(alpha: 0.45) : paletteForTemplateBlock(b).dot,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ));
        cursor = b.end;
      }
    }
    if (cursor < dayEnd) children.add(Expanded(flex: dayEnd - cursor, child: const SizedBox()));
    return Container(
      height: 8,
      decoration: BoxDecoration(color: const Color(0xFFF1F4F6), borderRadius: BorderRadius.circular(4)),
      child: Row(children: children),
    );
  }
}

/// Edit a template: name, days, and its blocks.
class TemplateEditor extends ConsumerStatefulWidget {
  final DayTemplate? template;
  const TemplateEditor({super.key, this.template});

  @override
  ConsumerState<TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends ConsumerState<TemplateEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.template?.name ?? '');
  late Set<int> _days = {...?widget.template?.weekdays};
  late List<TemplateBlock> _blocks = [...?widget.template?.blocks];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final id = widget.template?.id ?? _newId('tpl');
    final t = DayTemplate(
      id: id,
      name: _name.text.trim().isEmpty ? 'Untitled' : _name.text.trim(),
      weekdays: _days.toList()..sort(),
      blocks: _blocks,
    );
    final nav = Navigator.of(context);
    await ref.read(appProvider.notifier).saveTemplate(t);
    nav.pop();
  }

  Future<void> _delete() async {
    final t = widget.template;
    if (t == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete ${t.name}?'),
        content: const Text('Days that used it become free days. Past days keep their history.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Delete', style: TextStyle(color: Brand.warn)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final nav = Navigator.of(context);
    await ref.read(appProvider.notifier).deleteTemplate(t.id);
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appProvider).valueOrNull ?? const AppData();
    final selfId = widget.template?.id;
    String? ownerOf(int d) {
      for (final t in data.templates) {
        if (t.id != selfId && t.weekdays.contains(d)) return t.name;
      }
      return null;
    }

    final moved = [
      for (final d in _days)
        if (ownerOf(d) != null) '${weekdayShort[d - 1]} (from ${ownerOf(d)})',
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: Text(widget.template == null ? 'New template' : 'Edit template'),
        actions: [
          if (widget.template != null)
            IconButton(tooltip: 'Delete template', onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded)),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Weekday'),
                ),
                const SizedBox(height: 18),
                const Text('Runs on', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                WeekdayPicker(
                  selected: _days,
                  onToggle: (d) => setState(() {
                    _days = {..._days};
                    if (!_days.remove(d)) _days.add(d);
                  }),
                ),
                if (moved.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Saving moves ${moved.join(', ')} to this template.',
                      style: const TextStyle(fontSize: 13, color: Brand.muted)),
                ],
                const SizedBox(height: 22),
                const SectionLabel('Blocks'),
                const SizedBox(height: 8),
                BlockListEditor(blocks: _blocks, onChanged: (b) => setState(() => _blocks = b)),
                const SizedBox(height: 24),
                FilledButton(onPressed: _save, child: const Text('Save template')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Seven round day toggles.
class WeekdayPicker extends StatelessWidget {
  final Set<int> selected;
  final ValueChanged<int> onToggle;
  const WeekdayPicker({super.key, required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var d = 1; d <= 7; d++)
          Semantics(
            button: true,
            selected: selected.contains(d),
            label: weekdayName(d),
            child: Material(
              color: selected.contains(d) ? Brand.cyanDeep : Colors.white,
              shape: CircleBorder(side: BorderSide(color: selected.contains(d) ? Brand.cyanDeep : Brand.line)),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onToggle(d),
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: Center(
                    child: Text(
                      weekdayLetter[d - 1],
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: selected.contains(d) ? Colors.white : Brand.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The blocks of a template, with gaps you can mark as free time.
class BlockListEditor extends StatelessWidget {
  final List<TemplateBlock> blocks;
  final ValueChanged<List<TemplateBlock>> onChanged;
  const BlockListEditor({super.key, required this.blocks, required this.onChanged});

  Future<void> _edit(BuildContext context, TemplateBlock? existing, {int? start, int? end, BlockKind? kind}) async {
    final r = await showBlockForm(context, blocks: blocks, existing: existing, start: start, end: end, kind: kind);
    if (r == null) return;
    final list = blocks.where((b) => b.id != existing?.id).toList();
    if (r.block != null) list.add(r.block!);
    list.sort((a, b) => a.start.compareTo(b.start));
    onChanged(list);
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...blocks]..sort((a, b) => a.start.compareTo(b.start));
    final rows = <Widget>[];
    for (var i = 0; i < sorted.length; i++) {
      final b = sorted[i];
      rows.add(_BlockRow(block: b, onTap: () => _edit(context, b)));
      if (i + 1 < sorted.length) {
        final gap = sorted[i + 1].start - b.end;
        if (gap > 0) {
          rows.add(Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text('${formatDuration(gap)} gap · ${formatRange(b.end, sorted[i + 1].start)}',
                      style: const TextStyle(fontSize: 13, color: Brand.muted)),
                ),
                TextButton(
                  onPressed: () {
                    final list = [
                      ...blocks,
                      TemplateBlock(
                        id: _newId('b'),
                        name: 'Free time',
                        start: b.end,
                        end: sorted[i + 1].start,
                        kind: BlockKind.free,
                      ),
                    ]..sort((a, c) => a.start.compareTo(c.start));
                    onChanged(list);
                  },
                  child: const Text('Mark as free'),
                ),
              ],
            ),
          ));
        }
      }
    }
    final lastEnd = sorted.isEmpty ? 540 : sorted.last.end;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sorted.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('No blocks yet.', style: TextStyle(color: Brand.muted)),
          ),
        ...rows,
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: lastEnd >= 1440 ? null : () => _edit(context, null, start: lastEnd),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add a block'),
        ),
      ],
    );
  }
}

class _BlockRow extends StatelessWidget {
  final TemplateBlock block;
  final VoidCallback onTap;
  const _BlockRow({required this.block, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pal = paletteForTemplateBlock(block);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: block.isFree ? Colors.white : pal.tint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: block.isFree ? const Color(0xFFE2E8EB) : pal.edge),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: block.isFree ? Colors.transparent : pal.dot,
                    border: block.isFree ? Border.all(color: Brand.line, width: 1.5) : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(block.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: block.isFree ? FontWeight.w500 : FontWeight.w700,
                        color: block.isFree ? Brand.muted : pal.ink,
                      )),
                ),
                Text(formatRange(block.start, block.end),
                    style: TextStyle(fontSize: 13, color: block.isFree ? Brand.muted : pal.ink)),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, size: 18, color: block.isFree ? Brand.muted : pal.ink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Block form

class BlockEdit {
  /// The saved block, or null when the block was deleted.
  final TemplateBlock? block;
  const BlockEdit(this.block);
}

Future<BlockEdit?> showBlockForm(
  BuildContext context, {
  required List<TemplateBlock> blocks,
  TemplateBlock? existing,
  int? start,
  int? end,
  BlockKind? kind,
}) {
  return showModalBottomSheet<BlockEdit>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: Brand.ink.withValues(alpha: 0.22),
    builder: (_) => _BlockForm(blocks: blocks, existing: existing, start: start, end: end, kind: kind),
  );
}

class _BlockForm extends StatefulWidget {
  final List<TemplateBlock> blocks;
  final TemplateBlock? existing;
  final int? start;
  final int? end;
  final BlockKind? kind;
  const _BlockForm({required this.blocks, this.existing, this.start, this.end, this.kind});

  @override
  State<_BlockForm> createState() => _BlockFormState();
}

class _BlockFormState extends State<_BlockForm> {
  late final TextEditingController _name = TextEditingController(text: widget.existing?.name ?? '');
  late int _start = widget.existing?.start ?? widget.start ?? 540;
  late int _length = widget.existing?.minutes ?? ((widget.end ?? (_start + 60)) - _start);
  late BlockKind _kind = widget.existing?.kind ?? widget.kind ?? BlockKind.focus;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: _start ~/ 60, minute: _start % 60));
    if (t != null) setState(() => _start = t.hour * 60 + t.minute);
  }

  Future<void> _pickEnd() async {
    final e = _start + _length;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (e ~/ 60) % 24, minute: e % 60),
    );
    if (t == null) return;
    var end = t.hour * 60 + t.minute;
    if (end == 0) end = 1440;
    if (end > _start) setState(() => _length = end - _start);
  }

  @override
  Widget build(BuildContext context) {
    final end = _start + _length;
    final clash = findOverlap(widget.blocks, _start, end, exceptId: widget.existing?.id);
    final pastMidnight = end > 1440;
    final name = _name.text.trim();
    final canSave = clash == null && !pastMidnight && _length > 0 && (name.isNotEmpty || _kind == BlockKind.free);
    final note = pastMidnight
        ? 'Ends after midnight. Blocks stop at 12:00 AM.'
        : clash != null
            ? 'Overlaps ${clash.name} (${formatRange(clash.start, clash.end)})'
            : formatRange(_start, end);

    return SheetFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.existing == null ? 'Add a block' : 'Edit block',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            children: [
              ChoicePill(label: 'Focus', selected: _kind == BlockKind.focus, onTap: () => setState(() => _kind = BlockKind.focus)),
              ChoicePill(label: 'Free time', selected: _kind == BlockKind.free, onTap: () => setState(() => _kind = BlockKind.free)),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Block name',
              hintText: _kind == BlockKind.free ? 'Free time' : 'e.g. Reading',
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: _pickStart, child: Text('Starts ${formatTime(_start)}')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(onPressed: _pickEnd, child: Text('Ends ${formatTime(end)}')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in const [15, 30, 60, 90, 120, 180])
                ChoicePill(label: formatDuration(m), selected: _length == m, onTap: () => setState(() => _length = m)),
            ],
          ),
          const SizedBox(height: 10),
          Text(note,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: (clash != null || pastMidnight) ? Brand.warn : Brand.muted)),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: canSave
                ? () {
                    final b = TemplateBlock(
                      id: widget.existing?.id ?? _newId('b'),
                      name: name.isEmpty ? 'Free time' : name,
                      start: _start,
                      end: end,
                      kind: _kind,
                      color: widget.existing?.color ?? BlockColor.auto,
                    );
                    Navigator.of(context).pop(BlockEdit(b));
                  }
                : null,
            child: Text(widget.existing == null ? 'Add block' : 'Save block'),
          ),
          if (widget.existing != null) ...[
            const SizedBox(height: 4),
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: Brand.warn),
              onPressed: () => Navigator.of(context).pop(const BlockEdit(null)),
              child: const Text('Delete block'),
            ),
          ],
        ],
      ),
    );
  }
}
