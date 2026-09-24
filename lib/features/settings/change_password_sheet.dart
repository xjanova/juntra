import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/auth/auth_state.dart';
import '../../shared/widgets/gold_button.dart';

/// เปลี่ยนรหัสผ่านในแอพ (เดิมต้องเปิดเว็บ) — เซิร์ฟเวอร์ออกจากระบบเครื่องอื่นให้ทั้งหมด
class ChangePasswordSheet extends ConsumerStatefulWidget {
  const ChangePasswordSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: JuntraColors.bgPurpleDeep,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const ChangePasswordSheet(),
    );
  }

  @override
  ConsumerState<ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<ChangePasswordSheet> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    // ตรวจในเครื่องก่อน — ข้อความภาษาไทยทันที ไม่ต้องรอเซิร์ฟเวอร์
    if (_current.text.isEmpty) {
      setState(() => _error = 'กรุณากรอกรหัสผ่านปัจจุบัน');
      return;
    }
    if (_next.text.length < 8) {
      setState(() => _error = 'รหัสผ่านใหม่ต้องยาวอย่างน้อย 8 ตัวอักษร');
      return;
    }
    if (_next.text != _confirm.text) {
      setState(() => _error = 'รหัสผ่านใหม่สองช่องไม่ตรงกัน');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).changePassword(
            currentPassword: _current.text,
            newPassword: _next.text,
            confirmation: _confirm.text,
          );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(
        content: Text('เปลี่ยนรหัสผ่านเรียบร้อยแล้ว · เครื่องอื่นถูกออกจากระบบให้แล้ว'),
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
        _error = 'เชื่อมต่อไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
      });
    }
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: JuntraColors.textMuted),
        filled: true,
        fillColor: JuntraColors.bgDark2.withValues(alpha: 0.6),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        suffixIcon: IconButton(
          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              color: JuntraColors.textFaint, size: 20),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      );

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: JuntraColors.textCream);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('เปลี่ยนรหัสผ่าน', style: baiJamjuree(size: 18, color: JuntraColors.gold)),
              const SizedBox(height: 14),
              TextField(controller: _current, obscureText: _obscure, enabled: !_busy, style: style,
                  decoration: _dec('รหัสผ่านปัจจุบัน')),
              const SizedBox(height: 10),
              TextField(controller: _next, obscureText: _obscure, enabled: !_busy, style: style,
                  decoration: _dec('รหัสผ่านใหม่ (อย่างน้อย 8 ตัว)')),
              const SizedBox(height: 10),
              TextField(controller: _confirm, obscureText: _obscure, enabled: !_busy, style: style,
                  decoration: _dec('ยืนยันรหัสผ่านใหม่')),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 12.5)),
              ],
              const SizedBox(height: 16),
              GoldButton(label: _busy ? 'กำลังบันทึก...' : 'บันทึกรหัสผ่านใหม่', onPressed: _busy ? null : _save),
            ],
          ),
        ),
      ),
    );
  }
}
