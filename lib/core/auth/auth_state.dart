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

/// ยังไม่รู้ว่าใครล็อกอินอยู่ เพราะ **ติดต่อเซิร์ฟเวอร์ไม่ได้** (ไม่ใช่ 401)
///
/// แยกจาก [AuthUnknown] (กำลังโหลดอยู่) และ [AuthGuest] (เป็นแขกจริง ๆ) เพราะ
/// ทั้งสองอย่างนั้นให้หน้าจอผิด: หมุนค้างตลอดกาล หรือบอกผู้ใช้ที่ล็อกอินอยู่ว่า
/// เป็นผู้เยี่ยมชมพร้อมยอดเครดิตหายทั้งก้อน — ตกใจว่าเงินหาย
///
/// token ยังอยู่ในเครื่อง แค่ยังยืนยันไม่ได้ → หน้าจอควรเสนอปุ่มลองใหม่
class AuthOffline extends AuthState {
  const AuthOffline();
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({
    required this.userId,
    required this.displayName,
    this.email,
    this.phone,
    this.walletBalance,
    this.walletCurrency = 'THB',
    this.thaipromptLinked = false,
  });
  final String userId;
  final String displayName;

  /// อีเมลจริงของผู้ใช้ — null เมื่อสมัครด้วยเบอร์อย่างเดียว
  /// (เซิร์ฟเวอร์กรองอีเมลภายในที่สร้างให้ออกแล้ว ห้ามเอามาโชว์)
  final String? email;
  final String? phone;
  final double? walletBalance;
  final String walletCurrency;
  final bool thaipromptLinked;

  /// สิ่งที่ผู้ใช้ใช้เข้าระบบ — เอาไว้โชว์ในหน้าโปรไฟล์/ตั้งค่า
  String? get loginHint => email ?? phone;

  AuthAuthenticated copyWith({double? walletBalance}) => AuthAuthenticated(
        userId: userId,
        displayName: displayName,
        email: email,
        phone: phone,
        walletBalance: walletBalance ?? this.walletBalance,
        walletCurrency: walletCurrency,
        thaipromptLinked: thaipromptLinked,
      );

  @override
  List<Object?> get props => [
        userId,
        displayName,
        email,
        phone,
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
    } on ApiException catch (e) {
      // 401 = token ถูกเพิกถอนจริง → เป็นแขก (ApiClient ล้าง token ให้แล้ว)
      if (e.statusCode == 401) {
        state = const AuthGuest();
        return;
      }
      // 🔴 นอกนั้น (เน็ตตก / DNS / 5xx) **ห้ามเด้งเป็นแขก** — token ยังใช้ได้อยู่
      // ของเดิม catch ทุกอย่างแล้วตั้ง AuthGuest ผู้ใช้ที่เปิดแอพตอนสัญญาณอ่อน
      // จึงเห็นตัวเองเป็นผู้เยี่ยมชมและยอดเครดิตหายทั้งก้อน ตกใจว่าเงินหาย
      // (refresh() ในไฟล์เดียวกันทำถูกมาตลอด — คงสถานะเดิมไว้เมื่อ error ชั่วคราว)
      state = const AuthOffline();
    } catch (_) {
      state = const AuthOffline();
    }
  }

  /// ลองบูตใหม่ — ผูกกับปุ่ม "เชื่อมต่อไม่ได้ · แตะเพื่อลองใหม่"
  Future<void> retryBootstrap() => _bootstrap();

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

  /// เข้าสู่ระบบด้วย **อีเมลหรือเบอร์โทร** — ต้องรับได้ทั้งคู่เหมือนฝั่งเว็บ
  ///
  /// เว็บยอมให้สมัครด้วยเบอร์อย่างเดียวแล้วสร้างอีเมลภายในให้เงียบ ๆ
  /// เจ้าตัวจึงไม่มีทางรู้อีเมลของตัวเอง ถ้าแอพยังบังคับอีเมล ลูกค้ากลุ่มนี้
  /// (ผู้สูงอายุ ซึ่งเป็นลูกค้าหลัก) จะเข้าแอพไม่ได้เลยทั้งที่มีบัญชีอยู่แล้ว
  ///
  /// ส่งคีย์ `login` ซึ่งเซิร์ฟเวอร์รับเป็นอีเมลหรือเบอร์ก็ได้
  /// Throws [ApiException] on 401/422 etc. so the UI can show the message.
  Future<void> signIn({required String login, required String password}) async {
    final api = await _ref.read(apiClientProvider.future);
    final res = await api.post<Map<String, dynamic>>(
      Api.authLogin,
      data: {'login': login, 'password': password, 'device': 'mobile'},
    );
    final data = _unwrap(res);
    final token = data['token']?.toString();
    if (token == null || token.isEmpty) {
      throw ApiException(statusCode: 500, message: 'ไม่ได้รับ token จากเซิร์ฟเวอร์');
    }
    await api.setToken(token);
    state = _userToState(data['user'] as Map<String, dynamic>? ?? const {});
  }

  /// สมัครสมาชิก — ต้องกรอก **อีเมลหรือเบอร์โทร อย่างน้อยอย่างใดอย่างหนึ่ง**
  /// (เงื่อนไขเดียวกับฟอร์มสมัครของเว็บ) ช่องที่ไม่ได้กรอกจะไม่ถูกส่งขึ้นไป
  /// เพื่อไม่ให้ `required_without` ฝั่งเซิร์ฟเวอร์เห็นเป็นสตริงว่าง
  Future<void> signUp({
    required String name,
    String? email,
    String? phone,
    required String password,
    required String passwordConfirmation,
    String? referralCode,
  }) async {
    final api = await _ref.read(apiClientProvider.future);
    final res = await api.post<Map<String, dynamic>>(
      Api.authRegister,
      data: {
        'name': name,
        if (email != null && email.isNotEmpty) 'email': email,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        // โค้ดผู้แนะนำ — คุกกี้ juntra_ref อยู่ในเบราว์เซอร์ เดินทางเข้าแอพไม่ได้
        // ถ้าไม่ส่งช่องนี้ คนที่กดลิงก์เชิญแล้วมาสมัครในแอพจะไม่ถูกผูกสายงานเลย
        // ผู้แนะนำเสียคอมมิชชั่นทั้งสายโดยไม่มีใครรู้
        if (referralCode != null && referralCode.isNotEmpty)
          'referral_code': referralCode,
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
      phone: u['phone']?.toString(),
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
