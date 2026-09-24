import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/app_config_repository.dart';
import '../../core/auth/auth_state.dart';
import '../../shared/widgets/gold_button.dart';
import '../../shared/widgets/starry_background.dart';

/// ลบบัญชีและข้อมูลส่วนตัว — ทำได้ในแอพ (Google Play บังคับ) ไม่ต้องออกไปเว็บ
///
/// เดิมปุ่มนี้พาไปหน้า /profile บนเว็บซึ่งต้องล็อกอินเว็บอีกรอบ และลบไม่ครบ (เบอร์ วันเกิด
/// คำถาม แชท รูปยังอยู่) — ตอนนี้เซิร์ฟเวอร์ลบครบตาม PDPA ในคำขอเดียว
/// ต้องยืนยันด้วยรหัสผ่าน + ติ๊กยอมรับ (การกระทำที่ย้อนไม่ได้ ต้องไม่เกิดจากการแตะพลาด)
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _password = TextEditingController();
  bool _understood = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_busy || !_understood) return;
    if (_password.text.isEmpty) {
      setState(() => _error = 'กรุณากรอกรหัสผ่านเพื่อยืนยัน');
      return;
    }
    // ถามซ้ำอีกชั้นก่อนลบจริง — ย้อนกลับไม่ได้
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JuntraColors.bgPurpleDeep,
        title: Text('ลบบัญชีถาวร?', style: baiJamjuree(size: 18, color: const Color(0xFFFF8FA0))),
        content: const Text(
          'ข้อมูลส่วนตัว คำทำนาย บทสนทนา และเครดิตคงเหลือจะหายทั้งหมด กู้คืนไม่ได้',
          style: TextStyle(color: JuntraColors.textLavender, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก', style: TextStyle(color: JuntraColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ลบบัญชีถาวร', style: TextStyle(color: Color(0xFFFF8FA0), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).deleteAccount(password: _password.text);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      context.go(Routes.home);
      messenger.showSnackBar(const SnackBar(
        content: Text('ลบบัญชีและข้อมูลของคุณเรียบร้อยแล้ว'),
        backgroundColor: JuntraColors.bgPurpleDeep,
        behavior: SnackBarBehavior.floating,
      ));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'เชื่อมต่อไม่สำเร็จ — บัญชียังไม่ถูกลบ กรุณาลองใหม่อีกครั้ง';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(appConfigValueProvider);
    final authed = ref.watch(authControllerProvider) is AuthAuthenticated;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const StarryBackground(density: 30, intensity: 0.4),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, color: JuntraColors.gold, size: 28),
                      onPressed: () => context.canPop() ? context.pop() : context.go(Routes.settings),
                    ),
                    Expanded(child: Text('ลบบัญชีและข้อมูล', style: baiJamjuree(size: 19))),
                  ],
                ),
                const SizedBox(height: 12),
                const _Card(children: [
                  Text('สิ่งที่จะถูกลบทันที', style: TextStyle(color: JuntraColors.gold, fontWeight: FontWeight.w700)),
                  SizedBox(height: 8),
                  _Bullet('ชื่อ อีเมล เบอร์โทร รหัสผ่าน และการเชื่อมต่อบัญชี'),
                  _Bullet('วันเกิดและข้อมูลโหราศาสตร์'),
                  _Bullet('คำถาม คำทำนาย และบทสนทนากับแม่หมอทั้งหมด'),
                  _Bullet('รูปที่อัปโหลด และเครดิตคงเหลือในบัญชี'),
                  _Bullet('การเข้าสู่ระบบทุกเครื่อง'),
                  SizedBox(height: 10),
                  Text('ที่เก็บต่อตามกฎหมาย (ไม่ผูกกับตัวตนของคุณ): รายการทางบัญชี เช่น ยอดและวันที่ของการเติม/ใช้เครดิต',
                      style: TextStyle(fontSize: 12, color: JuntraColors.textMuted, height: 1.5)),
                ]),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => launchUrl(Uri.parse(cfg.accountDeletionUrl), mode: LaunchMode.externalApplication),
                  child: const Text('อ่านรายละเอียดทั้งหมด', style: TextStyle(color: JuntraColors.gold)),
                ),
                const SizedBox(height: 6),
                if (!authed)
                  const _Card(children: [
                    Text('เข้าสู่ระบบก่อน แล้วกลับมาที่หน้านี้เพื่อลบบัญชี',
                        style: TextStyle(color: JuntraColors.textLavender)),
                  ])
                else ...[
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    enabled: !_busy,
                    style: const TextStyle(color: JuntraColors.textCream),
                    decoration: InputDecoration(
                      labelText: 'รหัสผ่านปัจจุบัน (เพื่อยืนยันตัวตน)',
                      labelStyle: const TextStyle(color: JuntraColors.textMuted),
                      filled: true,
                      fillColor: JuntraColors.bgDark2.withValues(alpha: 0.6),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            color: JuntraColors.textFaint, size: 20),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    value: _understood,
                    onChanged: _busy ? null : (v) => setState(() => _understood = v ?? false),
                    activeColor: const Color(0xFFFF8FA0),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('เข้าใจแล้วว่าลบแล้วกู้คืนไม่ได้ และเครดิตคงเหลือจะหายไปด้วย',
                        style: TextStyle(fontSize: 13, color: JuntraColors.textLavender)),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 6),
                    Text(_error!, style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 12.5)),
                  ],
                  const SizedBox(height: 14),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFB3261E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: (_busy || !_understood) ? null : _delete,
                    child: Text(_busy ? 'กำลังลบ...' : 'ลบบัญชีถาวร',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 8),
                  GhostButton(
                    label: 'ยกเลิก',
                    onPressed: _busy ? null : () => context.canPop() ? context.pop() : context.go(Routes.settings),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'เข้าสู่ระบบไม่ได้หรือจำรหัสผ่านไม่ได้? ส่งคำขอลบบัญชีมาที่ ${cfg.supportEmailDisplay}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11.5, color: JuntraColors.textFaint, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        border: Border.all(color: const Color(0xFFFF8FA0).withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ', style: TextStyle(color: Color(0xFFFF8FA0))),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: JuntraColors.textLavender, height: 1.45))),
        ],
      ),
    );
  }
}
