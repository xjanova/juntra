import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/auth/auth_state.dart';
import '../../shared/widgets/chantra_logo.dart';
import '../../shared/widgets/gold_button.dart';
import '../../shared/widgets/starry_background.dart';

/// Sign-in / sign-up — single screen, toggle between modes.
///
/// Backed by /v1/auth/login and /v1/auth/register on juntraweb. The
/// returned bearer token is persisted in flutter_secure_storage by
/// [ApiClient.setToken] (same scheme as thaipromptapp), so a relaunch
/// of the app picks up the existing session in [AuthController._bootstrap].
///
/// **อีเมลหรือเบอร์โทรก็ได้** — ต้องตรงกับเว็บทุกประการ เว็บยอมให้สมัครด้วย
/// เบอร์อย่างเดียวแล้วสร้างอีเมลภายในให้เงียบ ๆ (`p08xxxxxxxx@phone.juntra.local`)
/// ซึ่งเจ้าตัวไม่มีทางรู้ ตอนที่หน้านี้ยังบังคับอีเมล ลูกค้ากลุ่มนั้น
/// (ผู้สูงอายุ = ลูกค้าหลักของแบรนด์) สมัครทางเว็บแล้วเข้าแอพไม่ได้เลย
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _signUp = false;
  bool _busy = false;
  String? _error;

  final _name = TextEditingController();

  /// โหมดเข้าสู่ระบบ: ช่องเดียว รับได้ทั้งอีเมลและเบอร์
  final _login = TextEditingController();

  /// โหมดสมัคร: แยกสองช่อง เพราะเซิร์ฟเวอร์เก็บคนละคอลัมน์
  final _email = TextEditingController();
  final _phone = TextEditingController();

  final _password = TextEditingController();
  final _confirm = TextEditingController();

  /// โค้ดผู้แนะนำ (ถ้ามี) — ผูกสายงาน MLM ตั้งแต่ตอนสมัคร
  final _referral = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _login.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    _referral.dispose();
    super.dispose();
  }

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// เบอร์ไทยที่ยอมรับ — ตรงกับ `PhoneNumber::normalise()` ฝั่งเซิร์ฟเวอร์
  /// (เหลือเฉพาะตัวเลข, +66 → 0, ต้องยาว 9–32 หลัก) ถ้าเกณฑ์สองฝั่งไม่ตรงกัน
  /// จะเกิดบัญชีที่ "สมัครผ่านแต่ล็อกอินไม่ได้" แบบที่เคยเกิดมาแล้ว
  static String? _normalisePhone(String raw) {
    if (raw.trim().isEmpty || raw.contains('@')) return null;
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('66') && digits.length >= 11) {
      digits = '0${digits.substring(2)}';
    }
    if (digits.length < 9 || digits.length > 32) return null;
    return digits;
  }

  /// Client-side pre-validation so blank/invalid fields never round-trip to
  /// the API and come back as a raw server error. Returns a Thai message or
  /// null when the form is good to submit.
  String? _validate() {
    final password = _password.text;

    if (!_signUp) {
      final login = _login.text.trim();
      if (login.isEmpty) return 'กรุณากรอกอีเมลหรือเบอร์โทรศัพท์';
      final looksEmail = login.contains('@');
      if (looksEmail && !_emailPattern.hasMatch(login)) {
        return 'รูปแบบอีเมลไม่ถูกต้อง';
      }
      if (!looksEmail && _normalisePhone(login) == null) {
        return 'เบอร์โทรศัพท์ไม่ถูกต้อง เช่น 0812345678';
      }
      if (password.isEmpty) return 'กรุณากรอกรหัสผ่าน';
      return null;
    }

    if (_name.text.trim().isEmpty) {
      return 'กรุณากรอกชื่อที่จะให้แม่หมอเรียก';
    }

    final email = _email.text.trim();
    final phone = _phone.text.trim();
    if (email.isEmpty && phone.isEmpty) {
      return 'กรุณากรอกอีเมล หรือเบอร์โทรศัพท์อย่างใดอย่างหนึ่ง';
    }
    if (email.isNotEmpty && !_emailPattern.hasMatch(email)) {
      return 'รูปแบบอีเมลไม่ถูกต้อง';
    }
    if (phone.isNotEmpty && _normalisePhone(phone) == null) {
      return 'เบอร์โทรศัพท์ไม่ถูกต้อง เช่น 0812345678';
    }
    if (password.isEmpty) return 'กรุณากรอกรหัสผ่าน';
    if (password.length < 8) return 'รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร';
    if (password != _confirm.text) {
      return 'รหัสผ่านและการยืนยันไม่ตรงกัน';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final validationError = _validate();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final auth = ref.read(authControllerProvider.notifier);
      if (_signUp) {
        await auth.signUp(
          name: _name.text.trim(),
          email: _email.text.trim(),
          phone: _normalisePhone(_phone.text.trim()),
          password: _password.text,
          passwordConfirmation: _confirm.text,
          referralCode: _referral.text
              .trim()
              .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), ''),
        );
      } else {
        await auth.signIn(
          login: _login.text.trim(),
          password: _password.text,
        );
      }
      if (!mounted) return;
      // Land on home — the auth state is now AuthAuthenticated.
      context.go(Routes.home);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      // Never surface the raw exception (may carry internal detail/URLs).
      if (kDebugMode) debugPrint('[Login] unexpected: $e');
      setState(() => _error = 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const StarryBackground(density: 60, intensity: 0.8),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  const ChantraLogo(size: ChantraLogoSize.md)
                      .animate().fadeIn(duration: 500.ms),
                  const SizedBox(height: 18),
                  Text(
                    _signUp ? 'สมัครสมาชิก' : 'เข้าสู่ระบบ',
                    style: baiJamjuree(size: 24),
                  ).animate().fadeIn(duration: 500.ms, delay: 100.ms),
                  const SizedBox(height: 6),
                  Text(
                    _signUp
                        ? 'เพื่อเก็บประวัติคำทำนาย และสนทนากับแม่หมอ'
                        : 'ลงชื่อเข้าใช้เพื่อสนทนากับแม่หมอ',
                    style: const TextStyle(
                      fontSize: 12, color: JuntraColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (_signUp) ...[
                    _Field(
                      label: 'ชื่อที่จะให้แม่หมอเรียก',
                      controller: _name,
                      icon: Icons.person_outline,
                    ),
                    const SizedBox(height: 12),
                    _Field(
                      label: 'อีเมล',
                      controller: _email,
                      icon: Icons.alternate_email,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 10),
                    const _OrDivider(),
                    const SizedBox(height: 10),
                    _Field(
                      label: 'เบอร์โทรศัพท์',
                      controller: _phone,
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'กรอกอย่างใดอย่างหนึ่งก็พอ · ถ้าไม่มีอีเมล ใช้เบอร์โทรเข้าระบบได้เลย',
                      style: TextStyle(
                        fontSize: 11, color: JuntraColors.textFaint, height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    _Field(
                      label: 'อีเมล หรือ เบอร์โทรศัพท์',
                      controller: _login,
                      icon: Icons.person_outline,
                      // ไม่ล็อกเป็นคีย์บอร์ดอีเมล เพราะช่องนี้พิมพ์เบอร์ก็ได้
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                  ],
                  _Field(
                    label: 'รหัสผ่าน',
                    controller: _password,
                    icon: Icons.lock_outline,
                    obscure: true,
                  ),
                  if (_signUp) ...[
                    const SizedBox(height: 12),
                    _Field(
                      label: 'ยืนยันรหัสผ่าน',
                      controller: _confirm,
                      icon: Icons.lock_outline,
                      obscure: true,
                    ),
                    const SizedBox(height: 12),
                    _Field(
                      label: 'โค้ดผู้แนะนำ (ถ้ามี)',
                      controller: _referral,
                      icon: Icons.card_giftcard_outlined,
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0x33FF6B47),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x66FF6B47)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              size: 18, color: Color(0xFFFFB59A)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_error!,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFFFFD9C5),
                                  height: 1.4,
                                )),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  GoldButton(
                    label: _busy
                        ? 'กำลังดำเนินการ...'
                        : (_signUp ? 'สมัครสมาชิก' : 'เข้าสู่ระบบ'),
                    icon: const Text('✦', style: TextStyle(fontSize: 14)),
                    size: GoldButtonSize.lg,
                    disabled: _busy,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: 12),
                  GhostButton(
                    label: _signUp
                        ? 'มีบัญชีอยู่แล้ว · เข้าสู่ระบบ'
                        : 'ยังไม่มีบัญชี · สมัครสมาชิก',
                    onPressed: () => setState(() {
                      // ยกสิ่งที่พิมพ์ไว้ข้ามโหมดให้ ไม่ต้องพิมพ์ใหม่
                      if (_signUp) {
                        final typed = _email.text.trim().isNotEmpty
                            ? _email.text.trim()
                            : _phone.text.trim();
                        if (typed.isNotEmpty) _login.text = typed;
                      } else {
                        final typed = _login.text.trim();
                        if (typed.contains('@')) {
                          _email.text = typed;
                        } else if (typed.isNotEmpty) {
                          _phone.text = typed;
                        }
                      }
                      _signUp = !_signUp;
                      _error = null;
                    }),
                  ),
                  if (!_signUp) ...[
                    const SizedBox(height: 10),
                    TextButton(
                      // ทางออกเดียวของสองกลุ่ม: คนที่ลืมรหัส และคนที่สมัคร
                      // ทางเว็บด้วย Facebook/LINE (SSO ตั้งรหัสสุ่มให้ 40 ตัว
                      // เจ้าตัวไม่มีทางรู้) — เดิมแอพไม่มีลิงก์พาไปเลย = ทางตัน
                      onPressed: () => launchUrl(
                        Uri.parse('https://xn--82c4af5bzdj.online/forgot-password'),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: const Text(
                        'ลืมรหัสผ่าน? · เคยสมัครด้วย Facebook / LINE',
                        style: TextStyle(fontSize: 12, color: JuntraColors.textMuted),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  TextButton(
                    onPressed: () => context.go(Routes.home),
                    child: const Text(
                      'ลองดูก่อน (ไม่ต้องเข้าสู่ระบบ)',
                      style: TextStyle(
                        fontSize: 12, color: JuntraColors.textFaint,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// เส้นคั่น "หรือ" ระหว่างช่องอีเมลกับช่องเบอร์ตอนสมัคร — บอกด้วยสายตาว่า
/// สองช่องนี้เลือกกรอกอันเดียวก็ได้ ไม่ใช่ต้องกรอกทั้งคู่
class _OrDivider extends StatelessWidget {
  const _OrDivider();
  @override
  Widget build(BuildContext context) {
    final line = Expanded(
      child: Container(
        height: 1,
        color: JuntraColors.purple.withValues(alpha: 0.25),
      ),
    );
    return Row(
      children: [
        line,
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text('หรือ', style: TextStyle(
            fontSize: 11, color: JuntraColors.textFaint,
          )),
        ),
        line,
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.icon,
    this.obscure = false,
    this.keyboardType,
  });
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: JuntraColors.textCream, fontSize: 14),
      cursorColor: JuntraColors.gold,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: JuntraColors.textFaint, fontSize: 13,
        ),
        prefixIcon: Icon(icon, color: JuntraColors.textFaint, size: 18),
        filled: true,
        fillColor: JuntraColors.bgPurpleDeep.withValues(alpha: 0.6),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: JuntraColors.purple.withValues(alpha: 0.4),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: JuntraColors.purple.withValues(alpha: 0.4),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: JuntraColors.gold, width: 1.5),
        ),
      ),
    );
  }
}
