import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../shared/widgets/starry_background.dart';
import '../../shared/widgets/xman_studio_footer.dart';

/// Screen 9 — Profile. Avatar + tier + stats + menu cards (Natal Chart,
/// Affiliate Network, Packages, Settings, Sign-out).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const StarryBackground(density: 30, intensity: 0.4),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _Header(),
                const SizedBox(height: 24),
                _AvatarBlock(),
                const SizedBox(height: 18),
                _StatsRow(),
                const SizedBox(height: 20),
                _MenuCard(
                  icon: Icons.star_outline,
                  iconColor: JuntraColors.gold,
                  title: 'ผังดวงดาวเจ้าชะตา',
                  subtitle: 'ดวงเกิดของลูก คำนวณตามวันเวลา',
                  onTap: () => context.go(Routes.natal),
                ),
                _MenuCard(
                  icon: Icons.account_tree_outlined,
                  iconColor: JuntraColors.purpleBright,
                  title: 'ระบบสายงาน Affiliate',
                  subtitle: 'รายได้เดือนนี้ ฿4,250 · 47 คนในสายงาน',
                  onTap: () => context.go(Routes.affiliate),
                ),
                _MenuCard(
                  icon: Icons.bolt_outlined,
                  iconColor: JuntraColors.cyan,
                  title: 'แพ็คเกจของฉัน',
                  subtitle: 'Premium · เหลือ 23 วัน',
                  onTap: () {},
                ),
                _MenuCard(
                  icon: Icons.settings_outlined,
                  iconColor: JuntraColors.textMuted,
                  title: 'ตั้งค่า',
                  subtitle: 'ภาษา · ธีม · การแจ้งเตือน',
                  onTap: () {},
                ),
                _MenuCard(
                  icon: Icons.system_update_outlined,
                  iconColor: JuntraColors.mintGreen,
                  title: 'ตรวจสอบอัปเดต',
                  subtitle: 'อัปเดตให้ทันสมัยอยู่เสมอ',
                  onTap: () {/* triggers manual UpdateService check */},
                ),
                const SizedBox(height: 16),
                _VersionFooter(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, color: JuntraColors.gold, size: 28),
          onPressed: () => context.go(Routes.home),
        ),
        Expanded(child: Text('โปรไฟล์', style: baiJamjuree(size: 19))),
      ],
    );
  }
}

class _AvatarBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 92, height: 92,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [JuntraColors.bgPurpleLight, JuntraColors.bgPurple],
            ),
            border: Border.all(color: JuntraColors.gold, width: 2),
          ),
          alignment: Alignment.center,
          child: Text('ม', style: baiJamjuree(size: 40)),
        ),
        const SizedBox(height: 10),
        Text('คุณมาลี ✨', style: baiJamjuree(size: 19)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: JuntraColors.gold.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text('PREMIUM · ราศีพิจิก',
              style: TextStyle(
                fontSize: 10, color: JuntraColors.gold,
                fontWeight: FontWeight.w700, letterSpacing: 1.4,
              )),
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(child: _Stat(value: '47', label: 'ครั้งที่ดู')),
        Expanded(child: _Stat(value: '128', label: 'วันสมาชิก')),
        Expanded(child: _Stat(value: '480', label: 'แต้ม')),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: baiJamjuree(size: 22, color: JuntraColors.gold)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(
            fontSize: 11, color: JuntraColors.textMuted)),
      ],
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.icon, required this.iconColor,
    required this.title, required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(JuntraRadius.card),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(JuntraRadius.card),
          border: Border.all(color: iconColor.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600,
                    color: JuntraColors.textCream,
                  )),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(
                    fontSize: 11, color: JuntraColors.textMuted,
                  )),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: JuntraColors.gold),
          ],
        ),
      ),
    );
  }
}

class _VersionFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (_, snap) {
        final v = snap.data == null ? '...' : 'v${snap.data!.version}';
        return Column(
          children: [
            Text('จันทราพยากรณ์ · $v',
                style: const TextStyle(
                  fontSize: 11, color: JuntraColors.textFaint,
                )),
            const SizedBox(height: 8),
            const XmanStudioFooter(),
          ],
        );
      },
    );
  }
}
