import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/affiliate_repository.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/auth/auth_state.dart';
import '../../shared/widgets/starry_background.dart';

/// Screen 11 — Affiliate Network / MLM dashboard.
///
/// Three states:
///   1. **Authenticated + thaiprompt-linked** → KPI strip, downline
///      list (flat, no graph viz on mobile), recent commissions table,
///      referral link.
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
            tooltip: 'รีเฟรช',
            onPressed: () => ref.invalidate(affiliateBundleProvider),
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
    final token = await api.getToken();
    if (token == null || token.isEmpty) return null;
    // Build via Uri.https so the bearer is percent-encoded — a Sanctum token
    // is `<id>|<hash>` and the raw `|` would otherwise corrupt the query.
    return Uri.https('จันทรา.online', '/auth/thaiprompt/mobile-start', {
      'bearer': token,
    });
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
        ref.invalidate(affiliateBundleProvider);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _EarningsHero(stats: stats),
          const SizedBox(height: 12),
          _LevelStats(stats: stats),
          const SizedBox(height: 16),
          Text('สายงานของลูก', style: baiJamjuree(size: 16)),
          const SizedBox(height: 8),
          _DownlineList(tree: tree),
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

// ─── Downline list (flat — no graph viz on mobile) ───────────────

class _DownlineList extends StatelessWidget {
  const _DownlineList({required this.tree});
  final Map<String, dynamic> tree;

  @override
  Widget build(BuildContext context) {
    // Upstream tree shape (best-effort — vis-network nodes/edges):
    //   { nodes: [{id, label, level, total_pv?, ...}, ...], edges: [...] }
    // OR for some endpoints a recursive `children: []`. We flatten
    // either into a depth-indented list for mobile rendering.
    final flat = _flatten(tree);
    if (flat.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(JuntraRadius.card),
          border: Border.all(color: JuntraColors.purple.withValues(alpha: 0.2)),
        ),
        child: const Row(
          children: [
            Icon(Icons.account_tree_outlined,
                color: JuntraColors.textFaint, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'ยังไม่มีคนในสายงาน · ชวนเพื่อนผ่านลิงก์ด้านล่างเพื่อเริ่มสร้างทีม',
                style: TextStyle(
                  fontSize: 12, color: JuntraColors.textMuted, height: 1.5,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final n in flat.take(12)) _DownlineNode(node: n),
        if (flat.length > 12)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '+ อีก ${flat.length - 12} คน · ดูทั้งหมดบนเว็บ',
              style: const TextStyle(
                fontSize: 11, color: JuntraColors.textFaint,
              ),
            ),
          ),
      ],
    );
  }

  /// Walk the tree (either `{nodes: [...]}` or `{children: [...]}`)
  /// and produce `[{name, count, level}, ...]`. Best-effort; unknown
  /// shapes return empty so the screen falls back to the empty state.
  List<_FlatNode> _flatten(Map<String, dynamic> tree) {
    final out = <_FlatNode>[];
    final nodes = tree['nodes'];
    if (nodes is List) {
      for (final n in nodes.whereType<Map>()) {
        out.add(_FlatNode(
          name: (n['label'] ?? n['name'])?.toString() ?? 'ไม่ระบุชื่อ',
          level: (n['level'] as num?)?.toInt() ?? 0,
          count: (n['team_size'] as num?)?.toInt() ?? 0,
          earnings: (n['total_pv'] as num?)?.toDouble()
              ?? (n['earnings'] as num?)?.toDouble() ?? 0,
        ));
      }
    }
    final children = tree['children'];
    if (children is List) {
      _walkChildren(children, level: 1, out: out);
    }
    // Actual upstream shape: { tree: { name, children: [...], fortune_commission } }
    // — a single root node. Descend its children (the web dashboard reads it
    // this way). Kept additive so other shapes still degrade to empty.
    final root = tree['tree'];
    if (root is Map) {
      final rootChildren = root['children'];
      if (rootChildren is List) {
        _walkChildren(rootChildren, level: 1, out: out);
      }
    }
    return out;
  }

  void _walkChildren(List children, {required int level, required List<_FlatNode> out}) {
    for (final c in children.whereType<Map>()) {
      out.add(_FlatNode(
        name: (c['name'] ?? c['label'])?.toString() ?? 'ไม่ระบุชื่อ',
        level: level,
        count: (c['team_size'] as num?)?.toInt() ?? 0,
        earnings: (c['fortune_commission'] as num?)?.toDouble()
            ?? (c['earnings'] as num?)?.toDouble()
            ?? (c['total_pv'] as num?)?.toDouble() ?? 0,
      ));
      final inner = c['children'];
      if (inner is List) {
        _walkChildren(inner, level: level + 1, out: out);
      }
    }
  }
}

class _FlatNode {
  const _FlatNode({
    required this.name, required this.level,
    required this.count, required this.earnings,
  });
  final String name;
  final int level;
  final int count;
  final double earnings;
}

class _DownlineNode extends StatelessWidget {
  const _DownlineNode({required this.node});
  final _FlatNode node;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(node.level * 16.0, 4, 0, 4),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(JuntraRadius.card),
          border: Border.all(color: JuntraColors.purple.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [JuntraColors.bgPurpleLight, JuntraColors.bgPurple],
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                node.name.isNotEmpty ? node.name.substring(0, 1) : '?',
                style: const TextStyle(
                  color: JuntraColors.gold, fontWeight: FontWeight.w700,
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
                  Text('ระดับ ${node.level} · ${node.count} คน',
                      style: const TextStyle(
                        fontSize: 10, color: JuntraColors.textMuted,
                      )),
                ],
              ),
            ),
            if (node.earnings > 0)
              Text('฿${_fmt(node.earnings)}',
                  style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: JuntraColors.mintGreen,
                  )),
          ],
        ),
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
    final code = (user['referral_code']
            ?? user['code']
            ?? user['username']
            ?? '')
        .toString();
    final url = code.isEmpty
        ? 'https://จันทรา.online'
        : 'https://จันทรา.online/r/$code';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: JuntraColors.mysticHeroGradient,
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ลิงก์เชิญเพื่อน', style: baiJamjuree(size: 14)),
          const SizedBox(height: 8),
          InkWell(
            onTap: () async {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                        fontSize: 13, color: JuntraColors.textCream,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const Icon(Icons.open_in_new,
                      size: 16, color: JuntraColors.gold),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'แตะเพื่อเปิดในเบราว์เซอร์ · เพื่อนสมัครผ่านลิงก์นี้จะอยู่ในสายงานของลูก',
            style: TextStyle(
              fontSize: 11, color: JuntraColors.textFaint, height: 1.5,
            ),
          ),
        ],
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
