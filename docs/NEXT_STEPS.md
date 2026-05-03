# 🚀 Next Steps — Get Juntra to Production

> Ordered checklist to go from "scaffolded" to "real users installing the APK".

## ✅ Already done (this session)

- [x] Flutter app scaffolded — 12 screens, cinematic shuffle, design tokens
- [x] Auto-update wired to GitHub Releases (UI never exposes provider URLs)
- [x] Android: keystore generated · FileProvider · ABI splits · ProGuard rules
- [x] GitHub Actions: `auto-bump-on-merge.yml` + `release.yml` (4 ABI APKs + AAB)
- [x] Laravel backend patches committed to `xjanova/Thaiprompt-Affiliate`
      branch `claude/Main` commit `bc18bde34`:
      - 5 controllers in `app/Http/Controllers/Api/Juntra/`
      - 42 lines of routes in `routes/api.php` (`/v1/fortune/*`, `/v1/chat/mae-mor/*`,
        `/v1/natal/*`, `/v1/affiliate/*`, `/v1/payment/*`)
- [x] Flutter `FortuneRepository` + `ChatRepository` calling backend
- [x] Mae Mor chat screen wired to real `/v1/chat/mae-mor/send`
- [x] Tag `v0.1.0+2` pushed → CI building release APK

## 🔑 1. Upload signing keystore to GitHub Secrets (5 minutes)

Without this, every CI release ships a debug-signed APK that **cannot
install over a previous install with a different signature**.

```powershell
# Encode the keystore once
cd E:\juntra-build\android
[Convert]::ToBase64String([IO.File]::ReadAllBytes('upload-keystore.jks')) | Set-Clipboard
# Now paste into GitHub Secrets:
```

Open https://github.com/xjanova/juntra/settings/secrets/actions and add **4** secrets:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | (paste from clipboard above) |
| `ANDROID_KEYSTORE_PASSWORD` | `xJu3wuVpYQy8kAuWfMYbyQSE` |
| `ANDROID_KEY_ALIAS` | `juntra-upload` |
| `ANDROID_KEY_PASSWORD` | `xJu3wuVpYQy8kAuWfMYbyQSE` |

**Then re-run the release workflow** (Actions → Release → most recent run → Re-run jobs)
to produce a properly-signed APK.

> ⚠️ The plaintext password lives in `KEYSTORE_INFO.md` (gitignored). **Back up
> `upload-keystore.jks` + that file to 1Password / encrypted USB right now**.
> Lose them and you'll have to ship a new app with a new package name.

## 🌐 2. Deploy backend patches to production (`main.thaiprompt.online`)

Backend patches are already merged into `claude/Main`. Pull them on the server:

```bash
ssh xjanova@main.thaiprompt.online
cd ~/domains/main.thaiprompt.online/public_html
git fetch origin && git pull --ff-only origin claude/Main
php artisan route:cache
php artisan view:clear
# Smoke test
php artisan route:list --path=v1/fortune | head -10
```

Expected output: 7 fortune routes + 3 chat + 2 natal + 4 affiliate + 3 payment = 19 routes total under `api.juntra.*`.

## 📲 3. Install the APK

After CI release publishes (Actions tab → green checkmark on `Release · v0.1.0+2`):

```
https://github.com/xjanova/juntra/releases/latest
→ Download juntra-0.1.0-arm64-v8a.apk (or universal)
→ ADB push to device, OR send via LINE to your phone
→ Open file → "Install anyway" (sideload)
```

The first launch will:
1. Show splash with Mae Mor portrait + breathing glow
2. Auto-check for updates (silent — won't prompt since we're at latest)
3. Land on Home with daily card + transit + categories

## 🔄 4. Test the auto-update flow

Once you've installed `0.1.0+2`:
1. Bump pubspec to `0.1.1+3` locally:
   ```bash
   sed -i -E 's/^version:.*/version: 0.1.1+3/' pubspec.yaml
   git commit -am "chore: bump for update test" && git push
   git tag v0.1.1+3 -m "test update" && git push --tags
   ```
2. Wait for CI to publish the release
3. On the phone, force-quit the app and re-open
4. UpdateDialog should appear with "✨ มีเวอร์ชันใหม่ — จันทราพยากรณ์ 0.1.1"
5. Tap "อัปเดตตอนนี้" — APK downloads, OS installer pops up, install.
6. App relaunches at 0.1.1.

If the dialog doesn't appear, tap **โปรไฟล์ → ตรวจสอบอัปเดต** to bypass the
6-hour throttle.

## 🪲 5. Known limitations + must-fix-before-real-money

> A code-reviewer agent flagged these in the 2026-05-03 session. The
> CRITICAL items here are **revenue or accuracy bugs**, not security
> auth bypass — the routes ARE behind `auth:sanctum`. Still, fix before
> charging real users.

### CRITICAL (block real money)

- [ ] **`/v1/fortune/draw` does not deduct credits.** Comment promises it,
      code never decrements `FortuneUserCredit`. Free unlimited draws right
      now. Add `decrement('free_credits')` (or `paid_credits`) wrapped in
      a DB transaction with a Cache::lock per user_id to stop concurrency.
- [ ] **`/v1/fortune/read` payment bypass.** `is_paid` boolean is set by
      `/draw` itself based on `priceForSpread === 0`. Tie it to a verified
      `payment_id` from `PaymentController::status` before accepting.
- [ ] **Once credit deduction is wired**, exclude `/draw` from
      `RetryInterceptor` (or add an idempotency_key header) so a
      transient 5xx doesn't double-charge.
- [ ] **`PaymentController::initiate` PromptPay QR is fake** — string
      missing CRC16, merchant ID, and uses the wrong EMV field for amount.
      Banks will reject. Wire to existing `PromptPayService` (used by
      Facebook bot already).
- [ ] **`PaymentController::initiate` wallet balance hardcoded to 480**.
      Read real balance from `FortuneUserCredit::paid_credits` (or
      whichever column tracks wallet) before subtracting.
- [ ] **APK download has no SHA verification.** Anyone who MITM-replaces
      the APK between GitHub CDN and the device will install a malicious
      build. Add `digest` field to release notes (parse out `sha256: ...`)
      and verify the downloaded file before `OpenFilex.open`.

### Accuracy

- [ ] **`/v1/natal/compute` ascendant formula is wrong** — current
      `lst*15 + lat*0.5` is not the Meeus formula. Use proper
      `arctan(cos(LST) / -(sin(LST)*cos(ε) + tan(lat)*sin(ε)))`.
- [ ] **Planet positions are placeholders** — Mercury/Venus/Mars/etc.
      are computed as `sunLon ± constant`. License Swiss Ephemeris and
      replace with real positions before this screen ships.
- [ ] **`AffiliateController::link` referral code is predictable** —
      `substr(md5('juntra-' . userId), 0, 8)`. An attacker can compute
      anyone's referral URL. Generate a random 8-char code, persist to a
      dedicated column with unique index.

### Performance

- [ ] **`AffiliateController::downline` N+1** — recurses 5 levels with
      one query per node. Convert to a single recursive CTE or eager-load.
- [ ] **`AffiliateController::dashboard` caching** — 4 aggregates computed
      every page load. Cache for 5 min keyed by `juntra:aff:dash:{user_id}`.

### Polish

- [ ] **`Profile → ตรวจสอบอัปเดต`** button is decorative — wire to
      `UpdateService.checkForUpdate(isManual: true)` + show result toast
- [ ] **`History` tab** uses placeholder data — wire to
      `fortuneHistoryProvider`
- [ ] **`Reading` screen** shows the same SAMPLE_READING for every user
      — call `FortuneRepository.read(readingId)` after `/draw`
- [ ] **`Natal` chart** uses local Meeus only — call `/v1/natal/compute`
      once the formula is fixed
- [ ] **`Payment` screen** does not actually initiate transactions — wire
      to `/v1/payment/initiate` once the QR/wallet bugs above are fixed
- [ ] **`ChatController::send`** wraps user text in a quoted system
      instruction — vulnerable to prompt injection. Switch to structured
      role/content array at the AI service layer.
- [ ] **56 minor arcana cards** still missing — only 22 majors render today

## 📊 6. Telemetry (optional, post-launch)

The Laravel backend already writes `fortune_readings` rows with
`platform='juntra'`, so analytics that already exist for FB/LINE will
automatically include Juntra traffic — split by the `platform` column.

For client-side events (screen views, button taps, shuffle phase
transitions), add a `lib/core/telemetry/` provider that POSTs to a new
`/v1/events/batch` endpoint. Defer until there are real users.
