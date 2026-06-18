# CLAUDE.md — Juntra (จันทราพยากรณ์)

> Guidance for Claude Code working on this Flutter app.

## Project identity
- **Name:** จันทราพยากรณ์ (Juntra) — fortune-telling app for "แม่หมอจันทรา"
- **Repo:** `xjanova/juntra` (Flutter mobile)
- **Backend:** `xjanova/juntraweb` Laravel at `จันทรา.online` — the app connects to juntraweb ONLY; juntraweb proxies AI to the Thaiprompt-Affiliate pool server-side
- **Branding:** "POWERED BY XMAN STUDIO" must appear on splash + global footer

## ⚠️ Hard rules

### 1. Never expose GitHub URLs to the user
The auto-update system uses `api.github.com/repos/xjanova/juntra/releases/latest`
internally, but UI text/error messages/links must never reveal it.

- ✅ "ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์อัปเดต"
- ❌ "GitHub API failed" / "Cannot fetch from github.com/..."

If you find a place that leaks a GitHub URL, treat it as a P0 bug.

### 2. AI calls go through the backend pool
Juntra never holds AI provider keys. Every AI call (`/v1/fortune/read`,
`/v1/chat/mae-mor/send`) hits the Laravel backend, which uses
`FortuneAIService` with the shared key pool (Gemini 2.5-flash + Claude +
Groq, with `purpose` filter, `Cache::lock` per-key serialization, and
self-healing — see `Session 2026-05-02 Fortune Bot Major Overhaul` in xman's
brain for the full story).

### 3. Single-keystore signing
All Juntra releases must be signed with the SAME keystore (juntra-upload.jks).
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
HTTP: Dio 5.7 + smart_retry. Storage: flutter_secure_storage + shared_preferences.

## Common tasks

### Add a new screen
1. Create `lib/features/<name>/<name>_screen.dart` with a ConsumerWidget
2. Add to `lib/app/router.dart` route table + `lib/app/router.dart` Routes constants
3. Use `JuntraColors.*` tokens — never hardcode hex
4. Add `StarryBackground` if it's a primary screen

### Add a new API endpoint
1. Add path constant to `lib/core/api/endpoints.dart`
2. Add controller method to `backend-patches/juntra/README.md` (so the
   Thaiprompt-Affiliate maintainer knows what to add)
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
- `docs/RELEASING.md` — full release flow + keystore setup
- `backend-patches/juntra/README.md` — required Laravel patches
- Design source (NOT in this repo): `Juntra-handoff.zip` from claude.ai/design
