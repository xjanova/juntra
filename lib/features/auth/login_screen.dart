import 'package:flutter/material.dart';
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
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final auth = ref.read(authControllerProvider.notifier);
      if (_signUp) {
        await auth.signUp(
          name: _name.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
          passwordConfirmation: _confirm.text,
        );
      } else {
        await auth.signIn(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
      if (!mounted) return;
      // Land on home — the auth state is now AuthAuthenticated.
      context.go(Routes.home);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'เกิดข้อผิดพลาด: $e');
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
                  ],
                  _Field(
                    label: 'อีเมล',
                    controller: _email,
                    icon: Icons.alternate_email,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
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
                      _signUp = !_signUp;
                      _error = null;
                    }),
                  ),
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
