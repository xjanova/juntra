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

## 🪲 5. Known limitations (good first issues)

- [ ] `Profile → ตรวจสอบอัปเดต` button currently does nothing — wire to
      `UpdateService.checkForUpdate(isManual: true)` + show toast
- [ ] `History` tab uses placeholder data — wire to `fortuneHistoryProvider`
- [ ] `Reading` shows the same SAMPLE_READING for every user — call
      `FortuneRepository.read(readingId)` after `/draw`
- [ ] `Natal` chart uses local Meeus only — call `/v1/natal/compute` for
      Swiss Eph accuracy
- [ ] `Payment` screen does not actually initiate transactions — wire to
      `/v1/payment/initiate` (controller already returns mock payload)
- [ ] 56 minor arcana cards still missing — only 22 majors render today

## 📊 6. Telemetry (optional, post-launch)

The Laravel backend already writes `fortune_readings` rows with
`platform='juntra'`, so analytics that already exist for FB/LINE will
automatically include Juntra traffic — split by the `platform` column.

For client-side events (screen views, button taps, shuffle phase
transitions), add a `lib/core/telemetry/` provider that POSTs to a new
`/v1/events/batch` endpoint. Defer until there are real users.
