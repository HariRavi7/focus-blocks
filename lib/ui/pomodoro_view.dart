import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_state.dart';
import '../format.dart';
import '../pomodoro.dart';
import '../schedule_engine.dart';
import '../theme.dart';
import '../platform/notifications.dart';
import 'common.dart';

/// Focus is cyan, short breaks teal, long breaks indigo.
BlockPalette pomodoroPalette(PomodoroPhase p) => switch (p) {
      PomodoroPhase.focus => BlockPalette.cyan,
      PomodoroPhase.shortBreak => BlockPalette.teal,
      PomodoroPhase.longBreak => BlockPalette.indigo,
    };

/// The block and task running right now, for linking a new round.
({String? blockId, String? blockName, String? taskId, String? taskTitle}) currentFocus(TodayView? v) {
  final b = v?.snap.phase == Phase.running ? v?.snap.current : null;
  if (b == null) return (blockId: null, blockName: null, taskId: null, taskTitle: null);
  final slot = currentTaskSlot(b);
  return (blockId: b.id, blockName: b.name, taskId: slot?.task.id, taskTitle: slot?.task.title);
}

/// Starts a focus round tied to the current block and task.
Future<void> startPomodoroNow(WidgetRef ref, {String label = ''}) async {
  final f = currentFocus(ref.read(todayProvider));
  await ref.read(appProvider.notifier).startPomodoro(
        label: label,
        blockId: f.blockId,
        blockName: f.blockName,
        taskId: f.taskId,
        taskTitle: f.taskTitle,
      );
  // The alert at the end of the round needs permission, even with block
  // reminders turned off.
  await NotificationService.instance.requestPermission();
}

/// The Pomodoro timer: a ring countdown, controls, and today's rounds.
class PomodoroScreen extends ConsumerWidget {
  final bool embedded;
  const PomodoroScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(pomodoroProvider);
    if (v == null) return const SizedBox.shrink();
    final phase = v.timer?.phase ?? PomodoroPhase.focus;
    final pal = pomodoroPalette(phase);

    final body = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () => _toggle(ref, v),
      },
      child: Focus(
        autofocus: true,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Pomodoro', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.6)),
                ),
                IconButton(
                  tooltip: 'Pomodoro settings',
                  onPressed: () => showPomodoroSettings(context),
                  icon: const Icon(Icons.tune_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${v.settings.focusMinutes} min focus, ${v.settings.shortBreakMinutes} min break. '
              'After ${v.settings.rounds} rounds, a ${v.settings.longBreakMinutes} min break.',
              style: const TextStyle(fontSize: 15, color: Brand.muted),
            ),
            const SizedBox(height: 18),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: _TimerCard(view: v, palette: pal),
              ),
            ),
            const SizedBox(height: 14),
            _TodayPanel(view: v),
          ],
        ),
      ),
    );

    if (embedded) return SafeArea(child: body);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent, surfaceTintColor: Colors.transparent, elevation: 0),
      body: GlassBackdrop(color: pal.dot, child: SafeArea(child: body)),
    );
  }

  static void _toggle(WidgetRef ref, PomodoroView v) {
    if (v.timer == null) {
      startPomodoroNow(ref);
    } else {
      ref.read(appProvider.notifier).togglePomodoro();
    }
  }
}

class _TimerCard extends ConsumerStatefulWidget {
  final PomodoroView view;
  final BlockPalette palette;
  const _TimerCard({required this.view, required this.palette});

  @override
  ConsumerState<_TimerCard> createState() => _TimerCardState();
}

class _TimerCardState extends ConsumerState<_TimerCard> {
  final _label = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.view;
    final t = v.timer;
    final pal = widget.palette;
    final ink = pal.ink;
    final c = ref.read(appProvider.notifier);
    final phase = t?.phase ?? PomodoroPhase.focus;
    final left = v.secondsLeft;
    final progress = t?.progress(v.now) ?? 0.0;
    final focus = currentFocus(ref.watch(todayProvider));
    final hint = focus.taskTitle ?? focus.blockName ?? 'What are you working on?';
    final subject = t == null ? '' : pomodoroSubject(t);

    final String chip;
    if (t == null) {
      chip = 'READY';
    } else if (!t.running && t.started) {
      chip = 'PAUSED';
    } else {
      chip = phase.label.toUpperCase();
    }

    Widget primary() {
      if (t == null) {
        return FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: pal.ink),
          onPressed: () => startPomodoroNow(ref, label: _label.text),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text('Start ${v.settings.focusMinutes} min focus'),
        );
      }
      if (t.running) {
        return FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: pal.ink),
          onPressed: c.pausePomodoro,
          icon: const Icon(Icons.pause_rounded),
          label: const Text('Pause'),
        );
      }
      final what = t.started ? 'Resume' : (phase.isBreak ? 'Start break' : 'Start focus');
      return FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: pal.ink),
        onPressed: () => startPomodoroNow(ref),
        icon: const Icon(Icons.play_arrow_rounded),
        label: Text(what),
      );
    }

    return GlassCard(
      tint: pal.dot,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: ink),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: StatusChip(chip)),
            const SizedBox(height: 18),
            Center(
              child: Semantics(
                label: '${phase.label}, ${formatClock(left)} left',
                child: SizedBox(
                  width: 240,
                  height: 240,
                  child: CustomPaint(
                    painter: _RingPainter(progress: progress, color: pal.dot),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatClock(left),
                            style: TextStyle(
                              fontSize: 56,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1.5,
                              color: ink,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          if (t != null && t.running)
                            Text('until ${formatTime(t.endsAt!.hour * 60 + t.endsAt!.minute)}',
                                style: TextStyle(fontSize: 14, color: ink.withValues(alpha: 0.8))),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _RoundDots(
              rounds: v.settings.rounds,
              round: t?.round ?? 1,
              onBreak: phase.isBreak,
              color: pal.dot,
            ),
            const SizedBox(height: 16),
            if (t == null)
              TextField(
                controller: _label,
                textInputAction: TextInputAction.go,
                onSubmitted: (s) => startPomodoroNow(ref, label: s),
                decoration: InputDecoration(hintText: hint, prefixIcon: const Icon(Icons.edit_outlined, size: 18)),
              )
            else if (subject.isNotEmpty)
              Text(
                phase.isBreak ? 'Next up: $subject' : 'On: $subject',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: ink),
              ),
            const SizedBox(height: 16),
            primary(),
            if (t != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: c.skipPomodoro,
                      icon: Icon(Icons.skip_next_rounded, color: ink),
                      label: Text(phase.isBreak ? 'Skip break' : 'Skip to break', style: TextStyle(color: ink)),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () async {
                        await c.stopPomodoro();
                        if (context.mounted) showToast(context, 'Pomodoro stopped');
                      },
                      icon: Icon(Icons.stop_rounded, color: ink),
                      label: Text('Stop', style: TextStyle(color: ink)),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            Text('Space starts and pauses',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: ink.withValues(alpha: 0.6))),
          ],
        ),
      ),
    );
  }
}

class _RoundDots extends StatelessWidget {
  final int rounds;
  final int round;
  final bool onBreak;
  final Color color;
  const _RoundDots({required this.rounds, required this.round, required this.onBreak, required this.color});

  @override
  Widget build(BuildContext context) {
    // Rounds before this one are done; on a break, this one is done too.
    final done = onBreak ? round : round - 1;
    return Semantics(
      label: 'Round $round of $rounds',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < rounds; i++)
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < done ? color : Colors.transparent,
                border: Border.all(color: color, width: 1.6),
              ),
            ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    canvas.drawArc(
      r,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = color.withValues(alpha: 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (progress <= 0) return;
    canvas.drawArc(
      r,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color;
}

class _TodayPanel extends StatelessWidget {
  final PomodoroView view;
  const _TodayPanel({required this.view});

  @override
  Widget build(BuildContext context) {
    final s = view.stats;
    return ClearGlass(
      radius: BorderRadius.circular(20),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Today'),
          const SizedBox(height: 10),
          Text(
            '${s.today} ${s.today == 1 ? 'pomodoro' : 'pomodoros'} · ${formatDuration(s.todayMinutes)} focused',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text('This week: ${s.week} · ${formatDuration(s.weekMinutes)}',
              style: const TextStyle(fontSize: 13, color: Brand.muted)),
          const SizedBox(height: 12),
          if (view.today.isEmpty)
            const Text('Finish a focus round to see it here.', style: TextStyle(color: Brand.muted))
          else
            for (final p in view.today.reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      p.completed ? Icons.check_circle_rounded : Icons.timelapse_rounded,
                      size: 18,
                      color: p.completed ? Brand.cyanDeep : Brand.muted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Text(
                      '${formatTime(p.startedAt.hour * 60 + p.startedAt.minute)} · ${p.focusedMinutes} min',
                      style: const TextStyle(fontSize: 13, color: Brand.muted),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// A small pill with the live countdown, for the Now screen header.
class PomodoroChip extends ConsumerWidget {
  final VoidCallback onTap;
  const PomodoroChip({super.key, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(pomodoroProvider);
    final t = v?.timer;
    if (v == null || t == null) return const SizedBox.shrink();
    final pal = pomodoroPalette(t.phase);
    return Semantics(
      button: true,
      label: '${pomodoroMenuTitle(t, v.now)}. Open Pomodoro',
      child: Material(
        color: pal.tint,
        shape: StadiumBorder(side: BorderSide(color: pal.edge)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(t.running ? Icons.timer_outlined : Icons.pause_rounded, size: 14, color: pal.ink),
                const SizedBox(width: 6),
                Text(
                  pomodoroMenuTitle(t, v.now),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: pal.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lengths, rounds and auto-start.
Future<void> showPomodoroSettings(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      barrierColor: Brand.ink.withValues(alpha: 0.22),
      builder: (_) => const _SettingsSheet(),
    );

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider).valueOrNull?.pomodoroSettings ?? const PomodoroSettings();
    final c = ref.read(appProvider.notifier);

    Widget row(String label, int value, String unit, int min, int max, int step, PomodoroSettings Function(int) apply) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
            IconButton(
              tooltip: 'Less',
              onPressed: value - step < min ? null : () => c.setPomodoroSettings(apply(value - step)),
              icon: const Icon(Icons.remove_rounded),
            ),
            SizedBox(
              width: 64,
              child: Text('$value $unit', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            IconButton(
              tooltip: 'More',
              onPressed: value + step > max ? null : () => c.setPomodoroSettings(apply(value + step)),
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
      );
    }

    return SheetFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Pomodoro settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          row('Focus', s.focusMinutes, 'min', 5, 120, 5, (x) => s.copyWith(focusMinutes: x)),
          row('Short break', s.shortBreakMinutes, 'min', 1, 30, 1, (x) => s.copyWith(shortBreakMinutes: x)),
          row('Long break', s.longBreakMinutes, 'min', 5, 60, 5, (x) => s.copyWith(longBreakMinutes: x)),
          row('Rounds before long break', s.rounds, '', 2, 8, 1, (x) => s.copyWith(rounds: x)),
          const SizedBox(height: 6),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            activeTrackColor: Brand.cyanDeep,
            value: s.autoStartBreaks,
            title: const Text('Start breaks automatically', style: TextStyle(fontWeight: FontWeight.w600)),
            onChanged: (on) => c.setPomodoroSettings(s.copyWith(autoStartBreaks: on)),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            activeTrackColor: Brand.cyanDeep,
            value: s.autoStartFocus,
            title: const Text('Start the next focus round automatically', style: TextStyle(fontWeight: FontWeight.w600)),
            onChanged: (on) => c.setPomodoroSettings(s.copyWith(autoStartFocus: on)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: () => c.setPomodoroSettings(const PomodoroSettings()),
                child: const Text('Back to 25 / 5 / 15'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => c.setPomodoroSettings(
                  s.copyWith(focusMinutes: 50, shortBreakMinutes: 10, longBreakMinutes: 30, rounds: 3),
                ),
                child: const Text('Deep work 50 / 10'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
