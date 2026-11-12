import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../api/api_exceptions.dart';
import '../api/endpoints.dart';

class SocialProvider {
  const SocialProvider(this.id, this.name);
  final String id;
  final String name;

  static const supported = {
    'facebook': 'Facebook',
    'google': 'Google',
    'line': 'LINE',
    'thaiprompt': 'Thaiprompt',
  };
}

class SocialPkce {
  SocialPkce(this.verifier);
  factory SocialPkce.generate() {
    final random = Random.secure();
    return SocialPkce(
      base64Url
          .encode(List.generate(32, (_) => random.nextInt(256)))
          .replaceAll('=', ''),
    );
  }

  final String verifier;
  String get challenge => base64Url
      .encode(sha256.convert(ascii.encode(verifier)).bytes)
      .replaceAll('=', '');
}

class SocialLoginTicket {
  const SocialLoginTicket({
    required this.id,
    required this.url,
    required this.expiresAt,
    this.pollInterval = const Duration(seconds: 2),
  });
  final String id;
  final Uri url;
  final DateTime expiresAt;
  final Duration pollInterval;
}

enum SocialLoginStatus { pending, authorized, cancelled, failed, expired }

class SocialLoginResult {
  const SocialLoginResult({
    required this.status,
    this.token,
    this.user,
    this.message,
  });
  final SocialLoginStatus status;
  final String? token;
  final Map<String, dynamic>? user;
  final String? message;

  factory SocialLoginResult.fromJson(Map<String, dynamic> data) {
    final status = switch (data['status']) {
      'pending' => SocialLoginStatus.pending,
      'authorized' => SocialLoginStatus.authorized,
      'cancelled' => SocialLoginStatus.cancelled,
      'failed' => SocialLoginStatus.failed,
      'expired' => SocialLoginStatus.expired,
      _ => throw _invalidResponse(),
    };
    final token = data['token'];
    final user = data['user'];
    if (status == SocialLoginStatus.authorized &&
        (token is! String ||
            token.isEmpty ||
            user is! Map ||
            (user['id']?.toString().isEmpty ?? true))) {
      throw _invalidResponse();
    }
    return SocialLoginResult(
      status: status,
      token: status == SocialLoginStatus.authorized ? token as String : null,
      user: status == SocialLoginStatus.authorized
          ? Map<String, dynamic>.from(user as Map)
          : null,
      message: data['message'] is String ? data['message'] as String : null,
    );
  }
}

ApiException _invalidResponse() => ApiException(
  statusCode: 502,
  message: 'ยืนยันการเข้าสู่ระบบไม่สำเร็จ กรุณาลองใหม่อีกครั้ง',
);

class SocialAuthRepository {
  SocialAuthRepository(this.api);
  final ApiClient api;

  Map<String, dynamic> _data(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is! Map) throw _invalidResponse();
    return Map<String, dynamic>.from(data);
  }

  Future<List<SocialProvider>> providers() async {
    final data = _data(
      await api.get<Map<String, dynamic>>(Api.authSocialProviders),
    );
    final raw = data['providers'];
    if (raw is! List) throw _invalidResponse();
    final seen = <String>{};
    return [
      for (final item in raw)
        if (item is Map &&
            SocialProvider.supported.containsKey(item['id']) &&
            seen.add(item['id'] as String))
          SocialProvider(
            item['id'] as String,
            SocialProvider.supported[item['id']]!,
          ),
    ];
  }

  Future<SocialLoginTicket> start({
    required String provider,
    required SocialPkce proof,
    String? referralCode,
  }) async {
    final data = _data(
      await api.post<Map<String, dynamic>>(
        Api.authSocialStart,
        data: {
          'provider': provider,
          'code_challenge': proof.challenge,
          'device': 'mobile',
          if (referralCode != null && referralCode.isNotEmpty)
            'referral_code': referralCode,
        },
      ),
    );
    final id = data['id'];
    final url = Uri.tryParse(data['url']?.toString() ?? '');
    final base = Uri.parse(api.dio.options.baseUrl);
    final expires = int.tryParse('${data['expires_in']}');
    final interval = int.tryParse('${data['poll_interval']}') ?? 2;
    if (id is! String ||
        id.isEmpty ||
        url == null ||
        url.scheme != base.scheme ||
        url.host != base.host ||
        url.port != base.port ||
        url.userInfo.isNotEmpty ||
        url.hasFragment ||
        !['https', 'http'].contains(url.scheme) ||
        expires == null ||
        expires <= 0 ||
        expires > 600) {
      throw _invalidResponse();
    }
    return SocialLoginTicket(
      id: id,
      url: url,
      expiresAt: DateTime.now().add(Duration(seconds: expires)),
      pollInterval: Duration(seconds: interval.clamp(2, 15)),
    );
  }

  Future<SocialLoginResult> poll({
    required String id,
    required SocialPkce proof,
  }) async {
    return SocialLoginResult.fromJson(
      _data(
        await api.post<Map<String, dynamic>>(
          Api.authSocialPoll,
          data: {'id': id, 'code_verifier': proof.verifier},
        ),
      ),
    );
  }
}

final socialAuthRepositoryProvider = FutureProvider<SocialAuthRepository>((
  ref,
) async {
  return SocialAuthRepository(await ref.watch(apiClientProvider.future));
});

final socialProvidersProvider =
    FutureProvider.autoDispose<List<SocialProvider>>((ref) async {
      return (await ref.watch(socialAuthRepositoryProvider.future)).providers();
    });

final socialBrowserLauncherProvider = Provider<Future<bool> Function(Uri)>((
  ref,
) {
  return (url) => launchUrl(url, mode: LaunchMode.externalApplication);
});
