import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import '../quotes.dart';
import '../schedule_engine.dart';
import '../theme.dart';
import 'common.dart';

PlannedBlock? findPlanned(TodayView? view, String blockId) {
  if (view == null) return null;
  for (final b in view.snap.blocks) {
    if (b.id == blockId) return b;
  }
  return null;
}

String nextLabel(TodayView? view) {
  final n = view?.snap.next;
  if (n == null) return 'That was the last block today.';
  return 'Next: ${n.name} at ${formatTime(n.start)}';
}

Future<T?> _sheet<T>(BuildContext context, Widget child) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      barrierColor: Brand.ink.withValues(alpha: 0.22),
      builder: (_) => child,
    );

// ---------------------------------------------------------------- Time's up

/// "You showed up for …" with Next Goal! and a tucked-away Extend time.
Future<void> showTimesUpSheet(BuildContext host, String blockId) =>
    _sheet<void>(host, _TimesUpSheet(blockId: blockId, host: host));

class _TimesUpSheet extends ConsumerStatefulWidget {
  final String blockId;
  final BuildContext host;
  const _TimesUpSheet({required this.blockId, required this.host});

  @override
  ConsumerState<_TimesUpSheet> createState() => _TimesUpSheetState();
}

class _TimesUpSheetState extends ConsumerState<_TimesUpSheet> {
  bool _extendOpen = false;
  int _choice = 15;

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(todayProvider);
    final b = findPlanned(view, widget.blockId);
    final template = view?.template;
    if (view == null || b == null || template == null) return const SizedBox.shrink();

    final tasks = b.state.tasks;
    final done = tasks.where((t) => t.done).length;
    final line = '${tasks.isEmpty ? '' : '$done of ${tasks.length} tasks done. '}Every block you finish adds to your streak.';
    final preview = previewExtend(template, view.record, b.id, _choice);

    return SheetFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text("${formatTime(b.end)} · time's up",
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Brand.cyanDeep)),
          const SizedBox(height: 6),
          Text('You showed up for ${b.name}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.4)),
          const SizedBox(height: 8),
          Text(line, style: const TextStyle(fontSize: 15, color: Brand.muted, height: 1.4)),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (widget.host.mounted) showReviewSheet(widget.host, b.id);
            },
            child: const Text('Next Goal!'),
          ),
          const SizedBox(height: 10),
          if (!_extendOpen)
            OutlinedButton.icon(
              onPressed: () => setState(() => _extendOpen = true),
              icon: const Icon(Icons.schedule_rounded, size: 18),
              label: const Text('Extend time'),
            )
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD6DDE1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Keep going for', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final m in const [10, 15, 30, 45])
                        ChoicePill(label: '$m min', selected: _choice == m, onTap: () => setState(() => _choice = m)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text('${preview.describe}. Ends at ${formatTime(preview.newEnd)}.',
                      style: const TextStyle(fontSize: 13, color: Brand.muted)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                          onPressed: () => setState(() => _extendOpen = false),
                          child: const Text('Back'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          style: inkButtonStyle(),
                          onPressed: () async {
                            final nav = Navigator.of(context);
                            await ref.read(appProvider.notifier).extend(b.id, _choice);
                            nav.pop();
                            if (widget.host.mounted) {
                              showToast(widget.host, 'Extended to ${formatTime(preview.newEnd)}');
                            }
                          },
                          child: Text('Extend by $_choice min'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Review

/// Done / Partly / Not really, then the celebration.
Future<void> showReviewSheet(BuildContext host, String blockId) =>
    _sheet<void>(host, _ReviewSheet(blockId: blockId, host: host));

class _ReviewSheet extends ConsumerWidget {
  final String blockId;
  final BuildContext host;
  const _ReviewSheet({required this.blockId, required this.host});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = findPlanned(ref.watch(todayProvider), blockId);
    if (b == null) return const SizedBox.shrink();

    Future<void> pick(BlockResult r) async {
      final nav = Navigator.of(context);
      await ref.read(appProvider.notifier).review(blockId, r);
      nav.pop();
      if (host.mounted) showCelebration(host, b, r);
    }

    return SheetFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('How did ${b.name} go?',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.4)),
          const SizedBox(height: 6),
          const Text('Done or partly keeps your streak going.', style: TextStyle(fontSize: 15, color: Brand.muted)),
          const SizedBox(height: 20),
          FilledButton(onPressed: () => pick(BlockResult.done), child: const Text('Done')),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: () => pick(BlockResult.partly), child: const Text('Partly')),
          const SizedBox(height: 4),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: Brand.muted),
            onPressed: () => pick(BlockResult.no),
            child: const Text('Not really', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Skip

const skipReasons = ['Work ran late', 'Feeling unwell', 'Plans changed', 'Other'];

Future<void> showSkipSheet(BuildContext host, String blockId) =>
    _sheet<void>(host, _SkipSheet(blockId: blockId, host: host));

class _SkipSheet extends ConsumerStatefulWidget {
  final String blockId;
  final BuildContext host;
  const _SkipSheet({required this.blockId, required this.host});

  @override
  ConsumerState<_SkipSheet> createState() => _SkipSheetState();
}

class _SkipSheetState extends ConsumerState<_SkipSheet> {
  String? _reason;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = findPlanned(ref.watch(todayProvider), widget.blockId);
    if (b == null) return const SizedBox.shrink();
    return SheetFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Why are you skipping this block?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
          const SizedBox(height: 6),
          const Text("It's saved as a note on today, so the week tells the true story.",
              style: TextStyle(fontSize: 14, color: Brand.muted, height: 1.4)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in skipReasons)
                ChoicePill(label: r, selected: _reason == r, onTap: () => setState(() => _reason = r)),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'e.g. client call ran until 9'),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _reason == null
                ? null
                : () async {
                    final nav = Navigator.of(context);
                    final reason = _reason!;
                    final note = _note.text;
                    await ref.read(appProvider.notifier).skip(b.id, reason, note);
                    nav.pop();
                    if (widget.host.mounted) showSkipped(widget.host, b, reason, note);
                  },
            child: const Text('Skip and log it'),
          ),
          const SizedBox(height: 4),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Keep going', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Celebrations

Future<void> _fullScreen(BuildContext host, Widget child) {
  return showGeneralDialog<void>(
    context: host,
    barrierDismissible: false,
    barrierLabel: 'Celebration',
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, __, ___) => child,
    transitionBuilder: (_, anim, __, c) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.04), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: c,
      ),
    ),
  );
}

Future<void> showCelebration(BuildContext host, PlannedBlock b, BlockResult r) {
  HapticFeedback.mediumImpact();
  return _fullScreen(host, _CelebrationView(block: b, result: r));
}

Future<void> showSkipped(BuildContext host, PlannedBlock b, String reason, String note) =>
    _fullScreen(host, _SkippedView(block: b, reason: reason, note: note.trim()));

class _CelebrationView extends ConsumerStatefulWidget {
  final PlannedBlock block;
  final BlockResult result;
  const _CelebrationView({required this.block, required this.result});

  @override
  ConsumerState<_CelebrationView> createState() => _CelebrationViewState();
}

class _CelebrationViewState extends ConsumerState<_CelebrationView> {
  late final Quote _quote = randomQuote(ref.read(appProvider).valueOrNull?.customQuotes ?? const []);

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(todayProvider);
    final pal = paletteFor(widget.block);
    final r = widget.result;
    final title = switch (r) {
      BlockResult.done => 'Block done',
      BlockResult.partly => 'Partly done. It still counts.',
      _ => 'Logged. On to the next one.',
    };
    final streak = view?.streak ?? 0;
    final sub = r == BlockResult.no
        ? "This one won't count toward your streak. The next one can."
        : '${widget.block.name} · day $streak in a row';
    return _ResultFrame(
      color: pal.dot,
      icon: r == BlockResult.no ? Icons.arrow_forward_rounded : Icons.check_rounded,
      title: title,
      sub: sub,
      quote: _quote,
      next: nextLabel(view),
    );
  }
}

class _SkippedView extends ConsumerWidget {
  final PlannedBlock block;
  final String reason;
  final String note;
  const _SkippedView({required this.block, required this.reason, required this.note});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ResultFrame(
      color: paletteFor(block).dot,
      icon: Icons.redo_rounded,
      title: 'Skipped ${block.name}',
      sub: 'Logged on today: $reason${note.isEmpty ? '' : '. $note'}',
      quote: skipQuote,
      next: nextLabel(ref.watch(todayProvider)),
    );
  }
}

class _ResultFrame extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String sub;
  final Quote quote;
  final String next;
  const _ResultFrame({
    required this.color,
    required this.icon,
    required this.title,
    required this.sub,
    required this.quote,
    required this.next,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: GlassBackdrop(
        color: color,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: GlassCard(
                  tint: color,
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.5, end: 1),
                        duration: const Duration(milliseconds: 480),
                        curve: Curves.easeOutBack,
                        builder: (_, v, child) => Transform.scale(scale: v, child: child),
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Colors.white.withValues(alpha: 0.95), color.withValues(alpha: 0.3)],
                            ),
                            border: Border.all(color: Colors.white),
                            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 6))],
                          ),
                          child: Icon(icon, size: 34, color: color),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.4)),
                      const SizedBox(height: 8),
                      Text(sub, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: Brand.muted)),
                      const SizedBox(height: 22),
                      QuoteText(text: quote.text, source: quote.source, color: Brand.ink, size: 18),
                      const SizedBox(height: 22),
                      Text(next, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Brand.muted)),
                      const SizedBox(height: 18),
                      FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Continue')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
