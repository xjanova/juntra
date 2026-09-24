import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/tarot_catalog_repository.dart';
import '../../shared/widgets/starry_background.dart';
import '../../shared/widgets/xman_studio_footer.dart';
import '../update/check_for_update.dart';
import '../../core/api/app_config_repository.dart';
import '../../core/app_channel.dart';
import '../../core/auth/auth_state.dart';
import '../../core/auth/thaiprompt_link.dart';
import 'change_password_sheet.dart';

/// Screen — Settings. Only exposes controls that actually do something:
/// account actions (in-app password change + account deletion — Google Play
/// requires deletion inside the app), the legal pages every store listing
/// links to, a real update check, and honest (locked) language/theme info.
///
/// The old notifications switch was removed: it saved a preference nothing
/// ever read (the app has no push layer), so it only pretended to work.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final cfg = ref.watch(appConfigValueProvider);
    final authed = auth is AuthAuthenticated;
    final linked = auth is AuthAuthenticated && auth.thaipromptLinked;

    Future<void> open(String url) =>
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

    return Scaffold(
      body: Stack(
        children: [
          const StarryBackground(density: 30, intensity: 0.4),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                const _Header(),
                const SizedBox(height: 12),
                const _SectionLabel('การแสดงผล'),
                const _InfoTile(
                  icon: Icons.language_outlined,
                  iconColor: JuntraColors.cyan,
                  title: 'ภาษา',
                  value: 'ไทย',
                ),
                const _InfoTile(
                  icon: Icons.dark_mode_outlined,
                  iconColor: JuntraColors.purpleBright,
                  title: 'ธีม',
                  value: 'มืด',
                ),
                if (authed) ...[
                  const SizedBox(height: 14),
                  const _SectionLabel('บัญชีของลูก'),
                  _ActionTile(
                    icon: Icons.password_outlined,
                    iconColor: JuntraColors.gold,
                    title: 'เปลี่ยนรหัสผ่าน',
                    subtitle: 'ออกจากระบบเครื่องอื่นให้อัตโนมัติ',
                    onTap: () => ChangePasswordSheet.show(context),
                  ),
                  if (!linked)
                    _ActionTile(
                      icon: Icons.link_outlined,
                      iconColor: JuntraColors.purpleBright,
                      title: 'เชื่อมต่อบัญชี Thaiprompt',
                      subtitle: 'เพื่อใช้ระบบสายงานแนะนำ',
                      onTap: () async {
                        final launched = await launchThaipromptLink(context, ref);
                        // กลับมาจากเบราว์เซอร์แล้วสถานะ "เชื่อมแล้ว" ต้องขึ้นเอง
                        if (launched) {
                          // ignore: unawaited_futures
                          Future<void>.delayed(const Duration(seconds: 3),
                              () => ref.read(authControllerProvider.notifier).refresh());
                        }
                      },
                    ),
                  _ActionTile(
                    icon: Icons.person_remove_outlined,
                    iconColor: const Color(0xFFFF6B6B),
                    title: 'ลบบัญชีและข้อมูล',
                    subtitle: 'ลบถาวรตามสิทธิ์ PDPA · ทำได้ในแอพทันที',
                    onTap: () => context.push(Routes.deleteAccount),
                  ),
                ],
                const SizedBox(height: 14),
                const _SectionLabel('ความเป็นส่วนตัวและข้อตกลง'),
                _ActionTile(
                  icon: Icons.privacy_tip_outlined,
                  iconColor: JuntraColors.mintGreen,
                  title: 'นโยบายความเป็นส่วนตัว',
                  subtitle: 'ข้อมูลที่เราเก็บ และสิทธิ์ของลูกตาม PDPA',
                  onTap: () => open(cfg.privacyUrl),
                ),
                _ActionTile(
                  icon: Icons.description_outlined,
                  iconColor: JuntraColors.cyan,
                  title: 'ข้อตกลงการใช้งาน',
                  subtitle: 'เงื่อนไขการใช้บริการและเครดิต',
                  onTap: () => open(cfg.termsUrl),
                ),
                _ActionTile(
                  icon: Icons.mail_outline_rounded,
                  iconColor: JuntraColors.gold,
                  title: 'ติดต่อเรา',
                  subtitle: cfg.supportEmailDisplay,
                  onTap: () => launchUrl(Uri(scheme: 'mailto', path: cfg.supportEmail)),
                ),
                const SizedBox(height: 14),
                const _SectionLabel('เกี่ยวกับ'),
                _ActionTile(
                  icon: Icons.system_update_outlined,
                  iconColor: JuntraColors.mintGreen,
                  title: 'ตรวจสอบอัปเดต',
                  subtitle: isPlayChannel ? 'อัปเดตผ่าน Google Play' : 'อัปเดตให้ทันสมัยอยู่เสมอ',
                  onTap: () => runManualUpdateCheck(context, ref),
                ),
                const _VersionTile(),
                const _CardArtTile(),
                const SizedBox(height: 20),
                const Center(child: XmanStudioFooter(showVersion: false)),
              ],
            ),
          ),
        ],
      ),
    );
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
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.profile),
        ),
        Expanded(child: Text('ตั้งค่า', style: baiJamjuree(size: 19))),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(text,
          style: const TextStyle(
            fontSize: 11,
            color: JuntraColors.textFaint, fontWeight: FontWeight.w600,
          )),
    );
  }
}

class _TileShell extends StatelessWidget {
  const _TileShell({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        border: Border.all(color: JuntraColors.purple.withValues(alpha: 0.2)),
      ),
      child: child,
    );
  }
}

class _LeadingIcon extends StatelessWidget {
  const _LeadingIcon({required this.icon, required this.color});
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: 20),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon, required this.iconColor,
    required this.title, required this.value,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;
  @override
  Widget build(BuildContext context) {
    return _TileShell(
      child: Row(
        children: [
          _LeadingIcon(icon: icon, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title, style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600,
              color: JuntraColors.textCream,
            )),
          ),
          Text(value, style: baiJamjuree(size: 13, color: JuntraColors.textMuted)),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon, required this.iconColor,
    required this.title, required this.subtitle, required this.onTap,
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
      child: _TileShell(
        child: Row(
          children: [
            _LeadingIcon(icon: icon, color: iconColor),
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

class _VersionTile extends StatelessWidget {
  const _VersionTile();
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (_, snap) {
        final v = snap.data == null
            ? '...'
            : '${snap.data!.version} (${snap.data!.buildNumber})';
        return _TileShell(
          child: Row(
            children: [
              const _LeadingIcon(
                  icon: Icons.info_outline, color: JuntraColors.textMuted),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('เวอร์ชัน', style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600,
                  color: JuntraColors.textCream,
                )),
              ),
              Text(v, style: baiJamjuree(size: 13, color: JuntraColors.textMuted)),
            ],
          ),
        );
      },
    );
  }
}

/// Diagnostic — whether this device pulled the real card art from
/// จันทรา.online. "NN/78 ใบ" = showing real faces; "ใช้ภาพวาดในแอพ" = couldn't
/// reach the web, so the built-in drawing is in use. Tap to retry the fetch.
class _CardArtTile extends ConsumerWidget {
  const _CardArtTile();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tarotCatalogProvider);
    final (String label, Color color) = switch (async) {
      AsyncData(:final value) when value.bySlug.isNotEmpty => (
          '${value.bySlug.values.where((a) => a.imageUrl != null).length}/${value.bySlug.length} ใบ',
          JuntraColors.mintGreen,
        ),
      AsyncData(:final value) when value.error != null =>
        ('ดึงไม่ได้: ${value.error}', JuntraColors.gold),
      AsyncLoading() => ('กำลังโหลด...', JuntraColors.textMuted),
      _ => ('ใช้ภาพวาดในแอพ', JuntraColors.gold),
    };
    return InkWell(
      onTap: () => ref.invalidate(tarotCatalogProvider),
      borderRadius: BorderRadius.circular(JuntraRadius.card),
      child: _TileShell(
        child: Row(
          children: [
            const _LeadingIcon(icon: Icons.style_outlined, color: JuntraColors.cyan),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('ภาพไพ่จากเว็บ', style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600,
                color: JuntraColors.textCream,
              )),
            ),
            Text(label, style: baiJamjuree(size: 13, color: color)),
          ],
        ),
      ),
    );
  }
}
