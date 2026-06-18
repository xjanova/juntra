import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/wallet_repository.dart';
import '../../shared/widgets/starry_background.dart';

/// Full wallet history — cursor-paginated `/v1/wallet/transactions` (the
/// wallet screen only shows the last 10). Read-only.
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});
  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _items = <Map<String, dynamic>>[];
  final _scroll = ScrollController();
  String? _cursor;
  bool _loading = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
      _load();
    }
  }

  Future<void> _load() async {
    if (_loading || _done) return;
    setState(() { _loading = true; _error = null; });
    try {
      final repo = await ref.read(walletRepositoryProvider.future);
      final res = await repo.transactions(cursor: _cursor);
      final data = (res['data'] as List?)
              ?.whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList() ??
          const [];
      final next = (res['meta'] as Map?)?['next_cursor']?.toString();
      if (!mounted) return;
      setState(() {
        _items.addAll(data);
        _cursor = next;
        _done = next == null || next.isEmpty || data.isEmpty;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.message; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'โหลดประวัติไม่สำเร็จ'; });
    }
  }

  Future<void> _refresh() async {
    setState(() { _items.clear(); _cursor = null; _done = false; });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const StarryBackground(density: 25, intensity: 0.4),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, color: JuntraColors.gold, size: 28),
                      onPressed: () => context.canPop() ? context.pop() : context.go(Routes.wallet),
                    ),
                    Expanded(child: Text('ประวัติธุรกรรม', style: baiJamjuree(size: 20))),
                    const SizedBox(width: 12),
                  ],
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    color: JuntraColors.gold,
                    backgroundColor: JuntraColors.bgPurpleDeep,
                    child: _items.isEmpty && _loading
                        ? const Center(child: CircularProgressIndicator(color: JuntraColors.gold))
                        : _items.isEmpty
                            ? ListView(children: [
                                const SizedBox(height: 120),
                                Center(child: Text(_error ?? 'ยังไม่มีรายการธุรกรรม',
                                    style: const TextStyle(color: JuntraColors.textMuted))),
                              ])
                            : ListView.builder(
                                controller: _scroll,
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                                itemCount: _items.length + (_done ? 0 : 1),
                                itemBuilder: (_, i) {
                                  if (i >= _items.length) {
                                    return const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Center(child: SizedBox(
                                        width: 22, height: 22,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: JuntraColors.gold),
                                      )),
                                    );
                                  }
                                  return _TxRow(tx: _items[i]);
                                },
                              ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TxRow extends StatelessWidget {
  const _TxRow({required this.tx});
  final Map<String, dynamic> tx;

  @override
  Widget build(BuildContext context) {
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
    final isPositive = amount >= 0;
    final type = tx['type']?.toString() ?? '';
    final status = tx['status']?.toString() ?? 'success';
    final desc = tx['description']?.toString() ?? '';
    final created = tx['created_at']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        border: Border.all(color: JuntraColors.purple.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (isPositive ? JuntraColors.mintGreen : JuntraColors.purpleBright)
                  .withValues(alpha: 0.2),
            ),
            alignment: Alignment.center,
            child: Text(_icon(type), style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(desc.isEmpty ? _label(type) : desc,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5, color: JuntraColors.textCream, fontWeight: FontWeight.w600,
                    )),
                const SizedBox(height: 2),
                Text('${_date(created)} · ${_status(status)}',
                    style: const TextStyle(fontSize: 10.5, color: JuntraColors.textFaint)),
              ],
            ),
          ),
          Text('${isPositive ? '+' : ''}฿${amount.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700,
                color: isPositive ? JuntraColors.mintGreen : JuntraColors.purpleBright,
              )),
        ],
      ),
    );
  }

  String _icon(String t) => switch (t) {
        'topup' => '⬆', 'debit' => '⬇', 'refund' => '↩', _ => '•',
      };
  String _label(String t) => switch (t) {
        'topup' => 'เติมเงิน', 'debit' => 'หักค่าบริการ', 'refund' => 'คืนเครดิต',
        'adjustment' => 'ปรับยอด', _ => t,
      };
  String _status(String s) => switch (s) {
        'pending' => 'รอตรวจสอบ', 'success' => 'สำเร็จ', 'failed' => 'ปฏิเสธ',
        'refunded' => 'คืนเงินแล้ว', 'cancelled' => 'ยกเลิก', _ => s,
      };
  String _date(String iso) {
    if (iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return DateFormat('d MMM HH:mm', 'th').format(dt.toLocal());
  }
}
