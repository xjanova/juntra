# Releasing Juntra

แอพนี้ใช้ **GitHub Releases เป็นช่องทาง distribute APK** (ภายใน) + **Auto-update ในตัวแอพ**

⚠️ **UI separation contract:** ผู้ใช้ปลายทางต้องไม่เห็นข้อความหรือ URL ที่บ่งบอกว่าใช้ GitHub —
ทุก dialog/error message ใน `lib/core/update/` และ `lib/features/update/` จะพูดถึง
"เซิร์ฟเวอร์อัปเดต" เฉยๆ

## 🎯 หลักการ

- `pubspec.yaml` `version: 0.1.0+1` คือ **single source of truth**
- Tag บน GitHub ใช้รูป `v<version>` (เช่น `v0.1.0+1`)
- แอพเช็ค `api.github.com/repos/xjanova/juntra/releases/latest` เมื่อเปิดแอพ
- ถ้า tag > pubspec version → แสดง dialog แจ้งอัปเดต

## 🚀 วิธีออกเวอร์ชันใหม่

### วิธีที่ 1 ⭐ — Auto-bump on PR merge

```
PR merge with label "release:patch":
  ↓ auto-bump-on-merge.yml
  bump pubspec → commit → push tag vX.Y.Z+B
  ↓ release.yml triggered by tag
  flutter build APK (×4 ABI) + AAB → sign → publish Release
  ↓ within 6 hours
  user app pulls latest release → shows update dialog
  ↓ user taps "อัปเดทตอนนี้"
  download APK → open with FileProvider → system installer
```

ติด PR label เพื่อกำหนด bump level:

| Label | ผลลัพธ์ | เมื่อใด |
|---|---|---|
| `release:major` | 0.1.0 → 1.0.0 | Breaking change |
| `release:minor` | 0.1.0 → 0.2.0 | Feature ใหม่ |
| `release:patch` ⭐ | 0.1.0 → 0.1.1 | Bug fix (default) |
| `release:build` | 0.1.0+1 → 0.1.0+2 | Build number only |
| `release:skip` | ไม่ release | docs/refactor only |

### วิธีที่ 2 — GitHub Actions UI

Actions → **Auto-bump version on PR merge** → Run workflow → เลือก level

### วิธีที่ 3 — Manual

```bash
sed -i -E 's/^version:.*/version: 0.2.0+2/' pubspec.yaml
git commit -am "chore: bump to 0.2.0+2"
git tag v0.2.0+2
git push && git push --tags
```

## 🔑 Keystore setup (จำเป็นก่อน production)

ตอนนี้ workflow จะ fall back ไปใช้ debug signing ถ้าไม่มี secrets — **APK ที่ sign ด้วย debug key
ติดตั้งทับ release build ไม่ได้** (signature mismatch)

```bash
# สร้าง keystore (ครั้งเดียวตลอดอายุแอพ — ห้ามทำหาย)
keytool -genkey -v \
  -keystore juntra-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias juntra-upload

# Encode สำหรับ GitHub secret
base64 -w 0 juntra-upload.jks > keystore.base64.txt
```

ไปที่ repo → **Settings** → **Secrets and variables** → **Actions** → ตั้ง 4 ตัว:

| Secret | ค่า |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | เนื้อหา `keystore.base64.txt` |
| `ANDROID_KEYSTORE_PASSWORD` | รหัสผ่าน keystore |
| `ANDROID_KEY_ALIAS` | `juntra-upload` |
| `ANDROID_KEY_PASSWORD` | รหัสผ่าน key (ถ้าเหมือน keystore ใส่เหมือนกัน) |

⚠️ **เก็บ `juntra-upload.jks` + รหัสผ่านไว้ดีๆ** — ถ้าหายจะไม่สามารถออก update ที่ติดตั้งทับ
เวอร์ชันเก่าได้ (ผู้ใช้ต้อง uninstall + reinstall)

## 📦 Artifacts

แต่ละ release จะมี:

| ไฟล์ | สำหรับ |
|---|---|
| `juntra-X.Y.Z-arm64-v8a.apk` ⭐ | Android 64-bit (เครื่องสมัยใหม่) |
| `juntra-X.Y.Z-armeabi-v7a.apk` | Android 32-bit (เครื่องเก่า) |
| `juntra-X.Y.Z-x86_64.apk` | Emulator / x86 device |
| `juntra-X.Y.Z-universal.apk` | ทุก architecture (ไฟล์ใหญ่) — UpdateService ดึงตัวนี้เป็น default |
| `juntra-X.Y.Z.aab` | Google Play Console |

## 🔄 Auto-update Flow ในแอพ

1. แอพเปิด → `UpdateService.checkForUpdate()` (throttle 6 ชม.)
2. GET `releases/latest` (UI ไม่เห็น URL นี้)
3. compare tag vs `package_info_plus.version`
4. ถ้าใหม่กว่า → แสดง `UpdateDialog` พร้อม markdown changelog
5. ผู้ใช้กด:
   - **อัปเดทตอนนี้** → Dio download APK → OpenFilex.open(apkFile) → OS installer
   - **ภายหลัง** → ปิด dialog (ถามใหม่ใน 6 ชม.)
   - **ข้ามเวอร์ชันนี้** → จะไม่ถามอีกจนกว่าจะมีเวอร์ชันใหม่กว่า

ผู้ใช้ check เองได้ที่ **Profile → ตรวจสอบอัปเดต**

## 🐛 Troubleshooting

**Q: workflow บอก "No keystore secrets set"**
A: ชื่อ secrets ต้องตรงเป๊ะ (case-sensitive)

**Q: APK build ผ่านแต่ลง update ทับเครื่องไม่ได้**
A: signature ไม่ตรงกับเวอร์ชันก่อน — ผู้ใช้ต้อง uninstall ก่อน

**Q: แอพไม่แจ้งเตือน update ทั้งที่มี release ใหม่**
A: เช็ค (1) `pubspec.yaml` version < tag, (2) ผู้ใช้ไม่ได้กด "ข้ามเวอร์ชันนี้",
(3) ผ่าน throttle 6 ชม. — กด **Profile → ตรวจสอบอัปเดต** เพื่อบังคับเช็ค
