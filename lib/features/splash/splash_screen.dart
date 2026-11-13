import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/data/juntra_art.dart';
import '../../core/api/tarot_catalog_repository.dart';
import '../../core/auth/auth_state.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../shared/widgets/chantra_logo.dart';
import '../../shared/widgets/gold_button.dart';
import '../../shared/widgets/starry_background.dart';
import '../../shared/widgets/xman_studio_footer.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(tarotCatalogProvider.future).catchError((_) => TarotCatalog.empty);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isGuest = ref.watch(authControllerProvider) is AuthGuest;
    return Scaffold(body: LayoutBuilder(builder: (context, constraints) {
      final height = math.max(constraints.maxHeight, 640.0);
      return SingleChildScrollView(child: SizedBox(height: height, width: constraints.maxWidth,
        child: Stack(fit: StackFit.expand, children: [
          Image.asset(JuntraArt.splashBg, fit: BoxFit.cover, alignment: Alignment.topCenter,
            errorBuilder: (_, _, _) => const StarryBackground(showMoon: false)),
          Positioned(top: height * .28, height: height * .26, left: 56, right: 56,
            child: const Center(child: ChantraLogo(size: ChantraLogoSize.lg))
              .animate().fadeIn(duration: 600.ms)),
          Positioned(left: 24, right: 24, bottom: 16,
            child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('ดวงดาวเล่าเรื่องราว แม่หมอแปลให้ฟัง\nทาโรต์เปิดทางใจ AI ส่องอนาคต',
                style: baiJamjuree(size: 13, color: JuntraColors.textCream).copyWith(height: 1.6),
                textAlign: TextAlign.center),
              const SizedBox(height: 20),
              GoldButton(label: 'เริ่มดูดวงกับแม่หมอ', icon: const Icon(Icons.auto_awesome),
                size: GoldButtonSize.lg, onPressed: () => context.go(Routes.home)),
              if (isGuest) ...[
                const SizedBox(height: 10),
                GhostButton(label: 'ลงชื่อเข้าใช้', onPressed: () => context.go(Routes.login)),
              ],
              const SizedBox(height: 20),
              const XmanStudioFooter(showVersion: true),
            ]))),
        ])));
    }));
  }
}