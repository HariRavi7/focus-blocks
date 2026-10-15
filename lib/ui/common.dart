import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../schedule_engine.dart';
import '../theme.dart';

/// The palette a planned block is drawn in. Colors follow the template's
/// start time, so an extension never flips a block to another color.
BlockPalette paletteFor(PlannedBlock b) {
  if (b.isFree) return BlockPalette.free;
  return BlockPalette.of(b.color, b.block.start);
}

BlockPalette paletteForTemplateBlock(TemplateBlock b) =>
    b.isFree ? BlockPalette.free : BlockPalette.of(b.color, b.start);

/// Small white pill used for NOW / UP NEXT / TIME'S UP.
class StatusChip extends StatelessWidget {
  final String label;
  const StatusChip(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
      child: Text(
        label,
        style: const TextStyle(color: Brand.cyanDeep, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.7),
      ),
    );
  }
}

/// A selectable rounded chip (time choices, reasons, positions).
class ChoicePill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const ChoicePill({super.key, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? Brand.cyanSoft : Colors.white.withValues(alpha: 0.8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: selected ? Brand.cyanDeep : const Color(0xFFD6DDE1)),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected ? Brand.cyanDeep : Brand.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Uppercase section label.
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: Brand.muted),
      );
}

/// − 15 min + stepper in 5-minute steps.
class MinuteStepper extends StatelessWidget {
  final int minutes;
  final VoidCallback onLess;
  final VoidCallback onMore;
  final String taskTitle;
  const MinuteStepper({
    super.key,
    required this.minutes,
    required this.onLess,
    required this.onMore,
    required this.taskTitle,
  });

  @override
  Widget build(BuildContext context) {
    Widget btn(String glyph, String label, VoidCallback onTap) => Semantics(
          button: true,
          label: label,
          child: InkResponse(
            onTap: onTap,
            radius: 20,
            child: SizedBox(
              width: 32,
              height: 36,
              child: Center(
                child: Text(glyph, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Brand.muted)),
              ),
            ),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn('−', 'Less time for $taskTitle', onLess),
        SizedBox(
          width: 52,
          child: Text('$minutes min',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        btn('+', 'More time for $taskTitle', onMore),
      ],
    );
  }
}

/// Frosted-glass tick circle. Tapping an open one plays a short pop and
/// draws the check, then calls [onDone].
class GlassTick extends StatefulWidget {
  final Color color;
  final bool done;
  final double size;
  final String label;
  final VoidCallback? onDone;
  final VoidCallback? onUndo;

  const GlassTick({
    super.key,
    required this.color,
    required this.done,
    required this.label,
    this.size = 28,
    this.onDone,
    this.onUndo,
  });

  @override
  State<GlassTick> createState() => _GlassTickState();
}

class _GlassTickState extends State<GlassTick> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  bool _ticking = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _tap() async {
    if (widget.done) {
      widget.onUndo?.call();
      return;
    }
    if (_ticking || widget.onDone == null) return;
    setState(() => _ticking = true);
    await _c.forward(from: 0);
    if (!mounted) return;
    widget.onDone?.call();
    setState(() => _ticking = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return Semantics(
      button: true,
      checked: widget.done,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _tap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = _c.value;
                var scale = 1.0;
                if (_ticking) scale = t < 0.35 ? 1 + 0.18 * (t / 0.35) : 1.18 - 0.18 * ((t - 0.35) / 0.65);
                final draw = widget.done ? 1.0 : (_ticking ? math.min(1.0, t / 0.7) : 0.0);
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.96),
                          Colors.white.withValues(alpha: 0.6),
                          c.withValues(alpha: 0.22),
                        ],
                        stops: const [0, 0.45, 1],
                      ),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.95)),
                      boxShadow: [BoxShadow(color: c.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))],
                    ),
                    child: CustomPaint(painter: _CheckPainter(draw, c)),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  final double progress;
  final Color color;
  _CheckPainter(this.progress, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final s = size.width / 24;
    final path = Path()
      ..moveTo(7 * s, 12.5 * s)
      ..lineTo(10.5 * s, 16 * s)
      ..lineTo(17 * s, 8.5 * s);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final metrics = path.computeMetrics().toList();
    final total = metrics.fold<double>(0, (a, m) => a + m.length);
    var remaining = total * progress;
    final out = Path();
    for (final m in metrics) {
      final len = math.min(remaining, m.length);
      if (len > 0) out.addPath(m.extractPath(0, len), Offset.zero);
      remaining -= len;
      if (remaining <= 0) break;
    }
    canvas.drawPath(out, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress || old.color != color;
}

/// A short toast at the bottom, with an optional Undo.
void showToast(BuildContext context, String message, {VoidCallback? onUndo}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Brand.ink,
      duration: Duration(seconds: onUndo == null ? 2 : 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      content: Row(
        children: [
          if (onUndo == null) ...[
            const Icon(Icons.check_rounded, color: Brand.cyan, size: 18),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500))),
        ],
      ),
      action: onUndo == null ? null : SnackBarAction(label: 'Undo', textColor: Brand.cyan, onPressed: onUndo),
    ),
  );
}

/// A quote in the light, thin style used on the Now card.
class QuoteText extends StatelessWidget {
  final String text;
  final String source;
  final Color color;
  final double size;
  const QuoteText({super.key, required this.text, required this.source, required this.color, this.size = 19});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '“$text”',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: size, fontWeight: FontWeight.w300, letterSpacing: 0.2, height: 1.4, color: color),
        ),
        if (source.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            source,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.3, color: color.withValues(alpha: 0.8)),
          ),
        ],
      ],
    );
  }
}

/// A bottom sheet body in clear white glass with a drag handle.
class SheetFrame extends StatelessWidget {
  final Widget child;
  const SheetFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ClearGlass(
            opacity: 0.88,
            radius: const BorderRadius.vertical(top: Radius.circular(28)),
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(color: Brand.line, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    child,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A dark "ink" filled button (used for confirming an extension).
ButtonStyle inkButtonStyle() => FilledButton.styleFrom(
      backgroundColor: Brand.ink,
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
