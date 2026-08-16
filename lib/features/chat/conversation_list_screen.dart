import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../shared/data/juntra_art.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/chat_repository.dart';
import '../../core/auth/auth_state.dart';
import '../../shared/widgets/starry_background.dart';

/// Screen 7b — Conversation list. Past Mae Mor chat sessions, in reverse
/// chrono order, fetched from `GET /v1/chat/conversations`. Tapping a
/// tile opens `/chat?id=<id>` which the ChatScreen treats as a resume
/// (load full messages from /v1/chat/conversations/{id}) instead of
/// starting a fresh session.
///
/// A floating action button starts a fresh conversation (same as the
/// pre-existing `/chat` entry without a query param).
class ConversationListScreen extends ConsumerWidget {
  const ConversationListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final async = ref.watch(chatConversationsProvider);

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
                      : async.when(
                          loading: () => const Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  JuntraColors.gold),
                            ),
                          ),
                          error: (e, _) => _errorState(context, ref, e),
                          data: (rows) => _renderList(context, ref, rows),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: auth is AuthAuthenticated
          ? FloatingActionButton.extended(
              backgroundColor: JuntraColors.gold,
              foregroundColor: JuntraColors.bgPurpleDeep,
              onPressed: () => context.push(Routes.chat),
              icon: const Icon(Icons.add),
              label: const Text('สนทนาใหม่',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
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
            onPressed: () =>
                context.canPop() ? context.pop() : context.go(Routes.home),
          ),
          Expanded(
              child: Text('บทสนทนากับแม่หมอ', style: baiJamjuree(size: 19))),
          IconButton(
            icon: const Icon(Icons.refresh,
                color: JuntraColors.textFaint, size: 22),
            tooltip: 'รีเฟรช',
            onPressed: () => ref.invalidate(chatConversationsProvider),
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
            Text('เข้าสู่ระบบเพื่อดูบทสนทนา',
                style: baiJamjuree(size: 18, color: JuntraColors.gold)),
            const SizedBox(height: 8),
            const Text(
              'บทสนทนาของลูกกับแม่หมอจะถูกเก็บไว้บนเซิร์ฟเวอร์อย่างปลอดภัย — เข้าสู่ระบบเพื่อดูได้ทุกเมื่อ',
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
            const Text('โหลดบทสนทนาไม่สำเร็จ',
                style: TextStyle(
                  fontSize: 14, color: JuntraColors.textCream,
                  fontWeight: FontWeight.w600,
                )),
            const SizedBox(height: 6),
            // เดิมโชว์ e.toString() ซึ่งเป็นข้อความ exception ดิบ (มี URL /
            // ชื่อคลาสภายใน) ให้ผู้ใช้ทั่วไปเห็น — เผยโครงสร้างระบบและอ่านไม่รู้เรื่อง
            Text(
              e is ApiException ? e.message : 'ตรวจสอบสัญญาณอินเทอร์เน็ตแล้วลองใหม่อีกครั้งนะคะ',
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
              onPressed: () => ref.invalidate(chatConversationsProvider),
              child: const Text('ลองใหม่'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _renderList(BuildContext context, WidgetRef ref, List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return _emptyState(context);
    }
    return RefreshIndicator(
      color: JuntraColors.gold,
      backgroundColor: JuntraColors.bgPurpleDeep,
      onRefresh: () async {
        ref.invalidate(chatConversationsProvider);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        itemCount: rows.length,
        itemBuilder: (_, i) => _ConversationTile(convo: rows[i]),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(
        height: 400,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ภาพแทน emoji — 🔮 ถูกวาดด้วยฟอนต์ของเครื่องผู้ใช้
                // คนละรูปคนละสีทุกยี่ห้อ คุมโทนทอง-ม่วงไม่ได้เลย
                ClipRRect(
                  borderRadius: BorderRadius.circular(90),
                  child: Image.asset(JuntraArt.chat,
                      width: 180, height: 112, fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink()),
                ),
                const SizedBox(height: 16),
                Text('ยังไม่มีบทสนทนา',
                    style: baiJamjuree(size: 16, color: JuntraColors.gold)),
                const SizedBox(height: 8),
                const Text(
                  'เริ่มต้นคุยกับแม่หมอจันทราครั้งแรกของลูก · แม่หมอจะบันทึกทุกการพูดคุยเก็บไว้ให้',
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
                  onPressed: () => context.push(Routes.chat),
                  child: const Text('เริ่มสนทนา'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One row in the conversation list. Backend payload shape:
///   { id, title, message_count, updated_at }
class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.convo});
  final Map<String, dynamic> convo;

  @override
  Widget build(BuildContext context) {
    final id = (convo['id'] as num?)?.toInt();
    final title = convo['title']?.toString() ?? 'สนทนากับแม่หมอ';
    final count = (convo['message_count'] as num?)?.toInt() ?? 0;
    final relative = _relativeTime(convo['updated_at']?.toString());

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(JuntraRadius.card),
          onTap: id == null
              ? null
              : () => context.push('${Routes.chat}?id=$id'),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(JuntraRadius.card),
              border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                ClipOval(
                  child: Image.asset(
                    JuntraArt.maeMor,
                    width: 40, height: 40, fit: BoxFit.cover,
                    // ไฟล์ต้นฉบับ 1536×2752 (~6.7MB) — ถ้าไม่จำกัดขนาด decode
                    // ทุกแถวในลิสต์จะกิน RAM เต็มความละเอียดเพื่อวาดรูป 40px
                    cacheWidth: (40 * MediaQuery.devicePixelRatioOf(context)).round(),
                    errorBuilder: (_, _, _) => Container(
                      width: 40, height: 40,
                      color: JuntraColors.bgPurple,
                      alignment: Alignment.center,
                      child: const Text('🔮',
                          style: TextStyle(fontSize: 18)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600,
                                color: JuntraColors.textCream,
                              ),
                            ),
                          ),
                          if (relative != null)
                            Text(relative,
                                style: const TextStyle(
                                  fontSize: 10, color: JuntraColors.textFaint,
                                )),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$count ข้อความ',
                        style: const TextStyle(
                          fontSize: 11, color: JuntraColors.textMuted,
                        ),
                      ),
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

  static String? _relativeTime(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return null;
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'เมื่อสักครู่';
    if (diff.inMinutes < 60) return '${diff.inMinutes} นาที';
    if (diff.inHours < 24) return '${diff.inHours} ชม.';
    if (diff.inDays < 7) return '${diff.inDays} วัน';
    try {
      return DateFormat('d MMM', 'th').format(dt);
    } catch (_) {
      return DateFormat('d MMM').format(dt);
    }
  }
}
