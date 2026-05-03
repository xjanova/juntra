import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Small chip / badge — used for "ไพ่ประจำวัน", spread categories, etc.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.background,
    this.outlined = false,
  });
  final String label;
  final Widget? icon;
  final Color? color;
  final Color? background;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? JuntraColors.gold;
    final bg = background ?? fg.withValues(alpha: 0.12);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : bg,
        border: Border.all(color: fg.withValues(alpha: outlined ? 0.6 : 0.25)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            IconTheme(data: IconThemeData(size: 12, color: fg), child: icon!),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
