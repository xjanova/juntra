import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';

/// Shared bottom tab bar (Home · History · Chat · Profile).
///
/// Used as the `bottomNavigationBar` on every top-level tab screen so the
/// tabs actually switch from anywhere — previously only HomeScreen carried
/// it, which trapped the user (e.g. History → Chat was impossible without
/// backing out to Home first). Tabs use `context.go` to swap the top-level
/// location.
class JuntraTabBar extends StatelessWidget {
  const JuntraTabBar({super.key, required this.currentIndex});
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: JuntraColors.bgDeepest.withValues(alpha: 0.85),
        border: Border(top: BorderSide(
          color: JuntraColors.gold.withValues(alpha: 0.2),
        )),
      ),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _TabIcon(icon: Icons.home_filled, label: 'หน้าแรก', selected: currentIndex == 0,
              onTap: () => _goIfNeeded(context, 0, Routes.home)),
          _TabIcon(icon: Icons.history, label: 'ประวัติ', selected: currentIndex == 1,
              onTap: () => _goIfNeeded(context, 1, Routes.history)),
          _TabIcon(icon: Icons.auto_awesome, label: 'แม่หมอ', selected: currentIndex == 2,
              onTap: () => _goIfNeeded(context, 2, Routes.chat)),
          _TabIcon(icon: Icons.person, label: 'โปรไฟล์', selected: currentIndex == 3,
              onTap: () => _goIfNeeded(context, 3, Routes.profile)),
        ],
      ),
    );
  }

  // Don't re-navigate to the tab we're already on (avoids a needless rebuild).
  void _goIfNeeded(BuildContext context, int index, String route) {
    if (index != currentIndex) context.go(route);
  }
}

class _TabIcon extends StatelessWidget {
  const _TabIcon({
    required this.icon, required this.label,
    required this.selected, required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final color = selected ? JuntraColors.gold : JuntraColors.textFaint;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(
              fontSize: 10, color: color,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            )),
          ],
        ),
      ),
    );
  }
}
