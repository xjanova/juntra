import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_exceptions.dart';
import '../api/endpoints.dart';

/// Auth state machine — boots on app start, transitions on login/logout.
///
/// Token management lives in [ApiClient]; this controller owns only the
/// user-facing state (who's signed in, are we still figuring it out).
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
  const AuthAuthenticated({
    required this.userId,
    required this.displayName,
    this.email,
    this.walletBalance,
    this.walletCurrency = 'THB',
    this.thaipromptLinked = false,
  });
  final String userId;
  final String displayName;
  final String? email;
  final double? walletBalance;
  final String walletCurrency;
  final bool thaipromptLinked;

  AuthAuthenticated copyWith({double? walletBalance}) => AuthAuthenticated(
        userId: userId,
        displayName: displayName,
        email: email,
        walletBalance: walletBalance ?? this.walletBalance,
        walletCurrency: walletCurrency,
        thaipromptLinked: thaipromptLinked,
      );

  @override
  List<Object?> get props => [
        userId,
        displayName,
        email,
        walletBalance,
        walletCurrency,
        thaipromptLinked,
      ];
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
      final me = await api.get<Map<String, dynamic>>(Api.authMe);
      state = _userToState(_unwrap(me));
    } catch (_) {
      state = const AuthGuest();
    }
  }

  /// Refresh /me — call after wallet operations to update displayed balance.
  Future<void> refresh() async {
    try {
      final api = await _ref.read(apiClientProvider.future);
      final me = await api.get<Map<String, dynamic>>(Api.authMe);
      state = _userToState(_unwrap(me));
    } catch (_) {
      // Keep prior state — don't kick the user to guest on a transient error.
    }
  }

  /// Email + password sign-in. On success persists the bearer token via
  /// [ApiClient.setToken] and transitions to [AuthAuthenticated].
  /// Throws [ApiException] on 401/422 etc. so the UI can show the message.
  Future<void> signIn({required String email, required String password}) async {
    final api = await _ref.read(apiClientProvider.future);
    final res = await api.post<Map<String, dynamic>>(
      Api.authLogin,
      data: {'email': email, 'password': password, 'device': 'mobile'},
    );
    final data = _unwrap(res);
    final token = data['token']?.toString();
    if (token == null || token.isEmpty) {
      throw ApiException(statusCode: 500, message: 'ไม่ได้รับ token จากเซิร์ฟเวอร์');
    }
    await api.setToken(token);
    state = _userToState(data['user'] as Map<String, dynamic>? ?? const {});
  }

  /// Email + password registration. Backend creates the user, returns a token.
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
    required String passwordConfirmation,
  }) async {
    final api = await _ref.read(apiClientProvider.future);
    final res = await api.post<Map<String, dynamic>>(
      Api.authRegister,
      data: {
        'name': name,
        'email': email,
        'password': password,
        'password_confirmation': passwordConfirmation,
        'device': 'mobile',
      },
    );
    final data = _unwrap(res);
    final token = data['token']?.toString();
    if (token == null || token.isEmpty) {
      throw ApiException(statusCode: 500, message: 'ไม่ได้รับ token จากเซิร์ฟเวอร์');
    }
    await api.setToken(token);
    state = _userToState(data['user'] as Map<String, dynamic>? ?? const {});
  }

  Future<void> signOut() async {
    final api = await _ref.read(apiClientProvider.future);
    try {
      await api.post(Api.authLogout);
    } catch (_) {/* tolerate offline logout */}
    await api.clearToken();
    state = const AuthGuest();
  }

  /// Helpers ---------------------------------------------------------

  Map<String, dynamic> _unwrap(Map<String, dynamic> res) {
    final inner = res['data'];
    return inner is Map<String, dynamic> ? inner : res;
  }

  AuthAuthenticated _userToState(Map<String, dynamic> u) {
    final wallet = u['wallet'];
    double? balance;
    String currency = 'THB';
    if (wallet is Map) {
      balance = (wallet['balance'] as num?)?.toDouble();
      currency = wallet['currency']?.toString() ?? 'THB';
    }
    return AuthAuthenticated(
      userId: u['id']?.toString() ?? '',
      displayName: u['display_name']?.toString()
          ?? u['name']?.toString()
          ?? 'แขก',
      email: u['email']?.toString(),
      walletBalance: balance,
      walletCurrency: currency,
      thaipromptLinked: (u['thaiprompt_linked'] as bool?) ?? false,
    );
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref);
});
