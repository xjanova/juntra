import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/affiliate/affiliate_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/chat/conversation_list_screen.dart';
import '../features/history/history_screen.dart';
import '../features/home/home_screen.dart';
import '../features/natal/natal_screen.dart';
import '../features/payment/payment_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/reading/reading_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/share/share_screen.dart';
import '../features/shuffle/shuffle_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/spreads/spreads_screen.dart';
import '../features/wallet/wallet_screen.dart';

/// Root navigator key — required by [UpdateObserver] so the update dialog
/// can attach to a Navigator that exists ABOVE the router builder. See
/// `core/update/update_observer.dart` for the full story.
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// 12-screen route table — names match `extracted/juntra/project/app.jsx`
/// `screens` map exactly so the design's intent stays grep-able.
class Routes {
  Routes._();
  static const splash = '/';
  static const home = '/home';
  static const spreads = '/spreads';
  static const shuffle = '/shuffle';
  static const reading = '/reading';
  static const payment = '/payment';
  static const chat = '/chat';
  static const chatConversations = '/chat-conversations';
  static const history = '/history';
  static const profile = '/profile';
  static const natal = '/natal';
  static const affiliate = '/affiliate';
  static const share = '/share';
  static const login = '/login';
  static const wallet = '/wallet';
  static const settings = '/settings';
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.splash,
    debugLogDiagnostics: false,
    routes: [
      GoRoute(path: Routes.splash, builder: (c, s) => const SplashScreen()),
      GoRoute(path: Routes.home, builder: (c, s) => const HomeScreen()),
      GoRoute(
        path: Routes.spreads,
        builder: (c, s) => SpreadsScreen(
          categoryId: s.uri.queryParameters['category'],
        ),
      ),
      GoRoute(
        path: Routes.shuffle,
        builder: (c, s) => ShuffleScreen(
          spreadId: s.uri.queryParameters['spread'] ?? 'three',
          categoryId: s.uri.queryParameters['category'],
        ),
      ),
      GoRoute(
        path: Routes.reading,
        builder: (c, s) {
          // After-shuffle path: `?id=<readingId>` → fetch from API.
          // Unsupported-spread / direct nav path: `?spread=<id>` →
          // legacy hand-rolled sample reading. ReadingScreen branches
          // internally based on which is present.
          final idStr = s.uri.queryParameters['id'];
          final id = idStr == null ? null : int.tryParse(idStr);
          return ReadingScreen(
            readingId: id,
            spreadId: id == null
                ? (s.uri.queryParameters['spread'] ?? 'three')
                : null,
          );
        },
      ),
      GoRoute(
        path: Routes.payment,
        builder: (c, s) => PaymentScreen(
          spreadId: s.uri.queryParameters['spread'] ?? 'three',
          amount: int.tryParse(s.uri.queryParameters['amount'] ?? '0') ?? 0,
        ),
      ),
      GoRoute(
        path: Routes.chat,
        builder: (c, s) {
          // `?id=N` resumes an existing conversation; bare `/chat`
          // starts a fresh one. ChatScreen branches in _bootstrap().
          final idStr = s.uri.queryParameters['id'];
          final id = idStr == null ? null : int.tryParse(idStr);
          return ChatScreen(resumeConversationId: id);
        },
      ),
      GoRoute(
        path: Routes.chatConversations,
        builder: (c, s) => const ConversationListScreen(),
      ),
      GoRoute(path: Routes.history, builder: (c, s) => const HistoryScreen()),
      GoRoute(path: Routes.profile, builder: (c, s) => const ProfileScreen()),
      GoRoute(path: Routes.natal, builder: (c, s) => const NatalScreen()),
      GoRoute(path: Routes.affiliate, builder: (c, s) => const AffiliateScreen()),
      GoRoute(path: Routes.share, builder: (c, s) => const ShareScreen()),
      GoRoute(path: Routes.login, builder: (c, s) => const LoginScreen()),
      GoRoute(path: Routes.wallet, builder: (c, s) => const WalletScreen()),
      GoRoute(path: Routes.settings, builder: (c, s) => const SettingsScreen()),
    ],
  );
});
