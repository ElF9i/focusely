import 'dart:math';
import 'package:flutter/material.dart';

class AnimatedBackground extends StatefulWidget {
  const AnimatedBackground({super.key});

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final List<_Star> _stars;

  @override
  void initState() {
    super.initState();
    final r = Random(7);
    _stars = List.generate(
        26, (_) => _Star(r.nextDouble(), r.nextDouble(), r.nextDouble()));
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 24));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.of(context).disableAnimations;
    if (reduce) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) => CustomPaint(
          painter: _BgPainter(_c.value, _stars),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _Star {
  final double x, y, phase;
  _Star(this.x, this.y, this.phase);
}

class _BgPainter extends CustomPainter {
  final double t;
  final List<_Star> stars;
  _BgPainter(this.t, this.stars);

  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF14172B));

    void blob(double fx, double fy, double r, Color col, double ph, int sp) {
      final a = 2 * pi * (t * sp + ph);
      final o = Offset(s.width * fx + 30 * sin(a), s.height * fy + 40 * cos(a));
      final paint = Paint()
        ..color = col.withAlpha(115)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 45);
      canvas.drawCircle(o, r * (1 + 0.08 * sin(a)), paint);
    }

    blob(0.05, 0.08, 120, const Color(0xFF4C3FD1), 0.0, 1);
    blob(0.95, 0.42, 100, const Color(0xFF0F8F78), 0.33, 1);
    blob(0.25, 0.95, 90, const Color(0xFFD4537E), 0.66, 2);

    for (final st in stars) {
      final tw = 0.5 + 0.5 * sin(2 * pi * (t * 3 + st.phase));
      final p = Paint()..color = Colors.white.withAlpha((40 + 190 * tw).round());
      canvas.drawCircle(Offset(st.x * s.width, st.y * s.height), 1.5, p);
    }
  }

  @override
  bool shouldRepaint(covariant _BgPainter old) => true;
}