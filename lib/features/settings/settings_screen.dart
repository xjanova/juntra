import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/tarot_catalog_repository.dart';
import '../../shared/widgets/starry_background.dart';
import '../../shared/widgets/xman_studio_footer.dart';
import '../update/check_for_update.dart';

/// Shared-preferences key for the notification opt-in. Read by the push
/// layer once it exists; persisted here so the choice survives reinstalls
/// of the widget tree.
const kPrefNotificationsEnabled = 'juntra_notifications_enabled';

/// Screen — Settings. Only exposes controls that actually do something:
/// a persisted notifications toggle, a real update check, and honest
/// (locked) language/theme info — the app ships Thai + dark only for now,
/// so those are shown as facts, not fake switches.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _notifications = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _notifications = prefs.getBool(kPrefNotificationsEnabled) ?? true;
      _loaded = true;
    });
  }

  Future<void> _setNotifications(bool v) async {
    setState(() => _notifications = v); // optimistic
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kPrefNotificationsEnabled, v);
  }

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
                const _Header(),
                const SizedBox(height: 12),
                const _SectionLabel('การใช้งาน'),
                _SwitchTile(
                  icon: Icons.notifications_outlined,
                  iconColor: JuntraColors.gold,
                  title: 'การแจ้งเตือน',
                  subtitle: 'ข่าวสาร โปรโมชั่น และดวงประจำวัน',
                  value: _notifications,
                  enabled: _loaded,
                  onChanged: _setNotifications,
                ),
                const SizedBox(height: 14),
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
                const SizedBox(height: 14),
                const _SectionLabel('เกี่ยวกับ'),
                _ActionTile(
                  icon: Icons.system_update_outlined,
                  iconColor: JuntraColors.mintGreen,
                  title: 'ตรวจสอบอัปเดต',
                  subtitle: 'อัปเดตให้ทันสมัยอยู่เสมอ',
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
            fontSize: 11, letterSpacing: 1.8,
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

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon, required this.iconColor,
    required this.title, required this.subtitle,
    required this.value, required this.enabled, required this.onChanged,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    return _TileShell(
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
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeTrackColor: JuntraColors.gold,
          ),
        ],
      ),
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
