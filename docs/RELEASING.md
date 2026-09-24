# Releasing Juntra

แอพ build ได้ **2 ช่องทาง** จากโค้ดชุดเดียวกัน (Gradle flavor — `android/app/build.gradle.kts`)

| ช่อง | ไฟล์ | ผู้ใช้ได้อัปเดตจาก | เติมเครดิต |
|---|---|---|---|
| `play` | App Bundle `.aab` | Google Play (+ In-App Updates) | Google Play Billing |
| `direct` | `juntra-X.Y.Z-universal.apk` บน GitHub Releases | ตัวอัปเดตในแอพ | พร้อมเพย์ + สลิป |

ขั้นตอนตั้งค่า Google Play ทั้งหมด (Play Console, App Signing, แพ็กเครดิต, service account,
Data safety, บัญชีให้ผู้ตรวจ) อยู่ที่ [`GOOGLE_PLAY.md`](GOOGLE_PLAY.md)

⚠️ **UI separation contract (ช่อง direct):** ผู้ใช้ต้องไม่เห็นข้อความหรือ URL ที่บ่งบอกว่าใช้ GitHub —
ทุก dialog/error ใน `lib/core/update/` และ `lib/features/update/` พูดถึง "เซิร์ฟเวอร์อัปเดต" เท่านั้น

## 🎯 หลักการ

- `pubspec.yaml` `version: X.Y.Z+B` คือ **single source of truth** — ทั้งสองช่องได้ versionCode = B เท่ากัน
- **B ต้องเพิ่มขึ้นเสมอ และ ≥ 5000** — APK แบบแยก ABI ที่เคยปล่อยก่อนหน้า (≤ 0.4.0) ได้ versionCode
  1000×abi+B (arm64 = 2017, x86_64 = 4017) เลขต่ำกว่านั้นติดตั้งทับเครื่องพวกนั้นไม่ได้ ทั้งจาก Play และตัวอัปเดต
  ตั้งแต่ 0.5.0 เลิกทำ APK แยก ABI แล้ว (เหลือ universal ตัวเดียว)
- Tag บน GitHub ใช้รูป `v<version>` (เช่น `v0.5.0+5000`)
- ช่อง direct เช็ค `api.github.com/repos/xjanova/juntra/releases/latest` ตอนเปิดแอพ (ทุก 6 ชม.)
- ช่อง play ถาม Play In-App Updates API (ทุก 12 ชม.) — **ห้ามเรียก GitHub/ดาวน์โหลด APK ในช่อง play เด็ดขาด**

## 🚀 ออกเวอร์ชันใหม่

### วิธีที่ 1 ⭐ — Auto-bump on PR merge

```
PR merge with label "release:minor"
  ↓ auto-bump-on-merge.yml   bump pubspec → commit → tag vX.Y.Z+B → dispatch release.yml
  ↓ release.yml
  analyze + test (ต้องผ่าน) · ต้องมี keystore secrets (ไม่มี = ล้ม ไม่ยอมเซ็นด้วย debug key)
  flutter build apk --flavor direct        → GitHub Release (ผู้ใช้ APK ได้อัปเดต)
  flutter build appbundle --flavor play    → artifact "play-bundle-<ver>" (+ Internal testing แบบ draft ถ้าตั้ง secret)
  ↓
  Play Console: ตรวจ draft → Roll out → promote ไป Closed/Production
```

| Label | ผลลัพธ์ | เมื่อใด |
|---|---|---|
| `release:major` | 0.5.0 → 1.0.0 | Breaking change |
| `release:minor` | 0.5.0 → 0.6.0 | Feature ใหม่ |
| `release:patch` ⭐ | 0.5.0 → 0.5.1 | Bug fix (default) |
| `release:build` | 0.5.0+5000 → 0.5.0+5001 | Build number only |
| `release:skip` | ไม่ release | docs/refactor only |

### วิธีที่ 2 — GitHub Actions UI

Actions → **Auto-bump version on PR merge** → Run workflow → เลือก level

### วิธีที่ 3 — Build ในเครื่อง

```bash
# Google Play
flutter build appbundle --release --flavor play
# → build/app/outputs/bundle/playRelease/app-play-release.aab

# APK ช่อง direct
flutter build apk --release --flavor direct
# → build/app/outputs/flutter-apk/app-direct-release.apk
```

`flutter run` เฉย ๆ = ช่อง play (`default-flavor: play` ใน pubspec) — ทดสอบตัวอัปเดต APK ใช้ `flutter run --flavor direct`

## 🔑 Keystore

ทุก release เซ็นด้วย keystore เดียวกัน `android/upload-keystore.jks` (alias `juntra-upload`,
cert SHA-256 `C7:1B:…:9E:DB`) — GitHub secrets:

| Secret | ค่า |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w 0 upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | รหัสผ่าน keystore |
| `ANDROID_KEY_ALIAS` | `juntra-upload` |
| `ANDROID_KEY_PASSWORD` | รหัสผ่าน key (PKCS12 = เท่ากับ keystore) |
| `PLAY_SERVICE_ACCOUNT_JSON` *(ไม่บังคับ)* | JSON ของ service account ที่อัปโหลดขึ้น testing track ได้ |

⚠️ keystore หาย = ออกอัปเดตทับเวอร์ชันเก่าไม่ได้ (ผู้ใช้ต้องถอนแอพ) — ใน Play ให้ใช้
**Play App Signing แบบอัปโหลดคีย์เดิม** (ดู GOOGLE_PLAY.md ข้อ 1) Google จะเก็บคีย์สำรองให้
เปลี่ยนรหัสผ่าน keystore ได้ด้วย `keytool -storepasswd` โดยคู่กุญแจไม่เปลี่ยน (อัปเดตยังติดตั้งทับได้)

## 🔄 ตัวอัปเดตในแอพ (ช่อง direct)

1. แอพเปิด → `UpdateService.checkForUpdate()` (throttle 6 ชม.)
2. GET `releases/latest` (UI ไม่เห็น URL นี้) → เลือกไฟล์ `*universal.apk`
3. เทียบ version+build กับ `package_info_plus`
4. ใหม่กว่า → `UpdateDialog` (บันทึกรุ่นถูกกรองลิงก์ทิ้ง) → ดาวน์โหลด → ตรวจ SHA-256 → ตัวติดตั้งของระบบ

## 🔄 อัปเดตในแอพ Play (ช่อง play)

`PlayUpdateService` ถาม Play ว่ามีรุ่นใหม่ไหม → `PlayUpdateSheet` → Play พาอัปเดตแบบเต็มจอ
(Play ไม่พร้อม เช่น build ของนักพัฒนา → เปิดหน้าแอพใน Play Store แทน)

## 🐛 Troubleshooting

**Q: workflow ล้มที่ "Require the release keystore"** — ยังไม่ได้ตั้ง `ANDROID_KEYSTORE_*` secrets (ชื่อต้องตรงเป๊ะ)

**Q: ติดตั้งทับไม่ได้ (App not installed)** — ลายเซ็นไม่ตรง (คนละคีย์) หรือ versionCode ต่ำกว่าที่ติดตั้งอยู่

**Q: Play Console ไม่รับ AAB: "Version code already used"** — build number ต้องเพิ่มขึ้น (`release:build`)

**Q: แอพ APK ไม่แจ้งอัปเดต** — เช็ค (1) build ใน tag > ที่ติดตั้ง (2) ไม่ได้กด "ข้ามเวอร์ชันนี้"
(3) ผ่าน throttle 6 ชม. — กด **ตั้งค่า → ตรวจสอบอัปเดต** เพื่อบังคับเช็ค
