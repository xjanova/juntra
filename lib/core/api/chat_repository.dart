import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'endpoints.dart';

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
  Future<Map<String, dynamic>> startConversation() async {
    final res = await _api.post<Map<String, dynamic>>(Api.chatConversations);
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
  ///   { message: {id, role, content, created_at}, reply, balance, cost }
  /// On 402 (insufficient funds) the [ApiException] is rethrown — the chat
  /// screen catches statusCode==402 to deep-link the user to the wallet.
  Future<Map<String, dynamic>> send({
    required int conversationId,
    required String text,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      Api.chatSend(conversationId),
      data: {'message': text},
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
  final repo = await ref.watch(chatRepositoryProvider.future);
  return repo.listConversations();
});

/// Single conversation detail — keyed by id. Used by ChatScreen when
/// resuming an existing conversation via `/chat?id=N`.
final chatConversationProvider =
    FutureProvider.family<Map<String, dynamic>, int>((ref, id) async {
  final repo = await ref.watch(chatRepositoryProvider.future);
  return repo.getConversation(id);
});
