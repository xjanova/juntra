import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/endpoints.dart';

/// Minimal auth state — extended later with profile, membership tier, etc.
sealed class AuthState extends Equatable {
  const AuthState();
  @override
  List<Object?> get props => const [];
}

class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class AuthGuest extends AuthState {
  const AuthGuest();
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({required this.userId, required this.displayName});
  final String userId;
  final String displayName;
  @override
  List<Object?> get props => [userId, displayName];
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._ref) : super(const AuthUnknown()) {
    _bootstrap();
  }
  final Ref _ref;

  Future<void> _bootstrap() async {
    try {
      final api = await _ref.read(apiClientProvider.future);
      final token = await api.getToken();
      if (token == null || token.isEmpty) {
        state = const AuthGuest();
        return;
      }
      final me = await api.get<Map<String, dynamic>>(Api.me);
      final data = (me['data'] is Map ? me['data'] : me) as Map<String, dynamic>;
      state = AuthAuthenticated(
        userId: data['id']?.toString() ?? '',
        displayName: data['display_name']?.toString() ??
            data['name']?.toString() ??
            'แขก',
      );
    } catch (_) {
      state = const AuthGuest();
    }
  }

  Future<void> signOut() async {
    final api = await _ref.read(apiClientProvider.future);
    try {
      await api.post(Api.logout);
    } catch (_) {/* tolerate offline logout */}
    await api.clearToken();
    state = const AuthGuest();
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref);
});
