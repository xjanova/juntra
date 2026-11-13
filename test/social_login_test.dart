import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juntra/core/api/api_client.dart';
import 'package:juntra/core/api/api_exceptions.dart';
import 'package:juntra/core/api/endpoints.dart';
import 'package:juntra/core/auth/auth_state.dart';
import 'package:juntra/core/auth/social_auth.dart';
import 'package:juntra/features/auth/social_login_panel.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Map<String, dynamic> Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode({'data': respond(options)}),
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
  @override
  void close({bool force = false}) {}
}

class _Auth extends AuthController {
  _Auth(super.ref);
  int logins = 0;
  @override
  Future<void> completeSocialSignIn(SocialLoginResult result) async {
    logins++;
  }
}

class _Repo extends SocialAuthRepository {
  _Repo(super.api);
  int starts = 0;
  int polls = 0;
  String? referral;
  Completer<SocialLoginResult>? waiting;
  bool rejectBrowser = false;
  Duration expires = const Duration(minutes: 5);
  SocialLoginResult result = const SocialLoginResult(
    status: SocialLoginStatus.pending,
  );
  @override
  Future<SocialLoginTicket> start({
    required String provider,
    required SocialPkce proof,
    String? referralCode,
  }) async {
    starts++;
    referral = referralCode;
    return SocialLoginTicket(
      id: 'ticket',
      url: Uri.parse(
        'https://xn--82c4af5bzdj.online/auth/mobile/social/ticket',
      ),
      expiresAt: DateTime.now().add(expires),
    );
  }

  @override
  Future<SocialLoginResult> poll({
    required String id,
    required SocialPkce proof,
  }) async {
    polls++;
    return waiting?.future ?? result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<ApiClient> client(
    Map<String, dynamic> Function(RequestOptions) respond,
  ) async {
    final api = await ApiClient.create();
    api.dio.interceptors.clear();
    api.dio.httpClientAdapter = _Adapter(respond);
    addTearDown(api.dio.close);
    return api;
  }

  test('PKCE S256 matches RFC 7636 and each login has a fresh verifier', () {
    final proof = SocialPkce('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk');
    expect(proof.challenge, 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
    final a = SocialPkce.generate();
    final b = SocialPkce.generate();
    expect(a.verifier, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    expect(a.verifier, isNot(b.verifier));
  });

  test(
    'only enabled, known providers appear once, using trusted names',
    () async {
      final api = await client((request) {
        expect(request.path, Api.authSocialProviders);
        return {
          'providers': [
            {'id': 'facebook', 'name': 'untrusted label'},
            {'id': 'facebook'},
            {'id': 'unknown'},
            {'id': 'google'},
          ],
        };
      });
      final providers = await SocialAuthRepository(api).providers();
      expect(providers.map((p) => p.id), ['facebook', 'google']);
      expect(providers.map((p) => p.name), ['Facebook', 'Google']);
    },
  );

  test(
    'start sends only PKCE challenge and accepts a same-origin HTTPS URL',
    () async {
      final proof = SocialPkce.generate();
      final api = await client((request) {
        expect(request.method, 'POST');
        expect(request.path, Api.authSocialStart);
        expect(request.queryParameters, isEmpty);
        expect(request.data, {
          'provider': 'google',
          'code_challenge': proof.challenge,
          'device': 'mobile',
          'referral_code': 'boss',
        });
        return {
          'id': 'ticket',
          'url': 'https://xn--82c4af5bzdj.online/auth/mobile/social/ticket',
          'expires_in': 300,
          'poll_interval': 1,
        };
      });
      final ticket = await SocialAuthRepository(
        api,
      ).start(provider: 'google', proof: proof, referralCode: 'boss');
      expect(ticket.url.toString(), isNot(contains(proof.verifier)));
      expect(ticket.pollInterval, const Duration(seconds: 2));
    },
  );

  for (final url in [
    'https://attacker.example/auth',
    'http://xn--82c4af5bzdj.online/auth',
    'https://xn--82c4af5bzdj.online:8443/auth',
    'https://user@xn--82c4af5bzdj.online/auth',
    'https://xn--82c4af5bzdj.online/auth#token=untrusted',
    'intent://auth',
  ]) {
    test('reject browser launch outside trusted origin: $url', () async {
      final api = await client(
        (_) => {'id': 'ticket', 'url': url, 'expires_in': 300},
      );
      await expectLater(
        SocialAuthRepository(
          api,
        ).start(provider: 'facebook', proof: SocialPkce.generate()),
        throwsA(isA<ApiException>()),
      );
    });
  }

  test(
    'poll sends verifier in POST body and only accepts complete authorized results',
    () async {
      final proof = SocialPkce.generate();
      final api = await client((request) {
        expect(request.path, Api.authSocialPoll);
        expect(request.method, 'POST');
        expect(request.queryParameters, isEmpty);
        expect(request.data, {'id': 'ticket', 'code_verifier': proof.verifier});
        return {
          'status': 'authorized',
          'token': 'test-token',
          'user': {'id': 42, 'name': 'คุณ'},
        };
      });
      final result = await SocialAuthRepository(
        api,
      ).poll(id: 'ticket', proof: proof);
      expect(result.status, SocialLoginStatus.authorized);
      expect(result.user?['id'], 42);
      for (final bad in [
        {'status': 'authorized', 'token': 'secret'},
        {
          'status': 'authorized',
          'token': '',
          'user': {'id': 42},
        },
        {'status': 'authorized', 'token': 'secret', 'user': {}},
        {
          'token': 'secret',
          'user': {'id': 42},
        },
      ]) {
        expect(
          () => SocialLoginResult.fromJson(bad),
          throwsA(isA<ApiException>()),
        );
      }
    },
  );

  test(
    'authorized social login persists the same account shape as password login',
    () async {
      final api = await client((_) => {});
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) async => api)],
      );
      addTearDown(container.dispose);
      final auth = container.read(authControllerProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      await auth.completeSocialSignIn(
        SocialLoginResult.fromJson({
          'status': 'authorized',
          'token': 'test-token',
          'user': {
            'id': 42,
            'name': 'คุณทดสอบ',
            'wallet': {'balance': 25, 'currency': 'THB'},
          },
        }),
      );
      expect(await api.getToken(), 'test-token');
      final state = container.read(authControllerProvider) as AuthAuthenticated;
      expect(state.userId, '42');
      expect(state.displayName, 'คุณทดสอบ');
      expect(state.walletBalance, 25);
      await expectLater(
        auth.completeSocialSignIn(
          const SocialLoginResult(status: SocialLoginStatus.pending),
        ),
        throwsA(isA<ApiException>()),
      );
      expect(await api.getToken(), 'test-token');
    },
  );

  Future<(_Repo, _Auth, List<bool>, List<Uri>, List<bool>)> panel(
    WidgetTester tester,
  ) async {
    final api = await tester.runAsync(() => client((_) => {}));
    final repo = _Repo(api!);
    final busy = <bool>[];
    final launched = <Uri>[];
    final completed = <bool>[];
    late _Auth auth;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWith((ref) async => api),
          socialAuthRepositoryProvider.overrideWith((ref) async => repo),
          socialProvidersProvider.overrideWith(
            (ref) async => const [
              SocialProvider('facebook', 'Facebook'),
              SocialProvider('google', 'Google'),
            ],
          ),
          authControllerProvider.overrideWith((ref) => auth = _Auth(ref)),
          socialBrowserLauncherProvider.overrideWithValue((url) async {
            launched.add(url);
            return !repo.rejectBrowser;
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SocialLoginPanel(
                  onAuthenticated: () => completed.add(true),
                  onBusyChanged: busy.add,
                  referralCode: () => ' latest-ref! ',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // Instantiate the fake before an authorized response needs it.
    final context = tester.element(find.byType(SocialLoginPanel));
    ProviderScope.containerOf(context).read(authControllerProvider);
    await tester.pump();
    return (repo, auth, busy, launched, completed);
  }

  testWidgets('provider buttons fit a narrow screen and open browser once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final (repo, _, busy, launched, _) = await panel(tester);
    expect(find.text('เข้าสู่ระบบด้วย Facebook'), findsOneWidget);
    expect(find.text('เข้าสู่ระบบด้วย Google'), findsOneWidget);
    await tester.tap(find.text('เข้าสู่ระบบด้วย Facebook'));
    await tester.pump();
    expect(repo.starts, 1);
    expect(repo.referral, 'latest-ref');
    expect(launched, hasLength(1));
    expect(busy, [true]);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('ยกเลิก'));
    await tester.pump();
    expect(busy, [true, false]);
  });

  testWidgets('cancel ignores a late authorized result and cannot sign in', (
    tester,
  ) async {
    final (repo, auth, _, _, completed) = await panel(tester);
    repo.waiting = Completer<SocialLoginResult>();
    await tester.tap(find.text('เข้าสู่ระบบด้วย Google'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(repo.polls, 1);
    await tester.tap(find.text('ยกเลิก'));
    await tester.pump();
    repo.waiting!.complete(
      SocialLoginResult.fromJson({
        'status': 'authorized',
        'token': 'test-token',
        'user': {'id': 42},
      }),
    );
    await tester.pump();
    expect(auth.logins, 0);
    expect(completed, isEmpty);
    expect(find.text('เข้าสู่ระบบด้วย Google'), findsOneWidget);
  });

  testWidgets('returning from browser polls immediately and finishes once', (
    tester,
  ) async {
    final (repo, auth, busy, _, completed) = await panel(tester);
    await tester.tap(find.text('เข้าสู่ระบบด้วย Google'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 6));
    expect(repo.polls, 0);
    repo.result = SocialLoginResult.fromJson({
      'status': 'authorized',
      'token': 'test-token',
      'user': {'id': 42},
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(repo.polls, 1);
    expect(auth.logins, 1);
    expect(busy, [true, false]);
    expect(completed, [true]);
    await tester.pump(const Duration(seconds: 10));
    expect(repo.polls, 1);
  });

  for (final status in ['cancelled', 'failed', 'expired']) {
    testWidgets('server $status never signs in and allows a fresh attempt', (
      tester,
    ) async {
      final (repo, auth, busy, _, completed) = await panel(tester);
      repo.result = SocialLoginResult.fromJson({'status': status});
      await tester.tap(find.text('เข้าสู่ระบบด้วย Facebook'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(auth.logins, 0);
      expect(completed, isEmpty);
      expect(busy, [true, false]);
      expect(find.text('เข้าสู่ระบบด้วย Facebook'), findsOneWidget);
    });
  }

  testWidgets('browser failure and request expiry both allow a fresh login', (
    tester,
  ) async {
    final (repo, _, busy, _, _) = await panel(tester);
    repo.rejectBrowser = true;
    await tester.tap(find.text('เข้าสู่ระบบด้วย Facebook'));
    await tester.pump();
    expect(find.textContaining('เปิดหน้าล็อกอินไม่ได้'), findsOneWidget);
    expect(busy, [true, false]);
    repo.rejectBrowser = false;
    repo.expires = const Duration(seconds: 3);
    await tester.tap(find.text('เข้าสู่ระบบด้วย Google'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(find.textContaining('หมดเวลาเข้าสู่ระบบ'), findsOneWidget);
    expect(find.text('เข้าสู่ระบบด้วย Google'), findsOneWidget);
    expect(busy, [true, false, true, false]);
  });
}
