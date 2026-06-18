import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/fortune_repository.dart';
import '../../core/auth/auth_state.dart';
import '../../shared/widgets/juntra_tab_bar.dart';
import '../../shared/widgets/starry_background.dart';

/// Screen 8 — History. Filter chips (by reading type) + reverse-chrono
/// list backed by `GET /v1/history/readings`. Tapping a tile opens the
/// detail screen at `/reading?id=<id>`.
///
/// For guests we show a sign-in prompt instead of a (necessarily empty)
/// list — history lives server-side keyed by user id, so without a
/// session there's literally nothing to show.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

/// Backend type → (chip label, friendly title, icon, tint).
const Map<String, _TypeMeta> _typeMeta = {
  'tarot_single':   _TypeMeta('ไพ่ใบเดียว',  '✦', JuntraColors.gold),
  'tarot_three':    _TypeMeta('ทาโรต์ 3 ใบ', '✦', JuntraColors.gold),
  'tarot_love':     _TypeMeta('ความรัก',     '♥', Color(0xFFFF6B9D)),
  'tarot_career':   _TypeMeta('การงาน-เงิน', '✦', JuntraColors.gold),
  'tarot_decision': _TypeMeta('ทางแยก',      '✧', JuntraColors.purpleBright),
  'tarot_celtic':   _TypeMeta('เซลติกครอส',   '✧', JuntraColors.purpleBright),
  'tarot_year':     _TypeMeta('ดวง 12 เดือน', '☾', JuntraColors.gold),
  'numerology':     _TypeMeta('เลขศาสตร์',    '⊛', JuntraColors.mintGreen),
  'palmistry':      _TypeMeta('ดูลายมือ',     '✋', JuntraColors.gold),
  'auspicious':     _TypeMeta('ฤกษ์ยาม',     '☼', JuntraColors.cyan),
};

class _TypeMeta {
  const _TypeMeta(this.label, this.icon, this.color);
  final String label;
  final String icon;
  final Color color;
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String? _filter; // null = all

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final history = ref.watch(fortuneHistoryProvider);

    return Scaffold(
      bottomNavigationBar: const JuntraTabBar(currentIndex: 1),
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
                        onPressed: () =>
                            context.canPop() ? context.pop() : context.go(Routes.home),
                      ),
                      Expanded(child: Text('ประวัติดูดวง', style: baiJamjuree(size: 19))),
                      IconButton(
                        icon: const Icon(Icons.refresh,
                            color: JuntraColors.textFaint, size: 22),
                        tooltip: 'รีเฟรช',
                        onPressed: () => ref.invalidate(fortuneHistoryProvider),
                      ),
                    ],
                  ),
                ),
                if (auth is AuthAuthenticated) _filterRow(),
                if (auth is AuthAuthenticated) const SizedBox(height: 8),
                Expanded(
                  child: auth is! AuthAuthenticated
                      ? _guestPrompt()
                      : history.when(
                          loading: () => const Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(JuntraColors.gold),
                            ),
                          ),
                          error: (e, _) => _errorState(e),
                          data: _renderList,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── States ────────────────────────────────────────────────

  Widget _guestPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔐', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text('เข้าสู่ระบบเพื่อดูประวัติ',
                style: baiJamjuree(size: 18, color: JuntraColors.gold)),
            const SizedBox(height: 8),
            const Text(
              'ประวัติการดูดวงของลูกจะถูกเก็บไว้บนเซิร์ฟเวอร์อย่างปลอดภัย — เข้าสู่ระบบเพื่อดูคำทำนายที่ผ่านมาได้ทุกเมื่อ',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13, color: JuntraColors.textMuted, height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 200,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: JuntraColors.gold,
                  foregroundColor: JuntraColors.bgPurpleDeep,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => context.push(Routes.login),
                child: const Text('เข้าสู่ระบบ',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorState(Object e) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off,
                color: JuntraColors.textFaint, size: 48),
            const SizedBox(height: 12),
            const Text(
              'โหลดประวัติไม่สำเร็จ',
              style: TextStyle(
                fontSize: 14, color: JuntraColors.textCream,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              e.toString(),
              maxLines: 2, overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11, color: JuntraColors.textFaint,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                backgroundColor: JuntraColors.bgPurpleDeep,
                foregroundColor: JuntraColors.gold,
              ),
              onPressed: () => ref.invalidate(fortuneHistoryProvider),
              child: const Text('ลองใหม่'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _renderList(List<dynamic> all) {
    // Client-side type filter — the GET endpoint accepts `?type=` but
    // for the chip switcher we already have the full first-page set
    // cached, so filtering locally avoids a refetch per chip tap.
    final rows = _filter == null
        ? all
        : all.where((r) => (r is Map && r['type'] == _filter)).toList();

    if (rows.isEmpty) {
      return _emptyState();
    }

    return RefreshIndicator(
      color: JuntraColors.gold,
      backgroundColor: JuntraColors.bgPurpleDeep,
      onRefresh: () async {
        ref.invalidate(fortuneHistoryProvider);
        // Wait one frame so the indicator dismisses cleanly.
        await Future<void>.delayed(const Duration(milliseconds: 300));
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: rows.length,
        itemBuilder: (_, i) {
          final r = rows[i];
          if (r is! Map) return const SizedBox.shrink();
          return _ReadingTile(reading: r);
        },
      ),
    );
  }

  Widget _emptyState() {
    return SingleChildScrollView(
      // Wrap in scroll so RefreshIndicator still works on the empty state.
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(
        height: 400,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🔮', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 16),
                Text(
                  _filter == null ? 'ยังไม่มีคำทำนาย' : 'ยังไม่มีคำทำนายประเภทนี้',
                  style: baiJamjuree(size: 16, color: JuntraColors.gold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'เริ่มเปิดไพ่ครั้งแรกของลูกจากหน้าแรก แม่หมอจะบันทึกคำทำนายให้อ่านย้อนหลังได้',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13, color: JuntraColors.textMuted, height: 1.5,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: JuntraColors.gold,
                    foregroundColor: JuntraColors.bgPurpleDeep,
                  ),
                  onPressed: () => context.go(Routes.home),
                  child: const Text('เริ่มเปิดไพ่'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Filter chips ──────────────────────────────────────────

  Widget _filterRow() {
    // Filter set is limited to types we currently render. Chat / numerology
    // are tracked but not yet rendered as cards, so only show the chips
    // for types that have data shown on this screen.
    final entries = <(String?, String)>[
      (null, 'ทั้งหมด'),
      ('tarot_single', 'ไพ่ใบเดียว'),
      ('tarot_three', 'ทาโรต์ 3 ใบ'),
      ('tarot_love', 'ความรัก'),
      ('tarot_career', 'การงาน-เงิน'),
      ('tarot_decision', 'ทางแยก'),
      ('tarot_celtic', 'เซลติกครอส'),
      ('tarot_year', 'ดวง 12 เดือน'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: entries.map((f) {
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

/// One row in the history list. The backend gives us `{id, type, preview,
/// created_at}` — we render type metadata, the first 140 chars of the AI
/// interpretation, and a relative timestamp ("3 ชั่วโมงก่อน").
class _ReadingTile extends StatelessWidget {
  const _ReadingTile({required this.reading});
  final Map reading;

  @override
  Widget build(BuildContext context) {
    final type = reading['type']?.toString() ?? '';
    final meta = _typeMeta[type] ?? const _TypeMeta('คำทำนาย', '✦', JuntraColors.gold);
    final id = (reading['id'] as num?)?.toInt();
    final preview = reading['preview']?.toString() ?? '';
    final relative = _relativeTime(reading['created_at']?.toString());

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(JuntraRadius.card),
          onTap: id == null ? null : () => context.push('${Routes.reading}?id=$id'),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(JuntraRadius.card),
              border: Border.all(color: meta.color.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: meta.color.withValues(alpha: 0.18),
                  ),
                  alignment: Alignment.center,
                  child: Text(meta.icon, style: TextStyle(
                      fontSize: 18, color: meta.color)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(meta.label,
                                style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600,
                                  color: JuntraColors.textCream,
                                )),
                          ),
                          if (relative != null)
                            Text(relative,
                                style: const TextStyle(
                                  fontSize: 10, color: JuntraColors.textFaint,
                                )),
                        ],
                      ),
                      if (preview.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          preview,
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5, color: JuntraColors.textLavender,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right,
                    color: JuntraColors.gold, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Format `created_at` (ISO 8601) as a Thai relative time. Falls back
  /// to absolute date if older than a week so the tiles stay scannable.
  static String? _relativeTime(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return null;
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'เมื่อสักครู่';
    if (diff.inMinutes < 60) return '${diff.inMinutes} นาทีก่อน';
    if (diff.inHours < 24) return '${diff.inHours} ชั่วโมงก่อน';
    if (diff.inDays < 7) return '${diff.inDays} วันก่อน';
    try {
      return DateFormat('d MMM', 'th').format(dt);
    } catch (_) {
      return DateFormat('d MMM').format(dt);
    }
  }
}
