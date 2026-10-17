import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import '../pomodoro.dart';
import '../stats.dart';
import '../theme.dart';
import 'common.dart';

/// Streak, this week, totals and where the time went.
class ProgressScreen extends ConsumerWidget {
  final bool embedded;
  const ProgressScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appProvider).valueOrNull ?? const AppData();
    final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
    final s = computeStats(data, now);
    final p = pomodoroStats(data.pomodoros, now);
    final maxMinutes = s.minutesByName.isEmpty ? 1 : s.minutesByName.first.value;

    final body = ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const Text('Progress', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.6)),
        const SizedBox(height: 4),
        const Text('Done or partly keeps your streak going.', style: TextStyle(fontSize: 15, color: Brand.muted)),
        const SizedBox(height: 18),
        GlassCard(
          tint: Brand.cyan,
          radius: 24,
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              const Icon(Icons.local_fire_department_outlined, color: Brand.cyanDeep, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${s.currentStreak}-day streak',
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                    const SizedBox(height: 2),
                    Text('Longest: ${s.longestStreak} ${s.longestStreak == 1 ? 'day' : 'days'}',
                        style: const TextStyle(fontSize: 14, color: Brand.muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _Panel(
          title: 'This week',
          child: SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final d in s.week)
                  Expanded(child: _WeekBar(bar: d, isToday: dateKey(d.day) == dateKey(now))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _Number(label: 'Done', value: '${s.done}')),
            const SizedBox(width: 10),
            Expanded(child: _Number(label: 'Partly', value: '${s.partly}')),
            const SizedBox(width: 10),
            Expanded(child: _Number(label: 'Skipped', value: '${s.skipped}')),
          ],
        ),
        const SizedBox(height: 10),
        _Number(label: 'Time you showed up for', value: formatDuration(s.focusMinutes)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _Number(label: 'Pomodoros this week', value: '${p.week}')),
            const SizedBox(width: 10),
            Expanded(child: _Number(label: 'Pomodoro focus, all time', value: formatDuration(p.totalMinutes))),
          ],
        ),
        const SizedBox(height: 14),
        _Panel(
          title: 'Where the time went',
          child: s.minutesByName.isEmpty
              ? const Text('Finish a block to see it here.', style: TextStyle(color: Brand.muted))
              : Column(
                  children: [
                    for (final e in s.minutesByName.take(6))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600))),
                                Text(formatDuration(e.value), style: const TextStyle(fontSize: 13, color: Brand.muted)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: e.value / maxMinutes,
                                minHeight: 6,
                                color: Brand.cyanDeep,
                                backgroundColor: Brand.cyanSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        if (s.skipReasons.isNotEmpty) ...[
          const SizedBox(height: 14),
          _Panel(
            title: 'Why blocks were skipped',
            child: Column(
              children: [
                for (final e in s.skipReasons)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(child: Text(e.key)),
                        Text('${e.value}×', style: const TextStyle(color: Brand.muted)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );

    if (embedded) return SafeArea(child: body);
    final page = GlassBackdrop(color: Brand.cyan, child: SafeArea(child: body));
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent, surfaceTintColor: Colors.transparent, elevation: 0),
      body: page,
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final Widget child;
  const _Panel({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClearGlass(
      radius: BorderRadius.circular(20),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(title),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Number extends StatelessWidget {
  final String label;
  final String value;
  const _Number({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return ClearGlass(
      radius: BorderRadius.circular(18),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 13, color: Brand.muted)),
        ],
      ),
    );
  }
}

class _WeekBar extends StatelessWidget {
  final DayBar bar;
  final bool isToday;
  const _WeekBar({required this.bar, required this.isToday});

  @override
  Widget build(BuildContext context) {
    final frac = bar.total == 0 ? 0.0 : (bar.good / bar.total).clamp(0.0, 1.0).toDouble();
    return Semantics(
      label: '${weekdayName(bar.day.weekday)}: ${bar.good} of ${bar.total} blocks',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: frac == 0 ? 0.04 : frac,
                child: Container(
                  width: 18,
                  decoration: BoxDecoration(
                    color: frac == 0 ? Brand.line.withValues(alpha: 0.6) : Brand.cyanDeep,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            weekdayLetter[bar.day.weekday - 1],
            style: TextStyle(
              fontSize: 12,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
              color: isToday ? Brand.cyanDeep : Brand.muted,
            ),
          ),
        ],
      ),
    );
  }
}
