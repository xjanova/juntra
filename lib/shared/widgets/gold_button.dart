import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Primary CTA — gold gradient, deep purple ink, glows on press.
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
    final glow = _pressed && !disabled
        ? <BoxShadow>[
            const BoxShadow(color: Color(0x80F0C75E), blurRadius: 24, spreadRadius: 0),
            const BoxShadow(color: Color(0x66D4A537), blurRadius: 20, offset: Offset(0, 8)),
          ]
        : <BoxShadow>[
            const BoxShadow(color: Color(0x4DD4A537), blurRadius: 14, offset: Offset(0, 4)),
          ];

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
                  colors: [Color(0xFF4A3A1F), Color(0xFF2A2010)],
                )
              : JuntraColors.goldButtonGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: disabled ? const [] : glow,
        ),
        transform: _pressed && !disabled
            ? (Matrix4.identity()..translate(0.0, 1.0))
            : Matrix4.identity(),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.icon != null) ...[
              IconTheme(
                data: IconThemeData(
                  color: disabled ? const Color(0xFF7A6A4A) : JuntraColors.bgPurpleDeep,
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
                color: disabled ? const Color(0xFF7A6A4A) : JuntraColors.bgPurpleDeep,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum GoldButtonSize { sm, md, lg }

/// Secondary outline button with subtle purple border + lavender text.
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
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: full ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        decoration: BoxDecoration(
          color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.4),
          border: Border.all(color: JuntraColors.purple.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              IconTheme(
                data: const IconThemeData(color: JuntraColors.textLavender, size: 16),
                child: icon!,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: JuntraColors.textLavender,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
