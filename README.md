# จันทราพยากรณ์ (Juntra)

> **แอพดูดวงทาโรต์ AI โดยแม่หมอจันทรา · POWERED BY XMAN STUDIO**

แอพมือถือสำหรับดูดวงไพ่ทาโรต์, ผังดวงดาวเจ้าชะตา, และคุยกับแม่หมอจันทราด้วย AI — เชื่อมต่อข้อมูลกับระบบ Thaiprompt-Affiliate (Laravel) สำหรับการประมวลผล AI, การชำระเงิน, และระบบสายงาน Affiliate

## ✨ ฟีเจอร์หลัก

- 🎴 **Cinematic Tarot Game** — เลือกไพ่จาก 22 Major Arcana ด้วยอนิเมชั่น 5 phase: สับ → กางพัด → เลือก → เดินทาง → เปิดเผย (3D flip + spotlight + gold rays)
- 🌟 **Real Natal Chart** — ผังดวงดาวคำนวณจากวัน เวลา สถานที่เกิดจริง (Meeus simplified + server fallback ใช้ Swiss Ephemeris)
- 💬 **AI Chat with แม่หมอจันทรา** — คุยปรึกษาความรัก/การงาน/การเงิน ผ่าน AI provider pool ของ Thaiprompt
- 💸 **PromptPay/TrueMoney/Wallet** — ชำระเงินไพ่พรีเมียม
- 🌐 **MLM Affiliate Network** — ระบบสายงาน 5 ระดับ + downline tree + commission tracking
- 🔄 **Auto-Update** — เช็คเวอร์ชันใหม่อัตโนมัติทุก 6 ชม. ดาวน์โหลด APK + ติดตั้งทับได้เลย

## 🏗️ Tech Stack

| Layer | Tech |
|---|---|
| UI | Flutter 3.41 · Material 3 · Bai Jamjuree + Noto Sans Thai (Google Fonts) |
| State | Riverpod 2.6 |
| Routing | go_router 14 |
| HTTP | Dio 5.7 + smart_retry + pretty_dio_logger |
| Storage | flutter_secure_storage + shared_preferences |
| Animations | flutter_animate + Custom AnimationControllers |
| Auto-update | Direct release-API + open_filex |

## 🎨 Design System

ดู `lib/app/theme.dart` — โทนหลักคือ **gold-on-deep-purple-on-near-black** พร้อม mystic accents:

```
gold:           #F0C75E (primary)
purple:         #9B59B6 (secondary)
bg-purple-deep: #1A0F2E (surface)
bg-deepest:     #000000 (canvas)
cyan:           #7FFFD4 (ASC marker)
mint-green:     #00E5A0 (online indicator)
```

## 🔧 Development

```bash
flutter pub get
flutter run

# Release build with custom backend
flutter run --release --dart-define=JUNTRA_API_BASE=https://staging.thaiprompt.online/api
```

## 🚀 Releasing

ดู [`docs/RELEASING.md`](docs/RELEASING.md) — สรุปสั้นๆ:

1. Merge PR ที่มี label `release:patch` (หรือ `:minor` / `:major`)
2. `auto-bump-on-merge.yml` workflow จะ bump pubspec + push tag → trigger `release.yml`
3. Workflow build APK 4 variants + AAB → publish พร้อม changelog
4. ผู้ใช้ได้รับการแจ้งเตือนอัปเดตในแอพภายใน 6 ชม.

> ⚠️ **ก่อน production:** ต้องตั้ง keystore secrets ใน repo Settings → Secrets:
> `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`

## 📁 Structure

```
lib/
├── main.dart                       # entry + system chrome
├── app/
│   ├── app.dart                    # MaterialApp.router + UpdateObserver
│   ├── router.dart                 # go_router 12 routes
│   └── theme.dart                  # JuntraColors, JuntraTheme, fonts
├── core/
│   ├── api/                        # ApiClient (Dio + Sanctum), endpoints
│   ├── update/                     # UpdateService, UpdateInfo, UpdateObserver
│   ├── astronomy/                  # natal_chart.dart (Meeus simplified)
│   └── auth/                       # AuthState (guest/authenticated)
├── shared/
│   ├── data/                       # tarot_deck, fortune_categories, spreads
│   └── widgets/                    # StarryBackground, ChantraLogo, GoldButton, CardBack/Front
└── features/                       # 12 screens
    ├── splash/   home/   spreads/  shuffle/   reading/   payment/
    ├── chat/     history/ profile/ natal/     affiliate/ share/
    └── update/   ← UpdateDialog
```

## 🔌 Backend integration

Calls Thaiprompt-Affiliate Laravel backend at `main.thaiprompt.online`:

- `/v1/login` `/v1/register` `/v1/me` — Sanctum auth
- `/v1/fortune/*` — Tarot reading (uses **shared FortuneAIService pool**)
- `/v1/chat/mae-mor/*` — AI chat
- `/v1/natal/compute` — Server-side natal chart (Swiss Ephemeris)
- `/v1/payment/initiate` — PromptPay/TrueMoney/Card
- `/v1/affiliate/*` — MLM downline data

> Required backend patches live in `backend-patches/juntra/` — apply before first release.

---
**POWERED BY XMAN STUDIO**
