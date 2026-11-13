import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Primary CTA — the web's `.btn-primary`: gold gradient pill, deep ink,
/// soft gold drop-glow that lifts on press.
class GoldButton extends StatefulWidget {
  const GoldButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.full = true,
    this.size = GoldButtonSize.md,
    this.disabled = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool full;
  final GoldButtonSize size;
  final bool disabled;

  @override
  State<GoldButton> createState() => _GoldButtonState();
}

class _GoldButtonState extends State<GoldButton> {
  bool _pressed = false;

  EdgeInsets get _padding => switch (widget.size) {
        GoldButtonSize.lg => const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        GoldButtonSize.sm => const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        _ => const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      };

  double get _fontSize => switch (widget.size) {
        GoldButtonSize.lg => 17,
        GoldButtonSize.sm => 13,
        _ => 15,
      };

  @override
  Widget build(BuildContext context) {
    final disabled = widget.disabled || widget.onPressed == null;
    // box-shadow: 0 12px 40px -8px rgba(231,201,122,.5) → hover .7
    final glow = _pressed && !disabled
        ? JuntraShadows.goldStrong
        : JuntraShadows.goldGlow;

    return GestureDetector(
      onTapDown: (_) => disabled ? null : setState(() => _pressed = true),
      onTapUp: (_) {
        if (disabled) return;
        setState(() => _pressed = false);
        widget.onPressed?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: widget.full ? double.infinity : null,
        padding: _padding,
        decoration: BoxDecoration(
          gradient: disabled
              ? const LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Color(0xFF4A3D27), Color(0xFF2A2116)],
                )
              : JuntraColors.goldButtonGradient,
          borderRadius: BorderRadius.circular(999),
          // inset 0 1px 0 rgba(255,255,255,.4) — the thin highlight on the top edge
          border: disabled
              ? null
              : const Border(top: BorderSide(color: Color(0x66FFFFFF), width: 0.8)),
          boxShadow: disabled ? const [] : glow,
        ),
        transform: _pressed && !disabled
            ? (Matrix4.identity()..translateByDouble(0.0, -1.0, 0.0, 1.0))
            : Matrix4.identity(),
        // ป้ายยาว (ปุ่มครึ่งจอ) หรือผู้ใช้ตั้งตัวอักษรใหญ่ = ย่อทั้งแถวลงพอดีปุ่ม
        // แทนที่จะล้นขอบ/ถูกตัดกลางคำ
        child: _FitLabel(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                IconTheme(
                  data: IconThemeData(
                    color: disabled ? _inkDisabled : _ink,
                    size: _fontSize + 2,
                  ),
                  child: widget.icon!,
                ),
                const SizedBox(width: 8),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: _fontSize,
                  fontWeight: FontWeight.w600,
                  color: disabled ? _inkDisabled : _ink,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.btn-primary` ink (#1a0e2e)
const _ink = Color(0xFF1A0E2E);
const _inkDisabled = Color(0xFF7A6A4A);

enum GoldButtonSize { sm, md, lg }

/// Secondary button — the web's `.btn-ghost`: gold hairline pill on a
/// translucent night fill, gold-2 text.
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.full = true,
  });
  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool full;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: full ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        decoration: BoxDecoration(
          color: JuntraColors.bgDeepest.withValues(alpha: 0.35),
          border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: _FitLabel(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                IconTheme(
                  data: const IconThemeData(color: JuntraColors.goldLight, size: 16),
                  child: icon!,
                ),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: JuntraColors.goldLight,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ไอคอน+ป้ายของปุ่ม: ขนาดจริงเมื่อพอดี ย่อลงทั้งแถวเมื่อกว้างเกินปุ่ม
/// (Center ให้ปุ่มเต็มความกว้างยังจัดกลางเหมือนเดิม และใช้ในแถวที่ไม่จำกัดกว้างได้)
class _FitLabel extends StatelessWidget {
  const _FitLabel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Center(child: FittedBox(fit: BoxFit.scaleDown, child: child));
}
