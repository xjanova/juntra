import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';

/// Screen 12 — Share. Bottom-sheet style with platform grid.
class ShareScreen extends StatelessWidget {
  const ShareScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final platforms = const [
      _Platform('LINE', '🟢', Color(0xFF06C755)),
      _Platform('Facebook', '📘', Color(0xFF1877F2)),
      _Platform('Messenger', '💬', Color(0xFF0084FF)),
      _Platform('Instagram', '📸', Color(0xFFE4405F)),
      _Platform('X', '𝕏', Color(0xFF000000)),
      _Platform('TikTok', '🎵', Color(0xFFFF0050)),
      _Platform('คัดลอกลิงก์', '🔗', JuntraColors.gold),
      _Platform('บันทึกรูป', '💾', JuntraColors.cyan),
    ];
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () => context.pop(),
        child: Container(
          color: Colors.black.withValues(alpha: 0.7),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () {/* swallow */},
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Color(0xFF1A0F2E), Color(0xFF0A0414)],
                  ),
                  borderRadius: BorderRadius.circular(JuntraRadius.hero),
                  border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.4)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36, height: 4,
                      decoration: BoxDecoration(
                        color: JuntraColors.textFaint,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('แชร์คำทำนาย', style: baiJamjuree(size: 18)),
                    const SizedBox(height: 16),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 4,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 8,
                      children: platforms.map((p) => _PlatformTile(p: p)).toList(),
                    ),
                    const SizedBox(height: 12),
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

class _Platform {
  const _Platform(this.name, this.icon, this.color);
  final String name;
  final String icon;
  final Color color;
}

class _PlatformTile extends StatelessWidget {
  const _PlatformTile({required this.p});
  final _Platform p;
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: p.color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.color.withValues(alpha: 0.4)),
          ),
          alignment: Alignment.center,
          child: Text(p.icon, style: const TextStyle(fontSize: 24)),
        ),
        const SizedBox(height: 6),
        Text(p.name, style: const TextStyle(
          fontSize: 11, color: JuntraColors.textCream,
        )),
      ],
    );
  }
}
