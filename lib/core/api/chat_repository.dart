import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'endpoints.dart';
import '../auth/session.dart';

/// Mae Mor Chantra AI chat — wraps /v1/chat/conversations*.
///
/// New conversation flow (juntraweb-side):
///   1. POST /v1/chat/conversations          → returns {conversation, balance, cost}
///   2. POST /v1/chat/conversations/{id}/send {message} → {reply, balance, cost}
///   3. GET  /v1/chat/conversations          → list past conversations
///   4. GET  /v1/chat/conversations/{id}     → get full message history
///
/// All AI calls happen server-side; juntra mobile app holds NO AI keys.
class ChatRepository {
  ChatRepository(this._api);
  final ApiClient _api;

  /// Start a new conversation. Returns:
  ///   { conversation: {id, title, messages:[{role, content, ...}]},
  ///     balance: float, cost: float }
  Future<Map<String, dynamic>> startConversation({int? readingId}) async {
    // [readingId] = คุยต่อจากคำทำนายไพ่ที่จ่ายแล้ว — แม่หมอเห็นไพ่และคำพยากรณ์ชุดนั้นทุกข้อความ
    // (เซิร์ฟเวอร์คืนห้องเดิมของคำทำนายนั้นถ้าเคยเปิดไว้แล้ว ไม่สร้างห้องซ้ำ)
    final res = await _api.post<Map<String, dynamic>>(
      Api.chatConversations,
      data: readingId == null ? null : {'reading_id': readingId},
    );
    return _data(res);
  }

  /// List the user's recent conversations (max 50).
  Future<List<Map<String, dynamic>>> listConversations() async {
    final res = await _api.get<Map<String, dynamic>>(Api.chatConversations);
    final list = (res['data'] as List?) ?? const [];
    return list.cast<Map<String, dynamic>>();
  }

  /// Fetch a full conversation by id (includes all messages).
  Future<Map<String, dynamic>> getConversation(int id) async {
    final res = await _api.get<Map<String, dynamic>>(Api.chatConversation(id));
    return _data(res);
  }

  /// Send a user message. Returns:
  ///   { message: {...}, reply, balance, cost, daily_limit, daily_left,
  ///     awaiting, suggestions:[{label,prompt,icon}] }
  ///
  /// On 402 (insufficient funds) / 429 (daily_limit หรือส่งถี่เกินไป) /
  /// 409 (ข้อความเดิมกำลังส่งอยู่) จะโยน [ApiException] พร้อม reasonCode
  /// ให้หน้าจอแยกเคสได้
  ///
  /// [idempotencyKey] ต้องส่งเสมอสำหรับ endpoint นี้เพราะมันตัดเงิน และ
  /// ต้องใช้ค่าเดิมเมื่อผู้ใช้กด "ลองใหม่" ข้อความเดิม (ดู ApiClient.post)
  Future<Map<String, dynamic>> send({
    required int conversationId,
    required String text,
    required String idempotencyKey,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      Api.chatSend(conversationId),
      data: {'message': text},
      idempotencyKey: idempotencyKey,
    );
    return _data(res);
  }

  Map<String, dynamic> _data(Map<String, dynamic> res) {
    final inner = res['data'];
    return inner is Map<String, dynamic> ? inner : res;
  }
}

final chatRepositoryProvider = FutureProvider<ChatRepository>((ref) async {
  final api = await ref.watch(apiClientProvider.future);
  return ChatRepository(api);
});

/// Conversation list provider — feeds ConversationListScreen and the
/// "บทสนทนาเก่า" tab. Cached for the session; invalidate after
/// startConversation()/send() so a new convo appears at the top.
final chatConversationsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(sessionUserIdProvider); // ข้อมูลส่วนตัว — ล้างทิ้งเมื่อสลับผู้ใช้
  final repo = await ref.watch(chatRepositoryProvider.future);
  return repo.listConversations();
});

/// Single conversation detail — keyed by id. Used by ChatScreen when
/// resuming an existing conversation via `/chat?id=N`.
final chatConversationProvider =
    FutureProvider.family<Map<String, dynamic>, int>((ref, id) async {
  ref.watch(sessionUserIdProvider);
  final repo = await ref.watch(chatRepositoryProvider.future);
  return repo.getConversation(id);
});
