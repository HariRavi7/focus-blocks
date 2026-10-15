import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_state.dart';
import '../format.dart';
import '../quotes.dart';
import '../schedule_engine.dart';
import '../theme.dart';
import 'common.dart';
import 'sheets.dart';

/// The color the screen glows in: the current block, else the next one.
Color backdropColorFor(TodayView? v) {
  final b = v?.snap.current ?? v?.snap.next;
  if (b == null) return Brand.cyan;
  return paletteFor(b).dot;
}

/// One segment per task plus the open time left over.
List<({int minutes, double fill, bool open})> blockSegments(PlannedBlock b, int now) {
  final slots = taskSlots(b);
  final current = currentTaskSlot(b);
  final out = <({int minutes, double fill, bool open})>[];
  var planned = 0;
  for (final s in slots) {
    planned += s.task.minutes;
    var fill = 0.0;
    if (s.task.done) {
      fill = 1;
    } else if (current != null && s.task.id == current.task.id && s.task.minutes > 0) {
      fill = ((now - s.start) / s.task.minutes).clamp(0.0, 1.0).toDouble();
    }
    out.add((minutes: s.task.minutes, fill: fill, open: false));
  }
  final open = b.minutes - planned;
  if (open > 0) {
    final openStart = b.start + planned;
    final fill = current == null ? ((now - openStart) / open).clamp(0.0, 1.0).toDouble() : 0.0;
    out.add((minutes: open, fill: fill, open: true));
  }
  if (out.isEmpty) out.add((minutes: 1, fill: 1.0, open: true));
  return out;
}

class NowView extends ConsumerStatefulWidget {
  final bool wide;
  final VoidCallback onOpenSchedule;
  final VoidCallback onOpenProgress;
  final VoidCallback onOpenTemplates;
  const NowView({
    super.key,
    required this.wide,
    required this.onOpenSchedule,
    required this.onOpenProgress,
    required this.onOpenTemplates,
  });

  @override
  ConsumerState<NowView> createState() => _NowViewState();
}

class _NowViewState extends ConsumerState<NowView> {
  Quote? _quote;
  String? _quoteKey;

  Quote _quoteFor(TodayView v) {
    final key = '${v.snap.phase.name}-${v.snap.current?.id}-${v.snap.next?.id}';
    if (key != _quoteKey || _quote == null) {
      _quoteKey = key;
      _quote = randomQuote(ref.read(appProvider).valueOrNull?.customQuotes ?? const []);
    }
    return _quote!;
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(todayProvider);
    if (view == null) return const SizedBox.shrink();
    final quote = _quoteFor(view);

    final Widget card = switch (view.snap.phase) {
      Phase.running => _RunningCard(view: view, block: view.snap.current!, quote: quote),
      Phase.ended => _EndedCard(view: view, block: view.snap.current!),
      Phase.upNext => _InfoCard(
          color: paletteFor(view.snap.next!).dot,
          ink: paletteFor(view.snap.next!).ink,
          chip: 'UP NEXT',
          title: view.snap.next!.name,
          line: 'Starts at ${formatTime(view.snap.next!.start)}',
          quote: quote,
        ),
      Phase.dayDone => _InfoCard(
          color: Brand.cyan,
          ink: Brand.ink,
          chip: 'DONE FOR TODAY',
          title: "That's the day",
          line: '${view.snap.closedCount} of ${view.snap.focusCount} blocks reviewed',
          quote: quote,
        ),
      Phase.empty => _InfoCard(
          color: Brand.cyan,
          ink: Brand.ink,
          chip: 'FREE DAY',
          title: 'No template today',
          line: 'Enjoy the day off.',
          quote: quote,
          action: TextButton(onPressed: widget.onOpenTemplates, child: const Text('Edit templates')),
        ),
    };

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formatHeaderDate(view.date), style: const TextStyle(fontSize: 13, color: Brand.muted)),
                const SizedBox(height: 4),
                _StreakChip(streak: view.streak, onTap: widget.onOpenProgress),
              ],
            ),
          ),
          if (!widget.wide)
            ClearGlass(
              radius: BorderRadius.circular(999),
              child: InkWell(
                onTap: widget.onOpenSchedule,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.format_list_bulleted_rounded, size: 16),
                      SizedBox(width: 8),
                      Text("Today's schedule", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 560, maxHeight: widget.wide ? 640 : double.infinity),
              child: Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), child: card),
            ),
          ),
        ),
      ],
    );
  }
}

class _StreakChip extends StatelessWidget {
  final int streak;
  final VoidCallback onTap;
  const _StreakChip({required this.streak, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$streak-day streak. Open progress',
      child: Material(
        color: Brand.cyanSoft,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.local_fire_department_outlined, size: 14, color: Brand.cyanDeep),
                const SizedBox(width: 6),
                Text('$streak-day streak',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Brand.cyanDeep)),
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right_rounded, size: 14, color: Brand.cyanDeep),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The big Now card while a block runs.
class _RunningCard extends ConsumerWidget {
  final TodayView view;
  final PlannedBlock block;
  final Quote quote;
  const _RunningCard({required this.view, required this.block, required this.quote});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteFor(block);
    final now = view.snap.now;
    final left = block.end - now;
    final current = currentTaskSlot(block);
    final ink = pal.ink;

    return GlassCard(
      tint: pal.dot,
      padding: const EdgeInsets.fromLTRB(24, 12, 12, 12),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: ink),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                tooltip: 'Add a task to ${block.name}',
                onPressed: () => Scaffold.of(context).openEndDrawer(),
                icon: Icon(Icons.add_rounded, color: ink),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const StatusChip('NOW'),
                    const SizedBox(height: 16),
                    Text(
                      block.name,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: -1.2, height: 1.05, color: ink),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.schedule_rounded, size: 20, color: ink),
                        const SizedBox(width: 8),
                        Text('Focus until ${formatTime(block.end)}',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: ink)),
                      ],
                    ),
                    const SizedBox(height: 28),
                    SegmentBar(segments: blockSegments(block, now), color: pal.dot),
                    const SizedBox(height: 10),
                    Text('${left < 0 ? 0 : left} min left', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: ink)),
                    const SizedBox(height: 32),
                    if (current != null)
                      _InProgressRow(block: block, slot: current, now: now, color: pal.dot, ink: ink)
                    else ...[
                      Text('Finishing the block is the task.', style: TextStyle(fontSize: 15, color: ink)),
                      const SizedBox(height: 18),
                      QuoteText(text: quote.text, source: quote.source, color: ink),
                    ],
                  ],
                ),
                  ),
                ),
              ),
            ),
            Center(
              child: PopupMenuButton<String>(
                tooltip: 'More options for this block',
                icon: Icon(Icons.more_horiz_rounded, color: ink),
                position: PopupMenuPosition.over,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                color: Colors.white,
                onSelected: (v) {
                  if (v == 'finish') showReviewSheet(context, block.id);
                  if (v == 'skip') showSkipSheet(context, block.id);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'finish', child: Text('Finish early')),
                  PopupMenuItem(value: 'skip', child: Text('Skip this block', style: TextStyle(color: Brand.warn))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "In progress: <task>" with the glass tick and a small time bar.
class _InProgressRow extends ConsumerWidget {
  final PlannedBlock block;
  final TaskSlot slot;
  final int now;
  final Color color;
  final Color ink;
  const _InProgressRow({required this.block, required this.slot, required this.now, required this.color, required this.ink});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = slot.task;
    final over = now - slot.end;
    final isOver = over > 0;
    final fill = task.minutes == 0 ? 1.0 : ((now - slot.start) / task.minutes).clamp(0.0, 1.0).toDouble();
    final barColor = isOver ? const Color(0xFFEA7A2E) : color;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GlassTick(
          key: ValueKey(task.id),
          color: color,
          done: false,
          label: 'Mark ${task.title} done',
          onDone: () {
            ref.read(appProvider.notifier).toggleTask(block.id, task.id);
            showToast(context, 'Done: ${task.title}');
          },
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'In progress: ', style: TextStyle(fontWeight: FontWeight.w500)),
                  TextSpan(text: task.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
                style: TextStyle(fontSize: 16, color: ink),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Semantics(
                label: isOver ? '$over minutes over' : '${slot.end - now} minutes left on this task',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    width: 96,
                    height: 3,
                    child: Stack(
                      children: [
                        Positioned.fill(child: ColoredBox(color: barColor.withValues(alpha: 0.2))),
                        FractionallySizedBox(widthFactor: fill, heightFactor: 1, child: ColoredBox(color: barColor)),
                      ],
                    ),
                  ),
                ),
              ),
              if (isOver) ...[
                const SizedBox(height: 3),
                Text('$over min over', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Brand.warn)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Shown when a block's time is up but the sheet was dismissed.
class _EndedCard extends StatelessWidget {
  final TodayView view;
  final PlannedBlock block;
  const _EndedCard({required this.view, required this.block});

  @override
  Widget build(BuildContext context) {
    final pal = paletteFor(block);
    return _InfoCard(
      color: pal.dot,
      ink: pal.ink,
      chip: "TIME'S UP",
      title: block.name,
      line: 'Ended at ${formatTime(block.end)}',
      action: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: SizedBox(
          width: 220,
          child: FilledButton(onPressed: () => showTimesUpSheet(context, block.id), child: const Text('Wrap up')),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final Color color;
  final Color ink;
  final String chip;
  final String title;
  final String line;
  final Quote? quote;
  final Widget? action;
  const _InfoCard({
    required this.color,
    required this.ink,
    required this.chip,
    required this.title,
    required this.line,
    this.quote,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      tint: color,
      child: Center(
        child: SingleChildScrollView(
          child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: StatusChip(chip)),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: -1.2, height: 1.05, color: ink)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.schedule_rounded, size: 20, color: ink),
              const SizedBox(width: 8),
              Flexible(
                child: Text(line,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: ink)),
              ),
            ],
          ),
          if (quote != null) ...[
            const SizedBox(height: 24),
            QuoteText(text: quote!.text, source: quote!.source, color: ink),
          ],
          if (action != null) ...[const SizedBox(height: 16), Center(child: action!)],
        ],
          ),
        ),
      ),
    );
  }
}
