/// API endpoint constants for the juntraweb (จันทรา.online) Laravel backend.
///
/// Routes registered under `/api/v1/*` in juntraweb's routes/api.php.
/// Auth is Sanctum bearer token. The Flutter app obtains the token via
/// /auth/login, stores it in flutter_secure_storage, and the [ApiClient]
/// interceptor attaches it as `Authorization: Bearer <token>` on every
/// authenticated request. A 401 response auto-clears the stored token
/// so a server-side revocation can't leave the app wedged.
///
/// AI calls are NOT made directly — juntraweb proxies them to the
/// Thaiprompt-Affiliate API-key pool. The Flutter app only ever speaks
/// to juntraweb (CLAUDE.md hard rule #2: app holds no AI provider keys).
class Api {
  Api._();

  // ─── Public ──────────────────────────────────────────────────
  static const appHealth = '/v1/app/health';

  // ─── Auth (Sanctum) ──────────────────────────────────────────
  static const authLogin    = '/v1/auth/login';
  static const authRegister = '/v1/auth/register';
  static const authMe       = '/v1/auth/me';
  static const authLogout   = '/v1/auth/logout';
  /// Short-lived single-use code for the web OAuth bootstrap (so the bearer
  /// never goes in the mobile-start URL). POST; bearer in the auth header.
  static const authHandoff  = '/v1/auth/handoff';

  // ─── Wallet ─────────────────────────────────────────────────
  static const wallet               = '/v1/wallet';
  static const walletTransactions   = '/v1/wallet/transactions';
  static const walletTopups         = '/v1/wallet/topups';
  static const walletTopupPromptpay = '/v1/wallet/topup/promptpay';
  static String walletTopup(int id) => '/v1/wallet/topup/$id';
  /// Multipart upload of the PromptPay slip image (field name `slip`).
  /// 409 if status != pending; 422 if not a topup tx; 4 MB max image.
  static String walletTopupSlip(int id) => '/v1/wallet/topup/$id/slip';
  /// DELETE — cancel a still-pending top-up (releases the reserved amount).
  static String walletTopupCancel(int id) => '/v1/wallet/topup/$id';

  // ─── Mae Mor AI Chat ─────────────────────────────────────────
  static const chatConversations = '/v1/chat/conversations';
  static String chatConversation(int id) => '/v1/chat/conversations/$id';
  static String chatSend(int id) => '/v1/chat/conversations/$id/send';

  // ─── Reading history (tarot / numerology / palmistry / auspicious) ─
  static const historyReadings = '/v1/history/readings';
  static String historyReading(int id) => '/v1/history/readings/$id';

  // ─── Non-tarot paid readings ─────────────────────────────────
  static const fortuneNumerology = '/v1/fortune/numerology';
  static const fortuneAuspicious = '/v1/fortune/auspicious';
  static const fortunePalmistry  = '/v1/fortune/palmistry';

  // ─── Daily horoscope (free, read-only) ───────────────────────
  static const horoscopeIndex = '/v1/horoscope';
  static String horoscope(String slug) => '/v1/horoscope/$slug';

  // ─── Tarot card catalog (public — real card face images) ─────
  /// Returns every card's resolved face-image URL (or null) + the global
  /// card-back, so the app renders จันทรา.online art and falls back to its
  /// own built-in drawing per card. No auth required.
  static const tarotCards = '/v1/tarot/cards';

  // ─── MLM dashboard (requires thaiprompt_token; 403 unlinked) ────
  static const mlmStats       = '/v1/mlm/stats';
  static const mlmTree        = '/v1/mlm/tree';
  static const mlmCommissions = '/v1/mlm/commissions';

  // ─── Auto-update (internal — never shown to user) ───────────
  /// GitHub Releases API. Called directly from [UpdateService].
  /// Switch to a self-hosted proxy if rate-limit becomes an issue
  /// (anonymous GH API allows 60 req/IP/hour, plenty for our 6h
  /// throttle even at 10× concurrent users per IP).
  static const githubLatestRelease =
      'https://api.github.com/repos/xjanova/juntra/releases/latest';
}
