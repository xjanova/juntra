import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'endpoints.dart';

/// สิ่งที่เซิร์ฟเวอร์บอกแอพตอนเปิด (`GET /v1/app/config`) — บริการไหนเปิดขาย
/// ลิงก์นโยบาย/ลบบัญชี และเติมเครดิตผ่าน Google Play ได้ไหม
///
/// ทำไมต้องมี: หลังบ้านปิดขายบริการได้ (ServiceGate — ตอนนี้เหลือแต่ไพ่กับแชท) หน้าเว็บ
/// ซ่อนลิงก์ของบริการที่ปิดไว้ทุกที่ แต่แอพเคยโชว์ครบ ลูกค้ากดเข้าไปแล้วค่อยเจอ
/// "ปิดปรับปรุงชั่วคราว" — ตอนนี้แอพซ่อนตามสวิตช์เดียวกับเว็บ
@immutable
class AppConfig {
  const AppConfig({
    required this.services,
    this.googlePlayBilling = false,
    this.privacyUrl = kPrivacyUrl,
    this.termsUrl = kTermsUrl,
    this.accountDeletionUrl = kAccountDeletionUrl,
    this.supportEmail = kSupportEmail,
    this.supportLine,
    this.fromServer = false,
  });

  static const kPrivacyUrl = 'https://xn--82c4af5bzdj.online/privacy';
  static const kTermsUrl = 'https://xn--82c4af5bzdj.online/terms';
  static const kAccountDeletionUrl = 'https://xn--82c4af5bzdj.online/account/delete';
  static const kSupportEmail = 'hello@xn--82c4af5bzdj.online';

  /// ยังไม่เคยคุยกับเซิร์ฟเวอร์ได้เลย (เปิดครั้งแรกแบบออฟไลน์) — โชว์เฉพาะสิ่งที่
  /// ปิดขายไม่ได้ (ไพ่ + แชท) ดีกว่าโชว์บริการที่อาจปิดอยู่แล้วให้ลูกค้ากดไปเจอทางตัน
  static const fallback = AppConfig(services: {'tarot': true, 'chat': true});

  /// service key → เปิดขายอยู่ไหม (tarot · chat · numerology · auspicious ·
  /// palmistry · deep · horoscope)
  final Map<String, bool> services;
  final bool googlePlayBilling;
  final String privacyUrl;
  final String termsUrl;
  final String accountDeletionUrl;
  final String supportEmail;
  final String? supportLine;
  final bool fromServer;

  /// ไม่รู้จักบริการนี้ = ถือว่าปิด (บริการใหม่ในอนาคตต้องให้เซิร์ฟเวอร์เปิดเอง)
  bool isOpen(String service) => services[service] ?? false;

  /// อีเมลสำหรับแสดงผล — โดเมนเป็นภาษาไทยแบบที่เว็บแสดง ("hello@จันทรา.online")
  /// ลิงก์ mailto ยังใช้ [supportEmail] แบบ punycode ที่แอพอีเมลทุกตัวส่งได้
  String get supportEmailDisplay =>
      supportEmail.replaceAll('xn--82c4af5bzdj.online', 'จันทรา.online');

  factory AppConfig.fromJson(Map<String, dynamic> j) {
    final s = j['services'];
    final legal = j['legal'] is Map ? Map<String, dynamic>.from(j['legal'] as Map) : const <String, dynamic>{};
    final support = j['support'] is Map ? Map<String, dynamic>.from(j['support'] as Map) : const <String, dynamic>{};
    final billing = j['billing'] is Map ? Map<String, dynamic>.from(j['billing'] as Map) : const <String, dynamic>{};
    String url(String? v, String d) =>
        (v != null && v.startsWith('https://')) ? v : d;
    return AppConfig(
      services: {
        if (s is Map)
          for (final e in s.entries) e.key.toString(): e.value == true,
      },
      googlePlayBilling: billing['google_play'] == true,
      privacyUrl: url(legal['privacy_url']?.toString(), kPrivacyUrl),
      termsUrl: url(legal['terms_url']?.toString(), kTermsUrl),
      accountDeletionUrl: url(legal['account_deletion_url']?.toString(), kAccountDeletionUrl),
      supportEmail: (support['email']?.toString().contains('@') ?? false)
          ? support['email'].toString()
          : kSupportEmail,
      supportLine: support['line']?.toString(),
      fromServer: true,
    );
  }
}

class AppConfigRepository {
  AppConfigRepository(this._api);
  final ApiClient _api;

  static const _kCacheKey = 'juntra_app_config_v1';

  /// ดึงใหม่จากเซิร์ฟเวอร์ → เก็บไว้ในเครื่อง · ดึงไม่ได้ = ค่าที่เก็บไว้ล่าสุด
  /// (เปิดแอพตอนออฟไลน์ก็ยังซ่อน/โชว์บริการตามที่เซิร์ฟเวอร์เคยบอก) · ไม่เคยมี = fallback
  Future<AppConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final res = await _api.get<Map<String, dynamic>>(Api.appConfig);
      final data = res['data'];
      if (data is Map) {
        final json = Map<String, dynamic>.from(data);
        await prefs.setString(_kCacheKey, jsonEncode(json));
        return AppConfig.fromJson(json);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AppConfig] live load failed: $e');
    }
    final cached = prefs.getString(_kCacheKey);
    if (cached != null) {
      try {
        return AppConfig.fromJson(Map<String, dynamic>.from(jsonDecode(cached) as Map));
      } catch (_) {/* cache เสีย — ใช้ fallback */}
    }
    return AppConfig.fallback;
  }
}

final appConfigProvider = FutureProvider<AppConfig>((ref) async {
  final api = await ref.watch(apiClientProvider.future);
  return AppConfigRepository(api).load();
});

/// ค่าที่ใช้วาดหน้าจอได้ทันที (ยังโหลดอยู่ = fallback) — ไม่ต้อง `.when` ทุกที่
final appConfigValueProvider = Provider<AppConfig>((ref) {
  return ref.watch(appConfigProvider).valueOrNull ?? AppConfig.fallback;
});
