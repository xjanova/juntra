import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Cinematic night-sky background — radial gradient nebula, twinkling
/// stars, slow-floating gold particles, optional crescent in top-right.
///
/// Performance: stars are precomputed in initState (no rebuild churn);
/// twinkle/float are animated with a single AnimationController fed
/// into a CustomPainter so the widget tree stays cheap.
class StarryBackground extends StatefulWidget {
  const StarryBackground({
    super.key,
    this.density = 60,
    this.intensity = 1.0,
    this.showMoon = true,
  });
  final int density;
  final double intensity;
  final bool showMoon;

  @override
  State<StarryBackground> createState() => _StarryBackgroundState();
}

class _StarryBackgroundState extends State<StarryBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Star> _stars;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    final rng = math.Random(42); // Stable seed → no flicker on hot reload
    _stars = List.generate(widget.density, (_) {
      return _Star(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        size: rng.nextDouble() * 1.6 + 0.4,
        baseOpacity: rng.nextDouble() * 0.6 + 0.2,
        twinklePhase: rng.nextDouble() * 6.28,
        twinkleSpeed: rng.nextDouble() * 0.6 + 0.4,
      );
    });
    _particles = List.generate(14, (_) {
      return _Particle(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        phase: rng.nextDouble() * 6.28,
        speed: rng.nextDouble() * 0.3 + 0.2,
      );
    });
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _StarryPainter(
              stars: _stars,
              particles: _particles,
              t: _controller.value * 6.28,
              intensity: widget.intensity,
              showMoon: widget.showMoon,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _Star {
  _Star({
    required this.x, required this.y, required this.size,
    required this.baseOpacity, required this.twinklePhase, required this.twinkleSpeed,
  });
  final double x, y, size, baseOpacity, twinklePhase, twinkleSpeed;
}

class _Particle {
  _Particle({required this.x, required this.y, required this.phase, required this.speed});
  final double x, y, phase, speed;
}

class _StarryPainter extends CustomPainter {
  _StarryPainter({
    required this.stars, required this.particles,
    required this.t, required this.intensity, required this.showMoon,
  });
  final List<_Star> stars;
  final List<_Particle> particles;
  final double t;
  final double intensity;
  final bool showMoon;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Nebula radial background
    final bg = Paint()
      ..shader = const RadialGradient(
        center: Alignment(0, -0.6),
        radius: 1.4,
        colors: [
          Color(0xFF2A1B4A), Color(0xFF150924), Color(0xFF0A0414), Color(0xFF060309),
        ],
        stops: [0.0, 0.4, 0.8, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, bg);

    // Purple nebula glow (top-left)
    final purpleGlow = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40)
      ..color = JuntraColors.purple.withValues(alpha: 0.18 * intensity);
    canvas.drawCircle(
      Offset(size.width * -0.1, size.height * 0.05),
      size.width * 0.5,
      purpleGlow,
    );

    // Gold nebula glow (bottom-right)
    final goldGlow = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 50)
      ..color = JuntraColors.gold.withValues(alpha: 0.12 * intensity);
    canvas.drawCircle(
      Offset(size.width * 1.05, size.height * 0.85),
      size.width * 0.5,
      goldGlow,
    );

    // Stars — twinkling
    for (final s in stars) {
      final tw = (math.sin(t * s.twinkleSpeed + s.twinklePhase) + 1) * 0.5;
      final opacity = (s.baseOpacity * (0.4 + tw * 0.8)).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = const Color(0xFFFFF8E1).withValues(alpha: opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.size * 1.2);
      canvas.drawCircle(
        Offset(s.x * size.width, s.y * size.height),
        s.size,
        paint,
      );
    }

    // Floating gold particles
    for (final p in particles) {
      final phase = (p.phase + t * p.speed) % 6.28;
      final yOff = math.sin(phase) * 30;
      final xOff = math.cos(phase) * 20;
      final particleOpacity = ((math.sin(phase * 0.5) + 1) * 0.5).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = JuntraColors.gold.withValues(alpha: particleOpacity * 0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(
        Offset(p.x * size.width + xOff, p.y * size.height + yOff),
        2.2,
        paint,
      );
    }

    if (showMoon) _paintMoon(canvas, size);
  }

  void _paintMoon(Canvas canvas, Size size) {
    final cx = size.width - 40;
    const cy = 70.0;
    const r = 26.0;

    // Outer glow
    final glow = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16)
      ..color = JuntraColors.gold.withValues(alpha: 0.4);
    canvas.drawCircle(Offset(cx, cy), r + 8, glow);

    // Crescent — large filled circle minus offset cut-out
    final moon = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFFE7A0), Color(0xFFF0C75E),
          Color(0xFFC99B2D), Color(0xFF7A5A1E),
        ],
        stops: [0.0, 0.4, 0.7, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    final path = Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r))
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: Offset(cx + 8, cy - 4), radius: r * 0.85));
    canvas.drawPath(path, moon);
  }

  @override
  bool shouldRepaint(covariant _StarryPainter old) => true;
}
