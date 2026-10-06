import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../data/juntra_art.dart';

/// Cinematic night-sky background — radial gradient nebula, twinkling
/// stars, slow-floating gold particles, and the จันทรา brand logo in the
/// top-right corner.
///
/// มุมขวาบนเดิมเป็นพระจันทร์เสี้ยวที่วาดด้วยโค้ด (วงทองมีวงกลมมืดเจาะกลาง ดูไม่ออก
/// ว่าเป็นอะไร) ตอนนี้เป็นโลโก้จริง [JuntraArt.logoMark] วางตาม safe area จึงอยู่
/// แถวเดียวกับหัวจอเสมอ — หัวจอที่มีปุ่มด้านขวาต้องเว้นที่ท้ายแถวไว้
/// [StarryBackground.logoReserve] ไม่งั้นปุ่มจะทับโลโก้
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

  /// แสดงโลโก้จันทรามุมขวาบน (ชื่อเดิมจากสมัยที่เป็นพระจันทร์วาดเอง)
  final bool showMoon;

  /// ความกว้างที่หัวจอต้องเว้นไว้ท้ายแถว (นับจากขอบใน 16px) เพื่อไม่ให้ปุ่มทับโลโก้
  static const double logoReserve = 54;

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
    final sky = RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _StarryPainter(
              stars: _stars,
              particles: _particles,
              t: _controller.value * 6.28,
              intensity: widget.intensity,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
    if (!widget.showMoon) return sky;
    return Stack(
      fit: StackFit.expand,
      children: [
        sky,
        Positioned(
          top: MediaQuery.paddingOf(context).top + 8,
          right: 8,
          child: const IgnorePointer(child: _BrandMark()),
        ),
      ],
    );
  }
}

/// โลโก้จันทรา (เสี้ยวจันทร์ทอง + ตัวอักษร) พร้อมแสงทองนวล ๆ ด้านหลัง
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  static const double _w = 56;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return SizedBox(
      width: _w,
      height: _w * 0.875,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: JuntraColors.gold.withValues(alpha: 0.28),
                  blurRadius: 22,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const SizedBox(width: _w * 0.6, height: _w * 0.6),
          ),
          Image.asset(
            JuntraArt.logoMark,
            width: _w,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            cacheWidth: (_w * dpr).round(),
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ],
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
    required this.t, required this.intensity,
  });
  final List<_Star> stars;
  final List<_Particle> particles;
  final double t;
  final double intensity;

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
  }

  @override
  bool shouldRepaint(covariant _StarryPainter old) => true;
}
