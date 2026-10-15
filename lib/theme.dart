import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'models.dart';

/// Brand colors.
class Brand {
  static const ink = Color(0xFF0B1215);
  static const muted = Color(0xFF56626A);
  static const line = Color(0xFFC9D2D8);
  static const cyan = Color(0xFF06B6D4);
  static const cyanDeep = Color(0xFF0E7490);
  static const cyanSoft = Color(0xFFE3F8FC);
  static const warn = Color(0xFF9A3412);
}

/// The four block colors: a pale tint, an edge, the ink used for text on
/// that tint, and the strong dot color.
class BlockPalette {
  final Color tint;
  final Color edge;
  final Color ink;
  final Color dot;
  final String label;
  const BlockPalette(this.tint, this.edge, this.ink, this.dot, this.label);

  static const amber = BlockPalette(Color(0xFFFFF4E5), Color(0xFFF2D6AA), Color(0xFF6B3A0C), Color(0xFFE8962E), 'Amber');
  static const teal = BlockPalette(Color(0xFFE5F5F2), Color(0xFFB6E0D8), Color(0xFF1B5952), Color(0xFF2FA294), 'Teal');
  static const indigo = BlockPalette(Color(0xFFEEECFC), Color(0xFFCDC8F3), Color(0xFF352E80), Color(0xFF6E61DB), 'Indigo');
  static const cyan = BlockPalette(Color(0xFFE3F8FC), Color(0xFFB3E8F2), Color(0xFF0B5566), Color(0xFF06B6D4), 'Cyan');
  static const free = BlockPalette(Color(0xFFFFFFFF), Color(0xFFC9D2D8), Color(0xFF56626A), Color(0xFFC9D2D8), 'Free');

  /// Morning blocks are amber, afternoons teal, evenings indigo, unless the
  /// user picked a color.
  static BlockPalette of(BlockColor color, int startMinutes) {
    switch (color) {
      case BlockColor.amber:
        return amber;
      case BlockColor.teal:
        return teal;
      case BlockColor.indigo:
        return indigo;
      case BlockColor.cyan:
        return cyan;
      case BlockColor.auto:
        if (startMinutes < 720) return amber;
        if (startMinutes < 1020) return teal;
        return indigo;
    }
  }
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: Brand.cyanDeep, surface: Colors.white),
    scaffoldBackgroundColor: Colors.white,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: Brand.ink, displayColor: Brand.ink),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Brand.cyanDeep,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Brand.ink,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: Brand.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.7),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Brand.line)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Brand.line)),
    ),
  );
}

/// Soft color orbs behind a screen, so glass has something to blur.
class GlassBackdrop extends StatelessWidget {
  final Color color;
  final Widget child;
  const GlassBackdrop({super.key, required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    Widget orb(double size, Color c, double blur) => ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: c)),
        );
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, Color.lerp(Colors.white, color, 0.12)!],
              ),
            ),
          ),
        ),
        Positioned(right: -40, top: 70, child: orb(230, color.withValues(alpha: 0.75), 34)),
        Positioned(left: -80, top: 330, child: orb(260, color.withValues(alpha: 0.5), 40)),
        Positioned(right: -30, bottom: -20, child: orb(180, color.withValues(alpha: 0.55), 36)),
        Positioned.fill(child: child),
      ],
    );
  }
}

/// Frosted glass: a light white frost, a faint wash of [tint], a bright
/// hairline edge, a soft shine in the top-left corner and a colored shadow.
class GlassCard extends StatelessWidget {
  final Widget child;
  final Color tint;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double frost; // 0 = clear, 1 = milky
  final Color? outline;

  const GlassCard({
    super.key,
    required this.child,
    required this.tint,
    this.radius = 32,
    this.padding = const EdgeInsets.all(24),
    this.frost = 0.26,
    this.outline,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [BoxShadow(color: tint.withValues(alpha: 0.2), blurRadius: 48, offset: const Offset(0, 24))],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: r,
              border: Border.all(color: outline ?? Colors.white.withValues(alpha: 0.55), width: outline == null ? 1 : 2),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(Colors.white.withValues(alpha: frost), tint.withValues(alpha: 0.05)),
                  Color.alphaBlend(Colors.white.withValues(alpha: frost * 0.2), tint.withValues(alpha: 0.05)),
                ],
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.topLeft,
                          radius: 1.1,
                          colors: [Colors.white.withValues(alpha: 0.35), Colors.white.withValues(alpha: 0)],
                          stops: const [0, 0.5],
                        ),
                      ),
                    ),
                  ),
                ),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Clear white glass for sheets, panels and buttons.
class ClearGlass extends StatelessWidget {
  final Widget child;
  final BorderRadius radius;
  final EdgeInsetsGeometry padding;
  final double opacity;
  const ClearGlass({
    super.key,
    required this.child,
    this.radius = const BorderRadius.all(Radius.circular(18)),
    this.padding = EdgeInsets.zero,
    this.opacity = 0.55,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: radius,
            color: Colors.white.withValues(alpha: opacity),
            border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Segmented progress bar: one segment per task plus open time.
class SegmentBar extends StatelessWidget {
  final List<({int minutes, double fill, bool open})> segments;
  final Color color;
  final double height;
  const SegmentBar({super.key, required this.segments, required this.color, this.height = 6});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < segments.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Expanded(
            flex: segments[i].minutes.clamp(1, 100000).toInt(),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(height),
              child: SizedBox(
                height: height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ColoredBox(color: color.withValues(alpha: segments[i].open ? 0.08 : 0.18)),
                    ),
                    FractionallySizedBox(
                      widthFactor: segments[i].fill.clamp(0.0, 1.0).toDouble(),
                      heightFactor: 1,
                      child: ColoredBox(color: color),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
