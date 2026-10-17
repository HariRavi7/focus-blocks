import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_state.dart';
import 'format.dart';
import 'pomodoro.dart';
import 'schedule_engine.dart';
import 'platform/platform_sync.dart';
import 'theme.dart';
import 'ui/add_task_panel.dart';
import 'ui/common.dart';
import 'ui/now_view.dart';
import 'ui/pomodoro_view.dart';
import 'ui/progress_screen.dart';
import 'ui/schedule_view.dart';
import 'ui/setup_flow.dart';
import 'ui/sheets.dart';
import 'ui/templates_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: FocusBlocksApp()));
}

class FocusBlocksApp extends StatelessWidget {
  const FocusBlocksApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Focus Blocks',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const _RootGate(),
    );
  }
}

/// Setup on first run, the app after that.
class _RootGate extends ConsumerWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    return app.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator(color: Brand.cyan))),
      error: (e, _) => Scaffold(body: Center(child: Text('Could not load your data.\n$e', textAlign: TextAlign.center))),
      data: (data) => data.onboarded ? const HomeShell() : const SetupFlow(),
    );
  }
}

enum _Section { now, pomodoro, templates, progress }

/// Phone: the Now screen with pushes to the rest.
/// Mac and wide windows: sidebar, Now card and today's schedule side by side.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  final _prompted = <String>{};
  final _bodyKey = GlobalKey();
  _Section _section = _Section.now;
  late final PlatformSync _platform = PlatformSync(ref);

  @override
  void initState() {
    super.initState();
    // When a block's time is up, offer "Next Goal!" once per block end.
    // Every tick also refreshes the menu bar, notifications and widget.
    ref.listenManual<TodayView?>(todayProvider, (_, next) {
      _maybePrompt(next);
      _platform.push(next);
    }, fireImmediately: true);
    // Move the Pomodoro on when a phase runs out, and say so.
    ref.listenManual<AsyncValue<DateTime>>(clockProvider, (_, next) {
      final now = next.valueOrNull;
      if (now != null) _advancePomodoro(now);
    });
    _platform.start(onAction: (a) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onAction(a);
      });
    });
  }

  @override
  void dispose() {
    _platform.dispose();
    super.dispose();
  }

  bool _advancing = false;

  Future<void> _advancePomodoro(DateTime now) async {
    if (_advancing) return;
    final before = ref.read(appProvider).valueOrNull;
    final t = before?.pomodoro;
    if (before == null || t == null || !t.isOver(now)) return;
    _advancing = true;
    try {
      final message = phaseEndMessage(t, before.pomodoroSettings);
      final a = await ref.read(appProvider.notifier).advancePomodoro(now);
      if (a == null || !mounted) return;
      final ctx = _bodyKey.currentContext ?? context;
      if (ctx.mounted) showToast(ctx, '${message.title}. ${message.body}');
    } finally {
      _advancing = false;
    }
  }

  /// Buttons from the Android notification and the Mac menu bar.
  void _onAction(String action) {
    final c0 = ref.read(appProvider.notifier);
    switch (action) {
      case 'pomo_start':
        if (ref.read(appProvider).valueOrNull?.pomodoro == null) {
          startPomodoroNow(ref);
        } else {
          c0.startPomodoro();
        }
        return;
      case 'pomo_pause':
        c0.pausePomodoro();
        return;
      case 'pomo_skip':
        c0.skipPomodoro();
        return;
      case 'pomo_stop':
        c0.stopPomodoro();
        return;
    }
    final v = ref.read(todayProvider);
    final cur = v?.snap.current;
    if (v == null || cur == null) return;
    final c = ref.read(appProvider.notifier);
    final ctx = _bodyKey.currentContext ?? context;
    switch (action) {
      case 'done':
        final slot = v.snap.phase == Phase.running ? currentTaskSlot(cur) : null;
        if (slot != null) {
          c.toggleTask(cur.id, slot.task.id);
          showToast(ctx, 'Done: ${slot.task.title}');
        } else {
          showReviewSheet(ctx, cur.id);
        }
      case 'extend':
        c.extend(cur.id, 15);
        showToast(ctx, 'Extended by 15 min');
      case 'wrap':
        if (v.snap.phase == Phase.ended) showTimesUpSheet(ctx, cur.id);
    }
  }

  void _maybePrompt(TodayView? v) {
    if (v == null || v.snap.phase != Phase.ended) return;
    final b = v.snap.current;
    if (b == null) return;
    final key = '${dateKey(v.date)}-${b.id}-${b.end}';
    if (!_prompted.add(key)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _bodyKey.currentContext ?? context;
      showTimesUpSheet(ctx, b.id);
    });
  }

  void _push(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(todayProvider);
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 900;
        return Scaffold(
          endDrawer: const AddTaskPanel(),
          body: GlassBackdrop(
            color: backdropColorFor(view),
            child: SafeArea(
              child: KeyedSubtree(key: _bodyKey, child: wide ? _wide(view) : _phone()),
            ),
          ),
        );
      },
    );
  }

  Widget _phone() => NowView(
        wide: false,
        onOpenPomodoro: () => _push(const PomodoroScreen()),
        onOpenSchedule: () => _push(const ScheduleScreen()),
        onOpenProgress: () => _push(const ProgressScreen()),
        onOpenTemplates: () => _push(const TemplatesScreen()),
      );

  Widget _wide(TodayView? view) {
    final Widget center = switch (_section) {
      _Section.now => NowView(
          wide: true,
          onOpenPomodoro: () => setState(() => _section = _Section.pomodoro),
          onOpenSchedule: () {},
          onOpenProgress: () => setState(() => _section = _Section.progress),
          onOpenTemplates: () => setState(() => _section = _Section.templates),
        ),
      _Section.pomodoro => const PomodoroScreen(embedded: true),
      _Section.templates => const TemplatesScreen(embedded: true),
      _Section.progress => const ProgressScreen(embedded: true),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Sidebar(
          section: _section,
          streak: view?.streak ?? 0,
          onPick: (s) => setState(() => _section = s),
        ),
        Expanded(child: center),
        if (_section == _Section.now)
          Container(
            width: 340,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.28),
              border: Border(left: BorderSide(color: Colors.white.withValues(alpha: 0.8))),
            ),
            child: const ScheduleList(compact: true),
          ),
      ],
    );
  }
}

class _Sidebar extends StatelessWidget {
  final _Section section;
  final int streak;
  final ValueChanged<_Section> onPick;
  const _Sidebar({required this.section, required this.streak, required this.onPick});

  @override
  Widget build(BuildContext context) {
    Widget item(_Section s, IconData icon, String label) {
      final on = s == section;
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: on ? Colors.white.withValues(alpha: 0.75) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onPick(s),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: on ? Brand.cyanDeep : Brand.muted),
                  const SizedBox(width: 10),
                  Text(label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                        color: on ? Brand.ink : Brand.muted,
                      )),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 220,
      padding: const EdgeInsets.fromLTRB(14, 22, 14, 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.4),
        border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.8))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 22),
            child: Row(
              children: [
                CircleAvatar(radius: 5, backgroundColor: Brand.cyan),
                SizedBox(width: 10),
                Text('Focus Blocks', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          item(_Section.now, Icons.radio_button_checked_rounded, 'Now'),
          item(_Section.pomodoro, Icons.timer_outlined, 'Pomodoro'),
          item(_Section.templates, Icons.view_agenda_outlined, 'Templates'),
          item(_Section.progress, Icons.insights_rounded, 'Progress'),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(
              children: [
                const Icon(Icons.local_fire_department_outlined, size: 16, color: Brand.cyanDeep),
                const SizedBox(width: 6),
                Text('$streak-day streak',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Brand.cyanDeep)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
