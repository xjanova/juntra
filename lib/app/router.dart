import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/affiliate/affiliate_screen.dart';
import '../features/auspicious/auspicious_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/chat/rooms_screen.dart';
import '../features/collection/collection_screen.dart';
import '../features/daily_luck/daily_luck_screen.dart';
import '../features/free_card/free_card_screen.dart';
import '../features/profile/account_profile_screen.dart';
import '../features/settings/notification_settings_screen.dart';
import '../features/deep/deep_screen.dart';
import '../features/horoscope/horoscope_screen.dart';
import '../features/chat/conversation_list_screen.dart';
import '../features/history/history_screen.dart';
import '../features/home/home_screen.dart';
import '../features/natal/natal_screen.dart';
import '../features/numerology/numerology_screen.dart';
import '../features/palmistry/palmistry_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/reading/reading_screen.dart';
import '../features/settings/delete_account_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/horoscope/thai_zodiac_screen.dart';
import '../features/share/share_screen.dart';
import '../features/shuffle/shuffle_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/spreads/spreads_screen.dart';
import '../features/wallet/transactions_screen.dart';
import '../features/wallet/wallet_screen.dart';
import '../shared/widgets/service_gate.dart';

/// Root navigator key — required by [UpdateObserver] so the update dialog
/// can attach to a Navigator that exists ABOVE the router builder. See
/// `core/update/update_observer.dart` for the full story.
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Route table. Screens follow the website's pages (จันทรา.online, 2026-11):
/// room picker → oracle room chat → shuffle → reading, plus the account
/// extras the web added (daily luck, card collection, astrology profile).
class Routes {
  Routes._();
  static const splash = '/';
  static const home = '/home';

  /// หน้า "เลือกผู้พยากรณ์" (เว็บ /chat ที่ยังไม่เลือกห้อง) — บุษบา · แม่หมอ · คุณไสย
  static const rooms = '/rooms';

  /// ไพ่ฟรี 1 ใบ (เว็บ /tarot/free) → ห้องถามฟรี 2 นาที
  static const freeCard = '/free-card';

  /// เช็กอินรายวัน + ดวงเสี่ยงทายประจำวัน (เว็บ dashboard#daily-luck)
  static const dailyLuck = '/daily-luck';

  /// สมุดสะสมไพ่ 78 ใบ (เว็บ /account/collection)
  static const collection = '/collection';

  /// ชื่อ · วันเกิด · เวลาเกิด · สถานที่เกิด (เว็บ /account/astrology + /profile)
  static const accountProfile = '/account-profile';

  /// การแจ้งเตือน (เว็บ push preferences)
  static const notifications = '/notifications';
  static const spreads = '/spreads';
  static const shuffle = '/shuffle';
  static const reading = '/reading';
  static const numerology = '/numerology';
  static const auspicious = '/auspicious';
  static const palmistry = '/palmistry';
  static const horoscope = '/horoscope';

  /// ดูดวงเชิงลึก 39฿ — แพ็กเดียวกับเว็บและบอท FB/LINE
  static const deep = '/deep';
  static const chat = '/chat';
  static const chatConversations = '/chat-conversations';
  static const history = '/history';
  static const profile = '/profile';
  static const natal = '/natal';
  static const affiliate = '/affiliate';
  static const share = '/share';
  static const thaiZodiac = '/thai-zodiac';
  static const login = '/login';
  static const wallet = '/wallet';
  static const transactions = '/transactions';
  static const settings = '/settings';
  /// ลบบัญชีและข้อมูลในแอพ (Google Play บังคับให้มีทางลบบัญชีในแอพ)
  static const deleteAccount = '/delete-account';
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
          // คำถามที่ลูกค้าพิมพ์ในแชทตอนแม่หมอยื่นแพ็กเกจ — ไม่ต้องพิมพ์ซ้ำ
          initialQuestion: s.uri.queryParameters['q'],
        ),
      ),
      GoRoute(
        path: Routes.reading,
        builder: (c, s) {
          // `?id=<readingId>` → คำทำนายจากเซิร์ฟเวอร์ (หน้าผลถามสถานะเองถ้ายังอ่านไม่เสร็จ)
          // ไม่มี id = ไม่มีอะไรให้แสดง (โหมดคำทำนายตัวอย่างถูกลบแล้ว)
          final id = int.tryParse(s.uri.queryParameters['id'] ?? '');
          return ReadingScreen(readingId: id);
        },
      ),
      GoRoute(
        path: Routes.chat,
        builder: (c, s) {
          // `?id=N` resumes an existing conversation; bare `/chat`
          // starts a fresh one. ChatScreen branches in _bootstrap().
          final idStr = s.uri.queryParameters['id'];
          final id = idStr == null ? null : int.tryParse(idStr);
          // `?reading=N` = คุยต่อจากคำทำนายไพ่ใบนั้น (แม่หมอเห็นไพ่+คำพยากรณ์ชุดนั้น)
          final readingId = int.tryParse(s.uri.queryParameters['reading'] ?? '');
          // `?room=busaba|maemor|kunsai` = เข้าห้องของผู้พยากรณ์คนนั้น · `?new=1` = ห้องคุยใหม่
          return ChatScreen(
            resumeConversationId: id,
            fromReadingId: readingId,
            room: s.uri.queryParameters['room'],
            startNew: s.uri.queryParameters['new'] == '1',
          );
        },
      ),
      GoRoute(path: Routes.rooms, builder: (c, s) => const RoomsScreen()),
      GoRoute(path: Routes.freeCard, builder: (c, s) => const FreeCardScreen()),
      GoRoute(path: Routes.dailyLuck, builder: (c, s) => const DailyLuckScreen()),
      GoRoute(path: Routes.collection, builder: (c, s) => const CollectionScreen()),
      GoRoute(path: Routes.accountProfile, builder: (c, s) => const AccountProfileScreen()),
      GoRoute(path: Routes.notifications, builder: (c, s) => const NotificationSettingsScreen()),
      GoRoute(
        path: Routes.chatConversations,
        builder: (c, s) => const ConversationListScreen(),
      ),
      GoRoute(path: Routes.numerology, builder: (c, s) => const ServiceGate(service: 'numerology', name: 'ดวงเลขศาสตร์', child: NumerologyScreen())),
      GoRoute(path: Routes.auspicious, builder: (c, s) => const ServiceGate(service: 'auspicious', name: 'หาฤกษ์ยาม', child: AuspiciousScreen())),
      GoRoute(path: Routes.palmistry, builder: (c, s) => const ServiceGate(service: 'palmistry', name: 'ดูลายมือ', child: PalmistryScreen())),
      GoRoute(
        path: Routes.horoscope,
        builder: (c, s) => ServiceGate(
          service: 'horoscope',
          name: 'ดวงรายวัน',
          child: HoroscopeScreen(initialSlug: s.uri.queryParameters['sign']),
        ),
      ),
      GoRoute(path: Routes.deep, builder: (c, s) => const ServiceGate(service: 'deep', name: 'ดูดวงเชิงลึก', child: DeepScreen())),
      GoRoute(path: Routes.history, builder: (c, s) => const HistoryScreen()),
      GoRoute(path: Routes.profile, builder: (c, s) => const ProfileScreen()),
      GoRoute(path: Routes.natal, builder: (c, s) => const NatalScreen()),
      GoRoute(path: Routes.affiliate, builder: (c, s) => const AffiliateScreen()),
      GoRoute(path: Routes.thaiZodiac, builder: (c, s) => const ServiceGate(service: 'horoscope', name: 'ดวงปีนักษัตร', child: ThaiZodiacScreen())),
      GoRoute(
        path: Routes.share,
        // ส่ง id ของคำทำนายไปด้วย ลิงก์ที่แชร์จะได้พาไปหน้าผลจริง
        // ไม่ใช่หน้าแรกของเว็บเฉย ๆ
        builder: (c, s) => ShareScreen(
          readingId: int.tryParse(s.uri.queryParameters['id'] ?? ''),
        ),
      ),
      GoRoute(path: Routes.login, builder: (c, s) => const LoginScreen()),
      GoRoute(path: Routes.wallet, builder: (c, s) => const WalletScreen()),
      GoRoute(path: Routes.transactions, builder: (c, s) => const TransactionsScreen()),
      GoRoute(path: Routes.settings, builder: (c, s) => const SettingsScreen()),
      GoRoute(path: Routes.deleteAccount, builder: (c, s) => const DeleteAccountScreen()),
    ],
  );
});
