import 'dart:ui' as ui show TextDirection;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/affiliate_repository.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/endpoints.dart';
import '../../core/auth/auth_state.dart';
import '../../shared/widgets/starry_background.dart';

/// Depth accent colors — must match the web dashboard legend so both
/// surfaces read the same (root/direct = gold, then blue/violet/rose/mint).
const List<Color> _levelColors = [
  JuntraColors.gold,   // 0 — root (คุณ)
  JuntraColors.gold,   // 1 — สายตรง
  Color(0xFF9EC6F5),   // 2
  Color(0xFFB07CFF),   // 3
  Color(0xFFFF8FD4),   // 4
  Color(0xFF7EE0C3),   // 5+
];

Color _levelColor(int level) =>
    _levelColors[level.clamp(0, _levelColors.length - 1)];

/// Hard refresh = bust juntraweb's per-user MLM cache first (so the refetch
/// hits Thaiprompt live and totals are guaranteed current), THEN invalidate
/// the bundle to refetch. Used by the toolbar button and pull-to-refresh.
Future<void> _hardRefresh(WidgetRef ref) async {
  try {
    final repo = await ref.read(affiliateRepositoryProvider.future);
    await repo.refreshUpstream(); // swallows its own network errors
  } catch (_) {
    // Repo unavailable (e.g. mid-logout) — plain refetch below still runs.
  }
  try {
    ref.invalidate(affiliateBundleProvider);
  } catch (_) {
    // Screen disposed during the awaits above — nothing left to refresh.
  }
}

/// Screen 11 — Affiliate Network / MLM dashboard.
///
/// Three states:
///   1. **Authenticated + thaiprompt-linked** → KPI strip, expandable
///      network tree (ผังสายงาน — matches the web chart), monthly
///      earnings chart, recent commissions table, referral link with
///      QR + copy + LINE share.
///   2. **Authenticated, NOT thaiprompt-linked** → CTA to complete the
///      Thaiprompt OAuth on the web (mobile OAuth flow is a separate
///      future task). The /v1/mlm/* endpoints return 403 with
///      reason_code=thaiprompt_not_linked which AffiliateRepository
///      surfaces as [MlmNotLinked].
///   3. **Guest** → bounce to /login.
///
/// All data goes through [affiliateBundleProvider] which bundles
/// stats + tree + first page of commissions into a single async state.
class AffiliateScreen extends ConsumerWidget {
  const AffiliateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      body: Stack(
        children: [
          const StarryBackground(density: 30, intensity: 0.4),
          SafeArea(
            child: Column(
              children: [
                _header(context, ref),
                Expanded(
                  child: auth is! AuthAuthenticated
                      ? _guestPrompt(context)
                      : _LinkedDashboard(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left,
                color: JuntraColors.gold, size: 28),
            onPressed: () => context.canPop()
                ? context.pop()
                : context.go(Routes.profile),
          ),
          Expanded(
              child: Text('ระบบสายงาน Affiliate', style: baiJamjuree(size: 18))),
          IconButton(
            icon: const Icon(Icons.refresh,
                color: JuntraColors.textFaint, size: 22),
            tooltip: 'ดึงยอดสดจาก Thaiprompt',
            onPressed: () => _hardRefresh(ref),
          ),
        ],
      ),
    );
  }

  Widget _guestPrompt(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔐', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text('เข้าสู่ระบบเพื่อดูผังสายงาน',
                style: baiJamjuree(size: 18, color: JuntraColors.gold)),
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
}

/// Stateful wrapper so we can attach a [WidgetsBindingObserver] —
/// when the user returns to the app after completing the Thaiprompt
/// OAuth in the browser (foreground state regained), we auto-refresh
/// /auth/me and the affiliate bundle so the dashboard appears without
/// the user having to hunt for the refresh button.
class _LinkedDashboard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_LinkedDashboard> createState() => _LinkedDashboardState();
}

class _LinkedDashboardState extends ConsumerState<_LinkedDashboard>
    with WidgetsBindingObserver {
  bool _oauthInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Foreground regained AFTER we launched the OAuth URL — assume the
    // user might have completed the link in the browser. Refresh auth
    // (which carries the thaiprompt_linked flag) and invalidate the
    // affiliate bundle so the screen re-renders against fresh data.
    // Cheap; runs at most once per OAuth attempt.
    if (state == AppLifecycleState.resumed && _oauthInFlight) {
      _oauthInFlight = false;
      // ignore: unawaited_futures
      ref.read(authControllerProvider.notifier).refresh();
      ref.invalidate(affiliateBundleProvider);
    }
  }

  /// Build the mobile OAuth bootstrap URL using the user's Sanctum
  /// bearer token from secure storage. The browser handoff carries the
  /// token in the URL (HTTPS, one-shot) so juntraweb can establish a
  /// matching web session for the same user before the Thaiprompt
  /// callback fires.
  Future<Uri?> _buildOauthUrl() async {
    final api = await ref.read(apiClientProvider.future);
    // Mint a SHORT-LIVED single-use handoff code instead of putting the
    // long-lived bearer in the URL (the bearer rides in the auth header on
    // this POST). The code expires in 120s and can't be replayed, so it's
    // safe to appear in browser history / logs.
    try {
      final res = await api.post<Map<String, dynamic>>(Api.authHandoff);
      final data = res['data'];
      final code = (data is Map ? data['code'] : null)?.toString();
      if (code == null || code.isEmpty) return null;
      return Uri.https('จันทรา.online', '/auth/thaiprompt/mobile-start', {
        'code': code,
      });
    } on ApiException {
      return null;
    }
  }

  Future<void> _launchOauth(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = await _buildOauthUrl();
    if (!mounted) return;
    if (uri == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text('เซสชั่นไม่พร้อม — กรุณาเข้าสู่ระบบใหม่แล้วลองอีกครั้ง'),
        backgroundColor: JuntraColors.bgPurpleDeep,
      ));
      return;
    }
    if (await canLaunchUrl(uri)) {
      _oauthInFlight = true;
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      messenger.showSnackBar(const SnackBar(
        content: Text('เปิดเบราว์เซอร์ไม่ได้ — กรุณาลองอีกครั้ง'),
        backgroundColor: JuntraColors.bgPurpleDeep,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(affiliateBundleProvider);
    return async.when(
      loading: () => const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(JuntraColors.gold),
        ),
      ),
      error: (e, _) => _errorState(context, ref, e),
      data: (result) => switch (result) {
        MlmLinked() => _renderLinked(context, ref, result),
        MlmNotLinked(message: final msg) => _notLinkedState(context, msg),
      },
    );
  }

  Widget _renderLinked(BuildContext context, WidgetRef ref, MlmLinked linked) {
    final root = linked.asMap;
    final stats = (root['stats'] as Map?)?.cast<String, dynamic>() ?? const {};
    final tree = (root['tree'] as Map?)?.cast<String, dynamic>() ?? const {};
    final commissions = (root['commissions'] as List?)
        ?.whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList()
        ?? <Map<String, dynamic>>[];

    return RefreshIndicator(
      color: JuntraColors.gold,
      backgroundColor: JuntraColors.bgPurpleDeep,
      onRefresh: () async {
        // Bust the server cache first so this pull returns LIVE Thaiprompt
        // totals — the same figures the web dashboard shows.
        await _hardRefresh(ref);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _SyncStamp(fetchedAt: linked.fetchedAt),
          const SizedBox(height: 8),
          _EarningsHero(stats: stats),
          const SizedBox(height: 12),
          _LevelStats(stats: stats),
          const SizedBox(height: 16),
          Text('รายได้ 12 เดือนล่าสุด', style: baiJamjuree(size: 16)),
          const SizedBox(height: 8),
          _MonthlyChart(stats: stats),
          const SizedBox(height: 16),
          Text('ผังสายงาน', style: baiJamjuree(size: 16)),
          const SizedBox(height: 8),
          _NetworkSection(tree: tree),
          const SizedBox(height: 16),
          Text('คอมมิชชั่นล่าสุด', style: baiJamjuree(size: 16)),
          const SizedBox(height: 8),
          if (commissions.isEmpty)
            _commissionsEmpty()
          else
            ..._renderCommissions(commissions),
          const SizedBox(height: 16),
          _ReferralBox(stats: stats),
        ],
      ),
    );
  }

  Widget _commissionsEmpty() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        border: Border.all(color: JuntraColors.purple.withValues(alpha: 0.2)),
      ),
      child: const Row(
        children: [
          Icon(Icons.receipt_long_outlined,
              color: JuntraColors.textFaint, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'ยังไม่มีคอมมิชชั่น · เมื่อคนในสายงานเปิดไพ่ ลูกจะได้ส่วนแบ่งทันที',
              style: TextStyle(
                fontSize: 12, color: JuntraColors.textMuted, height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Iterable<Widget> _renderCommissions(List<Map<String, dynamic>> rows) {
    // Keep mobile light — show first 8 then a "ดูทั้งหมด" link to the
    // web dashboard. Full pagination on a phone is heavy and the
    // breakdown is rarely needed away from a laptop.
    final shown = rows.take(8);
    return [
      for (final c in shown) _CommissionTile(commission: c),
      if (rows.length > 8)
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: TextButton(
            onPressed: () async {
              final url = Uri.parse('https://จันทรา.online/mlm');
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
            child: const Text('ดูทั้งหมดบนเว็บ →',
                style: TextStyle(color: JuntraColors.gold)),
          ),
        ),
    ];
  }

  Widget _errorState(BuildContext context, WidgetRef ref, Object e) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off,
                color: JuntraColors.textFaint, size: 48),
            const SizedBox(height: 12),
            const Text('โหลดข้อมูลสายงานไม่สำเร็จ',
                style: TextStyle(
                  fontSize: 14, color: JuntraColors.textCream,
                  fontWeight: FontWeight.w600,
                )),
            const SizedBox(height: 6),
            Text(
              // Only surface a localized ApiException message; anything else
              // (cast/parse errors from the opaque upstream payload) gets a
              // generic line so internal detail never reaches the user.
              e is ApiException
                  ? e.message
                  : 'ตรวจสอบการเชื่อมต่ออินเทอร์เน็ตแล้วลองใหม่อีกครั้ง',
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
              onPressed: () => ref.invalidate(affiliateBundleProvider),
              child: const Text('ลองใหม่'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notLinkedState(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88, height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  JuntraColors.gold.withValues(alpha: 0.35),
                  JuntraColors.gold.withValues(alpha: 0),
                ]),
              ),
              alignment: Alignment.center,
              child: const Text('🔗', style: TextStyle(fontSize: 40)),
            ),
            const SizedBox(height: 16),
            Text('เชื่อมต่อบัญชี Thaiprompt',
                style: baiJamjuree(size: 18, color: JuntraColors.gold)),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13, color: JuntraColors.textLavender, height: 1.55,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: 240,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: JuntraColors.gold,
                  foregroundColor: JuntraColors.bgPurpleDeep,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                // /auth/thaiprompt/mobile-start carries the user's
                // Sanctum bearer so juntraweb can establish a matching
                // web session for the OAuth callback. When the user
                // returns to the app, didChangeAppLifecycleState
                // auto-refreshes — they shouldn't need to tap anything.
                onPressed: () => _launchOauth(context),
                child: const Text('เปิดเว็บเพื่อเชื่อมต่อ',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'หลังเชื่อมต่อสำเร็จ กลับมาที่แอพ — ระบบจะอัปเดตข้อมูลให้อัตโนมัติ',
              style: TextStyle(
                fontSize: 11, color: JuntraColors.textFaint, height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── KPI strip ────────────────────────────────────────────────────

class _EarningsHero extends StatelessWidget {
  const _EarningsHero({required this.stats});
  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final totals = (stats['totals'] as Map?)?.cast<String, dynamic>() ?? const {};
    final allTime = (totals['all_time'] as num?)?.toDouble() ?? 0;
    final thisMonth = (totals['this_month'] as num?)?.toDouble() ?? 0;
    // `totals.last_month` isn't sent upstream; derive it from monthly_series
    // (the series the web chart uses) — the second-to-last point. Null when
    // unknown so we don't render a fake "฿0 / always up" comparison.
    final lastMonth = _lastMonthFromSeries(stats);
    final up = lastMonth == null ? null : thisMonth >= lastMonth;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: JuntraColors.purpleCardGradient,
        borderRadius: BorderRadius.circular(JuntraRadius.hero),
        border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.4)),
        boxShadow: const [
          BoxShadow(color: Color(0x99000000), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('รายได้สะสม', style: TextStyle(
            fontSize: 10, letterSpacing: 2.4,
            color: JuntraColors.textFaint, fontWeight: FontWeight.w500,
          )),
          const SizedBox(height: 6),
          Text('฿${_fmt(allTime)}',
              style: baiJamjuree(size: 32, color: JuntraColors.gold)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _MiniStat(
                label: 'เดือนนี้', value: '฿${_fmt(thisMonth)}', up: up,
              )),
              if (lastMonth != null) ...[
                const SizedBox(width: 8),
                Expanded(child: _MiniStat(
                  label: 'เดือนที่แล้ว', value: '฿${_fmt(lastMonth)}',
                  up: up == null ? null : !up,
                )),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Last month's earnings from `stats.monthly_series` (the second-to-last
  /// point), or null when the series isn't present / too short.
  static double? _lastMonthFromSeries(Map<String, dynamic> stats) {
    final series = stats['monthly_series'];
    if (series is! List || series.length < 2) return null;
    final prev = series[series.length - 2];
    if (prev is num) return prev.toDouble();
    if (prev is Map) {
      final v = prev['amount'] ?? prev['value'] ?? prev['commission'] ?? prev['total'];
      if (v is num) return v.toDouble();
    }
    return null;
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, this.up});
  final String label;
  final String value;
  /// null → no trend arrow (we don't have a real comparison).
  final bool? up;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: JuntraColors.bgDeepest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(
            fontSize: 10, color: JuntraColors.textFaint,
          )),
          const SizedBox(height: 4),
          Row(
            children: [
              Flexible(
                child: Text(value,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700,
                    color: JuntraColors.textCream,
                  ),
                ),
              ),
              if (up != null) ...[
                const SizedBox(width: 4),
                Icon(up! ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 12,
                    color: up! ? JuntraColors.mintGreen : Colors.redAccent),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _LevelStats extends StatelessWidget {
  const _LevelStats({required this.stats});
  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final mlm = (stats['mlm'] as Map?)?.cast<String, dynamic>() ?? const {};
    final counts = (stats['counts'] as Map?)?.cast<String, dynamic>() ?? const {};
    final direct = (mlm['direct_referrals'] as num?)?.toInt() ?? 0;
    final team = (mlm['total_team_members'] as num?)?.toInt() ?? 0;
    final customers = (counts['unique_customers'] as num?)?.toInt() ?? 0;

    return Row(
      children: [
        Expanded(child: _BoxStat(value: '$direct', label: 'ตรง')),
        const SizedBox(width: 8),
        Expanded(child: _BoxStat(value: '$team', label: 'ทีม')),
        const SizedBox(width: 8),
        Expanded(child: _BoxStat(value: '$customers', label: 'ลูกค้า')),
      ],
    );
  }
}

class _BoxStat extends StatelessWidget {
  const _BoxStat({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(value, style: baiJamjuree(size: 22, color: JuntraColors.gold)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(
              fontSize: 11, color: JuntraColors.textMuted)),
        ],
      ),
    );
  }
}

// ─── Sync stamp — "ยอดเดียวกับ Thaiprompt" + data freshness ──────

class _SyncStamp extends StatelessWidget {
  const _SyncStamp({required this.fetchedAt});
  final String? fetchedAt;

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.tryParse(fetchedAt ?? '')?.toLocal();
    String when = '';
    if (dt != null) {
      try {
        when = DateFormat('d MMM · HH:mm', 'th').format(dt);
      } catch (_) {
        when = DateFormat('d MMM · HH:mm').format(dt);
      }
    }
    return Row(
      children: [
        Container(
          width: 8, height: 8,
          decoration: const BoxDecoration(
            shape: BoxShape.circle, color: JuntraColors.mintGreen,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            dt == null
                ? 'ยอดตรงกับ Thaiprompt · ดึงลงมาเพื่อรีเฟรชยอดสด'
                : 'ยอดตรงกับ Thaiprompt · ข้อมูล ณ $when น.',
            style: const TextStyle(
              fontSize: 11, color: JuntraColors.textFaint,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Monthly earnings chart (matches the web line chart data) ─────

class _MonthlyChart extends StatelessWidget {
  const _MonthlyChart({required this.stats});
  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final series = <({String label, double amount})>[];
    final raw = stats['monthly_series'];
    if (raw is List) {
      for (final m in raw.whereType<Map>()) {
        series.add((
          label: (m['label'] ?? '').toString(),
          amount: (m['amount'] as num?)?.toDouble() ?? 0,
        ));
      }
    }
    final points = series.length > 12
        ? series.sublist(series.length - 12)
        : series;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 10),
      decoration: BoxDecoration(
        color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        border: Border.all(color: JuntraColors.purple.withValues(alpha: 0.2)),
      ),
      child: points.isEmpty || points.every((p) => p.amount == 0)
          ? const SizedBox(
              height: 90,
              child: Center(
                child: Text(
                  'ยังไม่มีรายได้ · กราฟจะแสดงเมื่อมีคอมมิชชั่นเข้า',
                  style: TextStyle(fontSize: 12, color: JuntraColors.textFaint),
                ),
              ),
            )
          : SizedBox(
              height: 150,
              width: double.infinity,
              child: CustomPaint(painter: _BarsPainter(points)),
            ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.points);
  final List<({String label, double amount})> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const labelH = 22.0;
    const valueH = 16.0;
    final chartH = size.height - labelH - valueH;
    final maxV = points.fold<double>(0, (m, p) => p.amount > m ? p.amount : m);
    if (maxV <= 0) return;

    final slot = size.width / points.length;
    final barW = (slot * 0.52).clamp(6.0, 26.0);

    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final h = (p.amount / maxV) * chartH;
      final x = slot * i + (slot - barW) / 2;
      final top = valueH + (chartH - h);
      final isLast = i == points.length - 1;

      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, top, barW, h),
        topLeft: const Radius.circular(5),
        topRight: const Radius.circular(5),
      );
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isLast
              ? [JuntraColors.goldLight, JuntraColors.goldMid]
              : [
                  JuntraColors.gold.withValues(alpha: 0.55),
                  JuntraColors.goldMid.withValues(alpha: 0.25),
                ],
        ).createShader(rect.outerRect);
      canvas.drawRRect(rect, paint);

      // Value above the current-month bar only (keeps the chart clean).
      if (isLast && p.amount > 0) {
        _text(canvas, '฿${_fmt(p.amount)}',
            x + barW / 2, top - 3, anchorBottom: true,
            color: JuntraColors.goldLight, fontSize: 10,
            bold: true);
      }
      // Month labels — every other bar when tight, parity anchored so the
      // latest month always carries its label.
      if (points.length <= 6 || i % 2 == (points.length - 1) % 2) {
        _text(canvas, p.label,
            x + barW / 2, size.height - labelH + 4,
            color: JuntraColors.textFaint, fontSize: 8.5);
      }
    }

    // Baseline
    final base = Paint()
      ..color = JuntraColors.gold.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, valueH + chartH),
      Offset(size.width, valueH + chartH),
      base,
    );
  }

  void _text(Canvas canvas, String s, double cx, double y,
      {required Color color, required double fontSize,
      bool bold = false, bool anchorBottom = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: color, fontSize: fontSize,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 60);
    tp.paint(canvas,
        Offset(cx - tp.width / 2, anchorBottom ? y - tp.height : y));
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.points != points;
}

// ─── Network tree (ผังสายงาน — expandable, matches web chart) ────

class _TreeNodeData {
  _TreeNodeData({
    required this.key, required this.name, required this.level,
    required this.earnings, required this.children,
    this.directOverride, this.teamOverride,
  });
  final String key;
  final String name;
  final int level;
  final double earnings;
  final List<_TreeNodeData> children;

  /// Upstream's true counts when present — the local walk undercounts when
  /// the tree is depth-clipped at 5 levels server-side.
  final int? directOverride;
  final int? teamOverride;

  int get direct => directOverride ?? children.length;
  late final int team =
      teamOverride ?? children.fold(0, (sum, c) => sum + 1 + c.team);
}

class _NetworkSection extends StatefulWidget {
  const _NetworkSection({required this.tree});
  final Map<String, dynamic> tree;

  @override
  State<_NetworkSection> createState() => _NetworkSectionState();
}

class _NetworkSectionState extends State<_NetworkSection> {
  bool _chartView = true;
  final Set<String> _collapsed = {};
  _TreeNodeData? _root;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(covariant _NetworkSection old) {
    super.didUpdateWidget(old);
    if (!identical(old.tree, widget.tree)) {
      _collapsed.clear();
      _parse();
    }
  }

  void _parse() {
    var seq = 0;
    _TreeNodeData? build(Map m, int level) {
      final kids = <_TreeNodeData>[];
      final rawKids = m['children'];
      if (rawKids is List) {
        for (final c in rawKids.whereType<Map>()) {
          final k = build(c, level + 1);
          if (k != null) kids.add(k);
        }
      }
      return _TreeNodeData(
        key: 'n${seq++}',
        name: (m['name'] ?? m['label'] ?? 'ไม่ระบุชื่อ').toString(),
        level: level,
        earnings: (m['fortune_commission'] as num?)?.toDouble()
            ?? (m['earnings'] as num?)?.toDouble()
            ?? (m['total_pv'] as num?)?.toDouble() ?? 0,
        children: kids,
        directOverride: (m['direct_referrals'] as num?)?.toInt(),
        teamOverride: (m['total_team_members'] as num?)?.toInt(),
      );
    }

    final rawRoot = widget.tree['tree'];
    _root = rawRoot is Map ? build(rawRoot, 0) : null;
    _total = _root == null ? 0 : _root!.team + 1;

    // Big trees start folded below level 1 so the first paint is readable —
    // same behavior as the web chart.
    if (_total > 40 && _root != null) {
      void fold(_TreeNodeData n) {
        if (n.level >= 1 && n.children.isNotEmpty) _collapsed.add(n.key);
        for (final c in n.children) {
          fold(c);
        }
      }
      for (final c in _root!.children) {
        fold(c);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final root = _root;
    if (root == null || root.children.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(JuntraRadius.card),
          border: Border.all(color: JuntraColors.purple.withValues(alpha: 0.2)),
        ),
        child: const Column(
          children: [
            Text('🌙', style: TextStyle(fontSize: 34)),
            SizedBox(height: 8),
            Text('ยังไม่มีคนในสายงาน',
                style: TextStyle(
                  fontSize: 13.5, color: JuntraColors.textCream,
                  fontWeight: FontWeight.w600,
                )),
            SizedBox(height: 4),
            Text(
              'แชร์ลิงก์ชวนเพื่อนด้านล่าง — คนที่สมัครผ่านลิงก์จะปรากฏบนผังนี้ทันที',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5, color: JuntraColors.textMuted, height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── view toggle ──
        Row(
          children: [
            _segButton('ผัง', _chartView, () => setState(() => _chartView = true)),
            const SizedBox(width: 6),
            _segButton('รายชื่อ', !_chartView, () => setState(() => _chartView = false)),
            const Spacer(),
            Text('$_total คนในสาย',
                style: const TextStyle(
                  fontSize: 11, color: JuntraColors.textFaint,
                )),
          ],
        ),
        const SizedBox(height: 10),
        if (_chartView) ...[
          _RootCard(node: root),
          const SizedBox(height: 2),
          ..._emitTree(root),
        ] else
          ..._emitList(root),
      ],
    );
  }

  Widget _segButton(String label, bool on, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          gradient: on ? JuntraColors.goldButtonGradient : null,
          color: on ? null : JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: on
                ? JuntraColors.gold
                : JuntraColors.purple.withValues(alpha: 0.25),
          ),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: on ? FontWeight.w700 : FontWeight.w400,
              color: on ? JuntraColors.bgPurpleDeep : JuntraColors.textMuted,
            )),
      ),
    );
  }

  /// ผัง — indented rows with connector rails; each node with children can
  /// fold its branch.
  List<Widget> _emitTree(_TreeNodeData root) {
    final out = <Widget>[];
    void walk(_TreeNodeData n) {
      out.add(_TreeRow(
        node: n,
        collapsed: _collapsed.contains(n.key),
        onToggle: n.children.isEmpty
            ? null
            : () => setState(() {
                  if (!_collapsed.remove(n.key)) _collapsed.add(n.key);
                }),
      ));
      if (!_collapsed.contains(n.key)) {
        n.children.forEach(walk);
      }
    }

    root.children.forEach(walk);
    return out;
  }

  /// รายชื่อ — flat, sorted by earnings (top earners first).
  List<Widget> _emitList(_TreeNodeData root) {
    final flat = <_TreeNodeData>[];
    void collect(_TreeNodeData n) {
      flat.add(n);
      for (final c in n.children) {
        collect(c);
      }
    }
    for (final c in root.children) {
      collect(c);
    }
    flat.sort((a, b) => b.earnings.compareTo(a.earnings));

    return [
      for (final n in flat.take(50))
        _TreeRow(node: n, collapsed: false, onToggle: null, flatMode: true),
      if (flat.length > 50)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '+ อีก ${flat.length - 50} คน · ดูทั้งหมดบนเว็บ',
            style: const TextStyle(
              fontSize: 11, color: JuntraColors.textFaint,
            ),
          ),
        ),
    ];
  }
}

/// Root (คุณ) hero card at the top of the ผัง view.
class _RootCard extends StatelessWidget {
  const _RootCard({required this.node});
  final _TreeNodeData node;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        gradient: JuntraColors.goldButtonGradient,
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        boxShadow: [
          BoxShadow(
            color: JuntraColors.gold.withValues(alpha: 0.35),
            blurRadius: 18, offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42, height: 42,
            decoration: const BoxDecoration(
              shape: BoxShape.circle, color: JuntraColors.bgPurpleDeep,
            ),
            alignment: Alignment.center,
            child: Text(
              node.name.isNotEmpty ? String.fromCharCodes(node.name.runes.take(1)) : '?',
              style: const TextStyle(
                color: JuntraColors.gold, fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(node.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700,
                      color: JuntraColors.bgPurpleDeep,
                    )),
                Text('คุณ (ต้นสาย) · ตรง ${node.direct} · ทีม ${node.team}',
                    style: TextStyle(
                      fontSize: 11,
                      color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.75),
                    )),
              ],
            ),
          ),
          if (node.earnings > 0)
            Text('฿${_fmt(node.earnings)}',
                style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800,
                  color: JuntraColors.bgPurpleDeep,
                )),
        ],
      ),
    );
  }
}

/// One row of the ผัง/รายชื่อ — depth-tinted avatar, connector rail,
/// fold toggle when the node has a branch.
class _TreeRow extends StatelessWidget {
  const _TreeRow({
    required this.node, required this.collapsed, required this.onToggle,
    this.flatMode = false,
  });
  final _TreeNodeData node;
  final bool collapsed;
  final VoidCallback? onToggle;
  final bool flatMode;

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(node.level);
    final indent = flatMode ? 0.0 : (node.level - 1).clamp(0, 6) * 18.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(indent, 3, 0, 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!flatMode && node.level > 1) ...[
            Container(
              width: 12, height: 2,
              color: color.withValues(alpha: 0.35),
            ),
          ],
          Expanded(
            child: GestureDetector(
              onTap: onToggle,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                decoration: BoxDecoration(
                  color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(JuntraRadius.card),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            color.withValues(alpha: 0.9),
                            color.withValues(alpha: 0.45),
                          ],
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        node.name.isNotEmpty
                            ? String.fromCharCodes(node.name.runes.take(1))
                            : '?',
                        style: const TextStyle(
                          color: JuntraColors.bgPurpleDeep,
                          fontWeight: FontWeight.w700, fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(node.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600,
                                color: JuntraColors.textCream,
                              )),
                          Text(
                            node.level == 1
                                ? 'สายตรง · ตรง ${node.direct} · ทีม ${node.team}'
                                : 'ชั้น ${node.level} · ตรง ${node.direct} · ทีม ${node.team}',
                            style: const TextStyle(
                              fontSize: 10, color: JuntraColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (node.earnings > 0) ...[
                      const SizedBox(width: 6),
                      Text('฿${_fmt(node.earnings)}',
                          style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700,
                            color: JuntraColors.mintGreen,
                          )),
                    ],
                    if (onToggle != null && !flatMode) ...[
                      const SizedBox(width: 4),
                      Icon(
                        collapsed
                            ? Icons.keyboard_arrow_right
                            : Icons.keyboard_arrow_down,
                        size: 18,
                        color: collapsed ? JuntraColors.gold : JuntraColors.textFaint,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Recent commissions ──────────────────────────────────────────

class _CommissionTile extends StatelessWidget {
  const _CommissionTile({required this.commission});
  final Map<String, dynamic> commission;

  @override
  Widget build(BuildContext context) {
    final amount = (commission['amount'] as num?)?.toDouble() ?? 0;
    // `from_user` is a nested object {name,...} upstream — read .name; fall
    // back to reading.customer (what the web dashboard consumes).
    final from = ((commission['from_user'] as Map?)?['name']
            ?? (commission['reading'] as Map?)?['customer']
            ?? commission['customer_name']
            ?? '—')
        .toString();
    final level = (commission['level'] as num?)?.toInt() ?? 0;
    final status = commission['status']?.toString() ?? 'pending';
    final dt = DateTime.tryParse(commission['created_at']?.toString() ?? '')
        ?.toLocal();

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        border: Border.all(color: _statusColor(status).withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 6, height: 36,
            decoration: BoxDecoration(
              color: _statusColor(status),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(from,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5, color: JuntraColors.textCream,
                          fontWeight: FontWeight.w600,
                        ))),
                    if (dt != null)
                      Text(_formatDate(dt),
                          style: const TextStyle(
                            fontSize: 10, color: JuntraColors.textFaint,
                          )),
                  ],
                ),
                const SizedBox(height: 2),
                Text('ระดับ $level · $status',
                    style: const TextStyle(
                      fontSize: 10, color: JuntraColors.textMuted,
                    )),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('+฿${_fmt(amount)}', style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700,
            color: _statusColor(status),
          )),
        ],
      ),
    );
  }

  static Color _statusColor(String status) {
    return switch (status.toLowerCase()) {
      'paid' || 'approved' || 'success' => JuntraColors.mintGreen,
      'pending' || 'awaiting'           => JuntraColors.gold,
      'rejected' || 'failed'            => Colors.redAccent,
      _ => JuntraColors.purpleBright,
    };
  }

  static String _formatDate(DateTime dt) {
    try {
      return DateFormat('d MMM', 'th').format(dt);
    } catch (_) {
      return DateFormat('d MMM').format(dt);
    }
  }
}

// ─── Referral link ───────────────────────────────────────────────

class _ReferralBox extends StatelessWidget {
  const _ReferralBox({required this.stats});
  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final user = (stats['user'] as Map?)?.cast<String, dynamic>() ?? const {};
    // กรองให้เหลือชุดอักขระที่ route /r/{code} รับจริง (`[A-Za-z0-9_-]+`)
    // ไม่งั้น username ที่เป็นอีเมล/เบอร์ (ซึ่งเป็น fallback ตัวสุดท้าย)
    // จะได้ลิงก์และ QR ที่ 404 ทั้งชุด — เหมือนที่หน้า MLM ของเว็บทำไว้แล้ว
    final code = (user['referral_code']
            ?? user['code']
            ?? user['username']
            ?? '')
        .toString()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');

    // ยังไม่มีรหัส (Thaiprompt ยังไม่ส่งกลับมา / เพิ่งลิงก์บัญชี) — ห้ามแจก
    // QR กับลิงก์เปล่าแล้วบอกว่า "เพื่อนที่สมัครผ่านลิงก์นี้จะเข้าสายงาน"
    // เพราะเพื่อนจะสมัครจริงแต่ไม่มีรหัสให้ผูก = เสียคอมมิชชั่นเงียบ ๆ
    if (code.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: JuntraColors.mysticHeroGradient,
          borderRadius: BorderRadius.circular(JuntraRadius.card),
          border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ลิงก์ชวนเพื่อน', style: baiJamjuree(size: 15)),
            const SizedBox(height: 8),
            const Text(
              'ยังไม่พบรหัสชวนเพื่อนจาก Thaiprompt — ลองกด "ดึงยอดสด" '
              'หรือเชื่อมต่อบัญชีอีกครั้งนะคะ',
              style: TextStyle(
                fontSize: 12.5, color: JuntraColors.textMuted, height: 1.6,
              ),
            ),
          ],
        ),
      );
    }

    final url = 'https://จันทรา.online/r/$code';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: JuntraColors.mysticHeroGradient,
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ชวนเพื่อน · ต่อสายงาน', style: baiJamjuree(size: 14)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // QR — scan face-to-face; same URL as the copy button.
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDF8EC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: url,
                  size: 92,
                  padding: EdgeInsets.zero,
                  backgroundColor: const Color(0xFFFDF8EC),
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: JuntraColors.bgPurpleDeep,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: JuntraColors.bgPurpleDeep,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (code.isNotEmpty) ...[
                      const Text('รหัสของลูก',
                          style: TextStyle(
                            fontSize: 10, color: JuntraColors.textFaint,
                          )),
                      Text(code,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: baiJamjuree(
                            size: 18, color: JuntraColors.gold,
                          )),
                      const SizedBox(height: 8),
                    ],
                    InkWell(
                      onTap: () async {
                        final uri = Uri.parse(url);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        }
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: JuntraColors.bgDeepest.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                url,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: JuntraColors.textCream,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            const Icon(Icons.open_in_new,
                                size: 14, color: JuntraColors.gold),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  context,
                  icon: Icons.copy_rounded,
                  label: 'คัดลอกลิงก์',
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await Clipboard.setData(ClipboardData(text: url));
                    messenger.showSnackBar(const SnackBar(
                      content: Text('คัดลอกลิงก์ชวนเพื่อนแล้ว ✓'),
                      backgroundColor: JuntraColors.bgPurpleDeep,
                      duration: Duration(seconds: 2),
                    ));
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _actionButton(
                  context,
                  icon: Icons.chat_bubble_rounded,
                  label: 'แชร์ LINE',
                  onTap: () async {
                    final share = Uri.parse(
                      'https://line.me/R/share?text=${Uri.encodeComponent('มาดูดวงกับฉันที่ จันทราพยากรณ์ ✨ $url')}',
                    );
                    if (await canLaunchUrl(share)) {
                      await launchUrl(share,
                          mode: LaunchMode.externalApplication);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'เพื่อนสมัครผ่านลิงก์นี้จะอยู่ในสายงานของลูก · ทุกบิลดูดวงของทีมสร้างคอมมิชชั่นอัตโนมัติ',
            style: TextStyle(
              fontSize: 11, color: JuntraColors.textFaint, height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(BuildContext context,
      {required IconData icon,
      required String label,
      required Future<void> Function() onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: JuntraColors.bgDeepest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: JuntraColors.gold.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: JuntraColors.gold),
            const SizedBox(width: 7),
            Text(label,
                style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: JuntraColors.textCream,
                )),
          ],
        ),
      ),
    );
  }
}

// ─── Shared helpers ──────────────────────────────────────────────

String _fmt(double v) {
  // Compact for big sums so the card doesn't wrap awkwardly on phones.
  if (v >= 1_000_000) return '${(v / 1_000_000).toStringAsFixed(1)}M';
  if (v >= 100_000) return '${(v / 1_000).toStringAsFixed(0)}k';
  return NumberFormat('#,###').format(v.round());
}
