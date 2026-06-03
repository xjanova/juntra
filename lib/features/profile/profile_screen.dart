import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/auth/auth_state.dart';
import '../../shared/widgets/gold_button.dart';
import '../../shared/widgets/starry_background.dart';
import '../../shared/widgets/xman_studio_footer.dart';
import '../update/check_for_update.dart';

/// Screen 9 — Profile. Real identity from [authControllerProvider]
/// (name / email / wallet credit / Thaiprompt link), live menu navigation,
/// a working "ตรวจสอบอัปเดต", and sign-out. Guests get a sign-in CTA instead
/// of fabricated stats.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      body: Stack(
        children: [
          const StarryBackground(density: 30, intensity: 0.4),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                const _Header(),
                const SizedBox(height: 20),
                switch (auth) {
                  AuthUnknown() => const _LoadingBlock(),
                  AuthGuest() => const _GuestBlock(),
                  AuthAuthenticated(:final displayName, :final email,
                          :final walletBalance, :final walletCurrency,
                          :final thaipromptLinked) =>
                    _AccountBlock(
                      displayName: displayName,
                      email: email,
                      balance: walletBalance,
                      currency: walletCurrency,
                      linked: thaipromptLinked,
                    ),
                },
                const SizedBox(height: 20),
                _MenuCard(
                  icon: Icons.star_outline,
                  iconColor: JuntraColors.gold,
                  title: 'ผังดวงดาวเจ้าชะตา',
                  subtitle: 'ดวงเกิดของลูก คำนวณตามวันเวลา',
                  onTap: () => context.push(Routes.natal),
                ),
                _MenuCard(
                  icon: Icons.account_balance_wallet_outlined,
                  iconColor: JuntraColors.mintGreen,
                  title: 'วอลเลต',
                  subtitle: 'เครดิต เติมเงิน และประวัติการใช้',
                  onTap: () => context.push(Routes.wallet),
                ),
                _MenuCard(
                  icon: Icons.account_tree_outlined,
                  iconColor: JuntraColors.purpleBright,
                  title: 'ระบบสายงาน Affiliate',
                  subtitle: 'เครือข่ายและรายได้ของลูก',
                  onTap: () => context.push(Routes.affiliate),
                ),
                _MenuCard(
                  icon: Icons.settings_outlined,
                  iconColor: JuntraColors.textMuted,
                  title: 'ตั้งค่า',
                  subtitle: 'การแจ้งเตือน · ภาษา · ธีม',
                  onTap: () => context.push(Routes.settings),
                ),
                _MenuCard(
                  icon: Icons.system_update_outlined,
                  iconColor: JuntraColors.cyan,
                  title: 'ตรวจสอบอัปเดต',
                  subtitle: 'อัปเดตให้ทันสมัยอยู่เสมอ',
                  onTap: () => runManualUpdateCheck(context, ref),
                ),
                if (auth is AuthAuthenticated) ...[
                  const SizedBox(height: 8),
                  _SignOutTile(onTap: () => _confirmSignOut(context, ref)),
                ],
                const SizedBox(height: 16),
                const _VersionFooter(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JuntraColors.bgPurpleDeep,
        title: Text('ออกจากระบบ', style: baiJamjuree(size: 18)),
        content: const Text('ต้องการออกจากระบบใช่ไหม?',
            style: TextStyle(color: JuntraColors.textLavender)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก',
                style: TextStyle(color: JuntraColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ออกจากระบบ',
                style: TextStyle(color: JuntraColors.gold)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(authControllerProvider.notifier).signOut();
    if (!context.mounted) return;
    context.go(Routes.login);
  }
}

class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, color: JuntraColors.gold, size: 28),
          onPressed: () => context.canPop() ? context.pop() : context.go(Routes.home),
        ),
        Expanded(child: Text('โปรไฟล์', style: baiJamjuree(size: 19))),
      ],
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: CircularProgressIndicator(color: JuntraColors.gold),
      ),
    );
  }
}

class _GuestBlock extends StatelessWidget {
  const _GuestBlock();
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 92, height: 92,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: JuntraColors.bgPurpleDeep,
            border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.5), width: 2),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.person_outline,
              color: JuntraColors.gold, size: 40),
        ),
        const SizedBox(height: 12),
        Text('ผู้เยี่ยมชม', style: baiJamjuree(size: 19)),
        const SizedBox(height: 4),
        const Text('เข้าสู่ระบบเพื่อบันทึกดวงและเครดิตของลูก',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: JuntraColors.textMuted)),
        const SizedBox(height: 16),
        GoldButton(
          label: 'เข้าสู่ระบบ / สมัครสมาชิก',
          icon: const Icon(Icons.login, size: 18),
          onPressed: () => context.push(Routes.login),
        ),
      ],
    );
  }
}

class _AccountBlock extends StatelessWidget {
  const _AccountBlock({
    required this.displayName, required this.email,
    required this.balance, required this.currency, required this.linked,
  });
  final String displayName;
  final String? email;
  final double? balance;
  final String currency;
  final bool linked;

  @override
  Widget build(BuildContext context) {
    final initial = displayName.trim().isEmpty
        ? '?'
        : displayName.trim().substring(0, 1);
    final symbol = currency == 'THB' ? '฿' : currency;
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
          child: Text(initial, style: baiJamjuree(size: 40)),
        ),
        const SizedBox(height: 10),
        Text(displayName, style: baiJamjuree(size: 19)),
        if (email != null && email!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(email!,
              style: const TextStyle(fontSize: 12, color: JuntraColors.textMuted)),
        ],
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: (linked ? JuntraColors.mintGreen : JuntraColors.gold)
                .withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(linked ? 'เชื่อมต่อ Thaiprompt ✓' : 'สมาชิก',
              style: TextStyle(
                fontSize: 10,
                color: linked ? JuntraColors.mintGreen : JuntraColors.gold,
                fontWeight: FontWeight.w700, letterSpacing: 1.2,
              )),
        ),
        const SizedBox(height: 16),
        // Real wallet credit — taps through to the wallet screen.
        InkWell(
          onTap: () => context.push(Routes.wallet),
          borderRadius: BorderRadius.circular(JuntraRadius.card),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: JuntraColors.purpleCardGradient,
              borderRadius: BorderRadius.circular(JuntraRadius.card),
              border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, color: JuntraColors.gold, size: 20),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('เครดิตคงเหลือ',
                      style: TextStyle(fontSize: 13, color: JuntraColors.textLavender)),
                ),
                Text(
                  balance == null
                      ? '—'
                      : '$symbol${NumberFormat.decimalPattern('th').format(balance)}',
                  style: baiJamjuree(size: 20, color: JuntraColors.gold),
                ),
                const Icon(Icons.chevron_right, color: JuntraColors.gold),
              ],
            ),
          ),
        ),
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

class _SignOutTile extends StatelessWidget {
  const _SignOutTile({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(JuntraRadius.card),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(JuntraRadius.card),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
        ),
        child: const Row(
          children: [
            Icon(Icons.logout, color: Colors.redAccent, size: 20),
            SizedBox(width: 12),
            Text('ออกจากระบบ',
                style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600,
                  color: Colors.redAccent,
                )),
          ],
        ),
      ),
    );
  }
}

class _VersionFooter extends StatelessWidget {
  const _VersionFooter();
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
