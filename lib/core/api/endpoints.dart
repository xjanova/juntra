/// API endpoint constants for the Thaiprompt-Affiliate Laravel backend.
///
/// New `/v1/fortune/*` and `/v1/chat/*` endpoints are added by the backend
/// patch that ships alongside this app (`backend-patches/juntra/`).
class Api {
  Api._();

  // ─── Auth (Sanctum) ──────────────────────────────────────────
  static const login = '/v1/login';
  static const register = '/v1/register';
  static const logout = '/v1/logout';
  static const me = '/v1/me';

  // ─── Profile + birth data ────────────────────────────────────
  static const profile = '/v1/profile';
  static const birthData = '/v1/profile/birth-data';
  static const referralCode = '/v1/profile/referral-code';

  // ─── Fortune (NEW — Juntra mobile API) ───────────────────────
  static const fortuneCategories = '/v1/fortune/categories';
  static const fortuneSpreads = '/v1/fortune/spreads';
  static const fortuneDraw = '/v1/fortune/draw';        // POST start session
  static const fortuneRead = '/v1/fortune/read';        // POST AI interpret
  static const fortuneHistory = '/v1/fortune/history';
  static const fortuneCredits = '/v1/fortune/credits';
  static String fortuneReading(dynamic id) => '/v1/fortune/readings/$id';

  // ─── Mae Mor AI Chat ─────────────────────────────────────────
  static const chatStart = '/v1/chat/mae-mor/start';
  static const chatSend = '/v1/chat/mae-mor/send';
  static String chatSession(dynamic id) => '/v1/chat/mae-mor/sessions/$id';

  // ─── Natal chart (server-side using Swiss Ephemeris) ─────────
  static const natalCompute = '/v1/natal/compute';
  static const natalDailyTransit = '/v1/natal/daily-transit';

  // ─── Payment (PromptPay / TrueMoney / Card) ──────────────────
  static const paymentMethods = '/v1/payment/methods';
  static const paymentInitiate = '/v1/payment/initiate';
  static String paymentStatus(dynamic id) => '/v1/payment/$id/status';

  // ─── Affiliate (MLM downline) ────────────────────────────────
  static const affiliateDashboard = '/v1/affiliate/dashboard';
  static const affiliateDownline = '/v1/affiliate/downline';
  static const affiliateCommissions = '/v1/affiliate/commissions';
  static const affiliateLink = '/v1/affiliate/link';

  // ─── App control ────────────────────────────────────────────
  static const appConfig = '/v1/app/config';
  static const appBanners = '/v1/app/banners';

  // ─── Auto-update (internal — never shown to user) ───────────
  /// GitHub Releases API. Called directly from [UpdateService].
  /// Switch to a self-hosted proxy if rate-limit becomes an issue
  /// (anonymous GH API allows 60 req/IP/hour, plenty for our 6h
  /// throttle even at 10× concurrent users per IP).
  static const githubLatestRelease =
      'https://api.github.com/repos/xjanova/juntra/releases/latest';
}
