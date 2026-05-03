import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'endpoints.dart';

/// Mae Mor Chantra AI chat — wraps /v1/chat/mae-mor/*.
class ChatRepository {
  ChatRepository(this._api);
  final ApiClient _api;

  /// Returns: { session_id, greeting }
  Future<Map<String, dynamic>> startSession() async {
    final res = await _api.post<Map<String, dynamic>>(Api.chatStart);
    return (res['data'] is Map<String, dynamic>)
        ? res['data'] as Map<String, dynamic>
        : res;
  }

  /// Returns: { session_id, reply, ai_provider }
  Future<Map<String, dynamic>> send({
    required String sessionId,
    required String text,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(Api.chatSend, data: {
      'session_id': sessionId,
      'text': text,
    });
    return (res['data'] is Map<String, dynamic>)
        ? res['data'] as Map<String, dynamic>
        : res;
  }
}

final chatRepositoryProvider = FutureProvider<ChatRepository>((ref) async {
  final api = await ref.watch(apiClientProvider.future);
  return ChatRepository(api);
});
