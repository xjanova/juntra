# CLAUDE.md — Juntra (จันทราพยากรณ์)

> Guidance for Claude Code working on this Flutter app.

## Project identity
- **Name:** จันทราพยากรณ์ (Juntra) — fortune-telling app for "แม่หมอจันทรา"
- **Repo:** `xjanova/juntra` (Flutter mobile)
- **Backend:** `xjanova/juntraweb` Laravel at `จันทรา.online` — the app connects to juntraweb ONLY; juntraweb proxies AI to the Thaiprompt-Affiliate pool server-side
- **Branding:** "POWERED BY XMAN STUDIO" must appear on splash + global footer

## ⚠️ Hard rules

### 0. Two distribution channels — the Google Play build must stay Play-compliant
Gradle flavors `play` (Google Play, App Bundle — the default for `flutter run`)
and `direct` (GitHub APK). Dart reads the channel from `appFlavor` via
`lib/core/app_channel.dart` (`isPlayChannel`; unknown flavor = play).
In the **play** channel NEVER:
- self-update / download APKs / call GitHub (use `PlayUpdateService`, In-App Updates)
- show PromptPay, slip upload, QR, or any button/link/text that leads to paying
  outside Google Play — credits are sold only through `PlayBilling`
  (`lib/core/billing/`), which lets the SERVER verify every purchase token and
  consumes only after the server credited it
- declare `REQUEST_INSTALL_PACKAGES`, `READ_MEDIA_*`, `CAMERA` (only
  `src/direct/AndroidManifest.xml` may add the install permission)
Also required by Play and already built: in-app account deletion
(`/delete-account`), privacy/terms links (Settings + sign-up), a report button
on AI content (reading screen + chat), closed services hidden (`/v1/app/config`).
See `docs/GOOGLE_PLAY.md`.

### 1. Never expose GitHub URLs to the user
The auto-update system (DIRECT channel only) uses
`api.github.com/repos/xjanova/juntra/releases/latest` internally, but UI
text/error messages/links must never reveal it.

- ✅ "ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์อัปเดต"
- ❌ "GitHub API failed" / "Cannot fetch from github.com/..."

If you find a place that leaks a GitHub URL, treat it as a P0 bug.

### 2. AI calls go through the backend
Juntra never holds AI provider keys. Every AI call (tarot readings via
`POST /v1/history/readings`, chat via `/v1/chat/conversations/{id}/send`) hits
juntraweb, which proxies to the Thaiprompt prediction lane server-side.
Tarot purchases use `mode: async`: the server charges, answers 202 with
`status: pending`, reads in the background with the package's own profile, and
the reading screen polls `/v1/history/readings/{id}/status` every 3 s.

### 3. Single-keystore signing + build numbers
All Juntra releases (both channels) must be signed with the SAME keystore
(`android/upload-keystore.jks`, alias `juntra-upload`); on Play use Play App
Signing with this key uploaded, so APK users can move to Play.
Build numbers only go up and stay ≥ 5000 (old per-ABI APKs used 1000×abi+build).
GitHub secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. Lose the keystore = users must
uninstall before they can update.

### 4. Bump on PR merge
PRs MUST carry one of: `release:major` / `release:minor` / `release:patch`
(default) / `release:build` / `release:skip`. The `auto-bump-on-merge.yml`
workflow reads this label.

## Architecture

```
lib/
├── main.dart                ← entry, system chrome
├── app/                     ← MaterialApp.router, go_router, theme
├── core/                    ← api, update, astronomy, auth, storage
├── shared/                  ← widgets (StarryBackground, GoldButton, ...)
│                              data (TAROT_DECK, SPREADS, FORTUNE_CATEGORIES)
└── features/                ← 12 screens (splash, home, ..., share)
                                + features/update/ (UpdateDialog)
```

State: Riverpod 2.6 (no codegen). Routing: go_router 14.
HTTP: Dio 5.7 + smart_retry (POST/PUT/DELETE are retried ONLY when the request
never left the phone — money endpoints must not be re-sent on 5xx/timeouts).
Storage: flutter_secure_storage + shared_preferences.

Data from the server, never hardcoded:
- `GET /v1/app/config` → `appConfigProvider` (open services, legal URLs, Play billing switch)
- `GET /v1/tarot/packages` → `tarotPackagesProvider` (catalog, prices, art, cooldown, birth flag);
  `shared/data/spreads.dart` is only the offline fallback
- user-scoped providers must `ref.watch(sessionUserIdProvider)` so a sign-out or
  account switch drops the previous user's data

## Common tasks

### Add a new screen
1. Create `lib/features/<name>/<name>_screen.dart` with a ConsumerWidget
2. Add to `lib/app/router.dart` route table + `lib/app/router.dart` Routes constants
3. Use `JuntraColors.*` tokens — never hardcode hex
4. Add `StarryBackground` if it's a primary screen

### Add a new API endpoint
1. Add path constant to `lib/core/api/endpoints.dart`
2. The backend is `xjanova/juntraweb` (`routes/api.php`, `app/Http/Controllers/Api/V1`)
3. Call via `ref.read(apiClientProvider.future).then((api) => api.get(...))`

### Bump dependencies
- Don't auto-bump everything. Riverpod 3 has breaking changes — pin to 2.6.x.
- `dio_smart_retry` and `flutter_riverpod` versions match thaipromptapp.

## Cinematic shuffle (signature feature)
`lib/features/shuffle/shuffle_screen.dart` — 5-phase state machine. The
animation timings (shuffle 2000ms, travel 800ms+80ms stagger, reveal 2500ms
each) come from the design handoff §5. Don't shorten them — the cinematic
feel IS the brand.

## See also
- `docs/GOOGLE_PLAY.md` — Play Console, billing products, service account, Data safety
- `docs/RELEASING.md` — full release flow (both channels) + keystore setup
- Design source (NOT in this repo): `Juntra-handoff.zip` from claude.ai/design
