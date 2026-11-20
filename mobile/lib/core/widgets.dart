import 'dart:math';
import 'package:flutter/material.dart';

class AppColors {
  static const bg1 = Color(0xFF0B0B1E);
  static const bg2 = Color(0xFF1B1140);
  static const accent = Color(0xFF8B7CFF);
  static const accent2 = Color(0xFF38E1C6);
  static const warm = Color(0xFFFFB74D);
  static const pink = Color(0xFFFF6B8B);
  static const green = Color(0xFFA5D66F);
}

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.accent, brightness: Brightness.dark),
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xDD0B0B1E),
        indicatorColor: AppColors.accent.withValues(alpha: 0.35),
      ),
    );

String fmtDur(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}';
  return '$m min';
}

String fmtClock(int seconds) {
  if (seconds < 0) seconds = 0;
  String two(int n) => n.toString().padLeft(2, '0');
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

// ---------- Fond degrade avec etoiles qui scintillent ----------
class AppBackground extends StatefulWidget {
  const AppBackground({super.key, required this.child});
  final Widget child;
  @override
  State<AppBackground> createState() => _AppBackgroundState();
}

class _Star {
  _Star(this.x, this.y, this.r, this.phase);
  final double x, y, r, phase;
}

class _AppBackgroundState extends State<AppBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
  late final List<_Star> _stars = () {
    final r = Random(11);
    return List.generate(80, (_) => _Star(r.nextDouble(), r.nextDouble(), 0.6 + r.nextDouble() * 1.6, r.nextDouble()));
  }();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.bg1, AppColors.bg2],
        ),
      ),
      child: Stack(fit: StackFit.expand, children: [
        IgnorePointer(child: CustomPaint(painter: _StarPainter(_stars, _c))),
        widget.child,
      ]),
    );
  }
}

class _StarPainter extends CustomPainter {
  _StarPainter(this.stars, this.t) : super(repaint: t);
  final List<_Star> stars;
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    for (final s in stars) {
      final tw = 0.5 + 0.5 * sin(2 * pi * (t.value + s.phase));
      p.color = Colors.white.withValues(alpha: 0.15 + 0.55 * tw);
      canvas.drawCircle(Offset(s.x * size.width, s.y * size.height), s.r, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------- Carte "verre" ----------
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: child,
      );
}

// ---------- Anneau lumineux du minuteur ----------
class FocusRing extends StatelessWidget {
  const FocusRing({
    super.key,
    required this.progress,
    required this.c1,
    required this.c2,
    required this.child,
    this.size = 280,
  });
  final double progress;
  final Color c1, c2;
  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _RingPainter(progress, c1, c2), child: Center(child: child)),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.c1, this.c2);
  final double progress;
  final Color c1, c2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 18;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..color = Colors.white.withValues(alpha: 0.08),
    );
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;
    final sweep = 2 * pi * p;

    canvas.drawArc(
      rect, -pi / 2, sweep, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22
        ..strokeCap = StrokeCap.round
        ..color = c1.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawArc(
      rect, -pi / 2, sweep, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: 2 * pi,
          colors: [c2, c1, c2],
          transform: const GradientRotation(-pi / 2),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.c1 != c1 || old.c2 != c2;
}
