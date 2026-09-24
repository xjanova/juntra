# จันทราพยากรณ์ (Juntra)

> **แอพดูดวงทาโรต์ AI โดยแม่หมอจันทรา · POWERED BY XMAN STUDIO**

แอพมือถือของเว็บ **จันทรา.online** (`xjanova/juntraweb`) — บัญชี เครดิต ประวัติคำทำนาย และแชทกับแม่หมอ
ชุดเดียวกับเว็บ แอพคุยกับ juntraweb เท่านั้น (AI อยู่ฝั่งเซิร์ฟเวอร์ทั้งหมด)

## ✨ ฟีเจอร์หลัก

- 🎴 **Cinematic Tarot** — สับไพ่ 78 ใบที่เซิร์ฟเวอร์ · กางพัด · เลือกไพ่ · เปิดทีละใบ (3D flip + spotlight + gold rays)
- 📦 **แพ็กเกจไพ่ชุดเดียวกับเว็บ** — รายการ ราคา ภาพประกอบ ข้อห้ามเปิดซ้ำ ช่องวันเกิด มาจากเซิร์ฟเวอร์ (`/v1/tarot/packages`)
- 🔮 **แม่หมออ่านเบื้องหลัง** — ซื้อแล้วตอบทันที หน้าผลถามสถานะจนคำทำนายขึ้น แสดงเป็นการ์ด/ตารางแบบเว็บ
- 💬 **แชทกับแม่หมอ** — คุยฟรี แม่หมอยื่นแพ็กเกจไพ่เป็นการ์ดกดเปิดได้ · คุยต่อจากไพ่ที่เปิดแล้วได้
- 💳 **เครดิต** — ช่อง Google Play: ซื้อแพ็กผ่าน Google Play Billing · ช่อง APK: พร้อมเพย์ + สลิป
- 🌐 **สายงานแนะนำ** — ผังแม่หมอ + ค่าแนะนำ + ลิงก์เชิญ/QR
- 🔐 **บัญชี** — สมัคร/ล็อกอินด้วยอีเมลหรือเบอร์ · เปลี่ยนรหัสผ่าน · ลบบัญชีในแอพ · รายงานเนื้อหา AI
- 🔄 **อัปเดต** — ช่อง Play: In-App Updates ของ Google · ช่อง APK: ตัวอัปเดตในแอพ

## 📦 สองช่องทางแจกจ่าย

| ช่อง | build | ใช้กับ |
|---|---|---|
| `play` (ค่าเริ่มต้น) | `flutter build appbundle --release --flavor play` | Google Play |
| `direct` | `flutter build apk --release --flavor direct` | APK บน GitHub Releases |

รายละเอียด: [`docs/GOOGLE_PLAY.md`](docs/GOOGLE_PLAY.md) (ขั้นตอนใน Play Console ทั้งหมด) ·
[`docs/RELEASING.md`](docs/RELEASING.md) (ออกเวอร์ชัน/keystore)

## 🏗️ Tech Stack

| Layer | Tech |
|---|---|
| UI | Flutter 3.41 · Material 3 · Bai Jamjuree + Noto Sans Thai (Google Fonts) |
| State | Riverpod 2.6 |
| Routing | go_router 14 |
| HTTP | Dio 5.7 + smart_retry |
| Storage | flutter_secure_storage + shared_preferences |
| Billing | in_app_purchase 3.3 (Play Billing Library 8) — เซิร์ฟเวอร์ตรวจทุกการซื้อ |
| Updates | in_app_update (Play) · GitHub release-API + open_filex (direct) |

## 🔧 Development

```bash
flutter pub get
flutter run                     # ช่อง play
flutter run --flavor direct     # ช่อง APK (ทดสอบตัวอัปเดต/พร้อมเพย์)
flutter analyze && flutter test

# ชี้ไปเซิร์ฟเวอร์อื่น (เช่น Laragon ในเครื่อง)
flutter run --dart-define=JUNTRA_API_BASE=http://10.0.2.2:8000/api
```

## 🚀 Releasing

1. Merge PR ที่มี label `release:patch` / `:minor` / `:major`
2. `auto-bump-on-merge.yml` bump pubspec + tag → `release.yml`
3. `release.yml`: analyze + test → APK ช่อง direct ขึ้น GitHub Releases · AAB ช่อง play เป็น artifact
   (+ อัปขึ้น Internal testing แบบ draft ถ้าตั้ง `PLAY_SERVICE_ACCOUNT_JSON`)

## 📁 Structure

```
lib/
├── main.dart                       # entry + system chrome (edge-to-edge)
├── app/                            # MaterialApp.router, go_router, theme
├── core/
│   ├── app_channel.dart            # play | direct (appFlavor)
│   ├── api/                        # ApiClient, endpoints, repositories (config, packages, wallet, chat, …)
│   ├── auth/                       # AuthState, session scope, Thaiprompt link
│   ├── billing/                    # PlayBilling (Google Play Billing) + bootstrap
│   ├── update/                     # PlayUpdateService (play) · UpdateService (direct)
│   └── astronomy/ payments/ sound/
├── shared/                         # widgets (ServiceGate, ReportContentSheet, …), data, format
└── features/                       # splash, home, spreads, shuffle, reading, chat, wallet,
                                    # history, profile, settings (+ delete account), affiliate, …
```

## 🔌 Backend integration

The app talks to **juntraweb** (`xjanova/juntraweb`) at `จันทรา.online` **ONLY**
(punycode `xn--82c4af5bzdj.online` in code). Main endpoints (all under `/api/v1`, Sanctum bearer):

- `app/config` — open services, legal URLs, Play billing switch (public)
- `tarot/packages` · `tarot/cards` · `tarot/deal` — catalog, card art, server-side shuffle
- `history/readings` (`mode: async`) · `history/readings/{id}` · `…/{id}/status` — buy & poll readings
- `chat/conversations*` — แม่หมอ chat (`reading_id` = chat about a reading), offers
- `wallet*` — balance, transactions, PromptPay (direct) · `wallet/google-play*` — Play Billing (play)
- `auth/*` · `auth/password` · `account/delete` · `reports` — account + AI content reports
- `mlm/*` — referral tree / commissions

---
**POWERED BY XMAN STUDIO**
