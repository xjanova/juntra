import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../shared/data/fortune_categories.dart';
import '../../shared/widgets/starry_background.dart';

/// Screen 8 — History. Filter chips + grouped past readings.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _filter = 'all';
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const StarryBackground(density: 30, intensity: 0.4),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left,
                            color: JuntraColors.gold, size: 28),
                        onPressed: () => context.canPop() ? context.pop() : context.go(Routes.home),
                      ),
                      Expanded(child: Text('ประวัติดูดวง', style: baiJamjuree(size: 19))),
                    ],
                  ),
                ),
                _filterRow(),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: 6,
                    itemBuilder: (_, i) {
                      final c = fortuneCategories[i % fortuneCategories.length];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(JuntraRadius.card),
                          border: Border.all(color: c.color.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38, height: 38,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: c.color.withValues(alpha: 0.18),
                              ),
                              alignment: Alignment.center,
                              child: Text(c.icon, style: TextStyle(
                                  fontSize: 18, color: c.color)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('ดวง${c.name} · 3 ใบ',
                                      style: const TextStyle(
                                        fontSize: 13, fontWeight: FontWeight.w600,
                                        color: JuntraColors.textCream,
                                      )),
                                  const SizedBox(height: 2),
                                  Text('${i + 1} วันก่อน · 14:32',
                                      style: const TextStyle(
                                        fontSize: 10, color: JuntraColors.textFaint,
                                      )),
                                ],
                              ),
                            ),
                            const Icon(Icons.star_border,
                                color: JuntraColors.textFaint),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterRow() {
    final filters = const [
      ('all', 'ทั้งหมด'), ('free', 'ฟรี'),
      ('premium', 'พรีเมียม'), ('star', 'สำคัญ'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: filters.map((f) {
          final selected = _filter == f.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () => setState(() => _filter = f.$1),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: selected ? JuntraColors.goldButtonGradient : null,
                  color: selected ? null : JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected
                        ? Colors.transparent
                        : JuntraColors.purple.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(f.$2, style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: selected ? JuntraColors.bgPurpleDeep : JuntraColors.textLavender,
                )),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
