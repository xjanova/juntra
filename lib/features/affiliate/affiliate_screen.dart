import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../shared/widgets/starry_background.dart';

/// Screen 11 — Affiliate Network. Earnings hero, downline tree, referral.
class AffiliateScreen extends StatelessWidget {
  const AffiliateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const StarryBackground(density: 30, intensity: 0.4),
          SafeArea(
            child: Column(
              children: [
                _Header(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      _EarningsHero(),
                      const SizedBox(height: 12),
                      _LevelStats(),
                      const SizedBox(height: 16),
                      Text('สายงานของลูก', style: baiJamjuree(size: 16)),
                      const SizedBox(height: 8),
                      _DownlineNode(name: 'คุณมาลี (You)', count: 47, level: 0),
                      _DownlineNode(name: 'พี่นกฟ้า', count: 12, level: 1),
                      _DownlineNode(name: 'พี่ดาว', count: 8, level: 1),
                      _DownlineNode(name: 'น้องมิ้นท์', count: 5, level: 2),
                      const SizedBox(height: 16),
                      _ReferralBox(),
                    ],
                  ),
                ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: JuntraColors.gold, size: 28),
            onPressed: () => context.go(Routes.profile),
          ),
          Expanded(child: Text('ระบบสายงาน Affiliate', style: baiJamjuree(size: 18))),
        ],
      ),
    );
  }
}

class _EarningsHero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: JuntraColors.purpleCardGradient,
        borderRadius: BorderRadius.circular(JuntraRadius.hero),
        border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.4)),
        boxShadow: const [
          BoxShadow(color: Color(0x99000000), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('รายได้สะสม', style: TextStyle(
            fontSize: 10, letterSpacing: 2.4,
            color: JuntraColors.textFaint, fontWeight: FontWeight.w500,
          )),
          const SizedBox(height: 6),
          Text('฿18,420', style: baiJamjuree(size: 32, color: JuntraColors.gold)),
          const SizedBox(height: 12),
          Row(
            children: const [
              Expanded(child: _MiniStat(label: 'เดือนนี้', value: '฿4,250', up: true)),
              SizedBox(width: 8),
              Expanded(child: _MiniStat(label: 'เดือนที่แล้ว', value: '฿3,180', up: false)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, required this.up});
  final String label;
  final String value;
  final bool up;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: JuntraColors.bgDeepest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(
            fontSize: 10, color: JuntraColors.textFaint,
          )),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(value, style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700,
                color: JuntraColors.textCream,
              )),
              const SizedBox(width: 4),
              Icon(up ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 12,
                  color: up ? JuntraColors.mintGreen : Colors.redAccent),
            ],
          ),
        ],
      ),
    );
  }
}

class _LevelStats extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(child: _BoxStat(value: '5', label: 'ระดับ')),
        SizedBox(width: 8),
        Expanded(child: _BoxStat(value: '47', label: 'สายงาน')),
        SizedBox(width: 8),
        Expanded(child: _BoxStat(value: '32', label: 'ใช้งาน')),
      ],
    );
  }
}

class _BoxStat extends StatelessWidget {
  const _BoxStat({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(value, style: baiJamjuree(size: 22, color: JuntraColors.gold)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(
              fontSize: 11, color: JuntraColors.textMuted)),
        ],
      ),
    );
  }
}

class _DownlineNode extends StatelessWidget {
  const _DownlineNode({required this.name, required this.count, required this.level});
  final String name;
  final int count;
  final int level;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(level * 18.0, 4, 0, 4),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(JuntraRadius.card),
          border: Border.all(color: JuntraColors.purple.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [JuntraColors.bgPurpleLight, JuntraColors.bgPurple],
                ),
              ),
              alignment: Alignment.center,
              child: Text(name.substring(0, 1), style: const TextStyle(
                color: JuntraColors.gold, fontWeight: FontWeight.w700,
              )),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600,
                    color: JuntraColors.textCream,
                  )),
                  Text('$count คนในสายงาน', style: const TextStyle(
                    fontSize: 10, color: JuntraColors.textMuted,
                  )),
                ],
              ),
            ),
            Text('฿${count * 90}', style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700,
              color: JuntraColors.mintGreen,
            )),
          ],
        ),
      ),
    );
  }
}

class _ReferralBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: JuntraColors.mysticHeroGradient,
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ลิงก์เชิญเพื่อน', style: baiJamjuree(size: 14)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: JuntraColors.bgDeepest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'juntra.app/r/MALI42',
                    style: TextStyle(
                      fontSize: 13, color: JuntraColors.textCream,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                Icon(Icons.copy, size: 16, color: JuntraColors.gold),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
