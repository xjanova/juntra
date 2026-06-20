import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/tarot_catalog_repository.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../shared/widgets/chantra_logo.dart';
import '../../shared/widgets/gold_button.dart';
import '../../shared/widgets/starry_background.dart';
import '../../shared/widgets/xman_studio_footer.dart';

/// Screen 1 — Splash. Mae Mor portrait centered on starry sky with a
/// gold radial glow and a slow breathing animation.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Warm the web card-art catalog early (cached-first) so the shuffle
    // cinematic already has real card faces by the time it reveals. Fully
    // fire-and-forget: swallow any provider-init error so a cold launch with
    // no network/storage can never raise an unhandled rejection.
    Future.microtask(
      () => ref.read(tarotCatalogProvider.future).catchError(
        (_) => TarotCatalog.empty,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const StarryBackground(density: 80, intensity: 1.1),
          SafeArea(
            // Fill the screen on normal phones (Spacers distribute the slack)
            // but scroll instead of hard-overflowing on short screens — the
            // portrait + logo + subtitle + two buttons + footer is a tall
            // stack that doesn't fit small devices otherwise.
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          const Spacer(flex: 2),
                          // Mae Mor portrait with breathing glow
                          _MaeMorPortrait()
                              .animate(onPlay: (c) => c.repeat(reverse: true))
                              .scale(
                                duration: 3.seconds,
                                curve: Curves.easeInOut,
                                begin: const Offset(1.0, 1.0),
                                end: const Offset(1.025, 1.025),
                              ),
                          const SizedBox(height: 32),
                          const ChantraLogo(size: ChantraLogoSize.lg)
                              .animate()
                              .fadeIn(duration: 600.ms, delay: 200.ms)
                              .slideY(begin: 0.2),
                          const SizedBox(height: 18),
                          const Text(
                            'ดวงดาวเล่าเรื่องราว แม่หมอแปลให้ฟัง\nทาโรต์เปิดทางใจ AI ส่องอนาคต',
                            style: TextStyle(
                              fontSize: 14,
                              color: JuntraColors.purpleBright,
                              height: 1.6,
                              letterSpacing: 0.3,
                            ),
                            textAlign: TextAlign.center,
                          ).animate().fadeIn(duration: 700.ms, delay: 500.ms),
                          const Spacer(flex: 3),
                          GoldButton(
                                label: 'เริ่มดูดวงกับแม่หมอ',
                                icon: const Text(
                                  '✦',
                                  style: TextStyle(fontSize: 16),
                                ),
                                size: GoldButtonSize.lg,
                                onPressed: () => context.go(Routes.home),
                              )
                              .animate()
                              .fadeIn(duration: 600.ms, delay: 800.ms)
                              .slideY(begin: 0.3),
                          const SizedBox(height: 10),
                          GhostButton(
                            label: 'ลงชื่อเข้าใช้',
                            onPressed: () => context.go(Routes.login),
                          ).animate().fadeIn(duration: 600.ms, delay: 950.ms),
                          const SizedBox(height: 28),
                          const XmanStudioFooter(showVersion: true),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MaeMorPortrait extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 280,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer gold glow
          Container(
            width: 240,
            height: 290,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  JuntraColors.gold.withValues(alpha: 0.4),
                  JuntraColors.gold.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          // Portrait (oval mask)
          ClipOval(
            child: Container(
              width: 200,
              height: 270,
              decoration: BoxDecoration(
                border: Border.all(
                  color: JuntraColors.gold.withValues(alpha: 0.5),
                  width: 2,
                ),
                shape: BoxShape.circle,
              ),
              child: Image.asset(
                'assets/images/maehmor.png',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: JuntraColors.bgPurpleDeep,
                  alignment: Alignment.center,
                  child: const Text('🔮', style: TextStyle(fontSize: 80)),
                ),
              ),
            ),
          ),
          // Inner mystic shadow
          IgnorePointer(
            child: Container(
              width: 200,
              height: 270,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(0, 0.5),
                  radius: 1.0,
                  colors: [
                    Colors.transparent,
                    JuntraColors.purple.withValues(alpha: 0.3),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
