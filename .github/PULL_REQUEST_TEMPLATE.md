## Summary
<!-- 1-3 bullets of what changed -->

## Release level
ติด label `release:major` / `release:minor` / `release:patch` / `release:build` / `release:skip` กับ PR นี้
- `release:major` — Breaking change (0.1.0 → 1.0.0)
- `release:minor` — Feature ใหม่ (0.1.0 → 0.2.0)
- `release:patch` ⭐ Bug fix (default ถ้าไม่ติด)
- `release:build` — Build number only
- `release:skip` — ไม่ release (docs/refactor)

## Test plan
- [ ] `flutter analyze` ผ่าน
- [ ] เปิด Splash + เข้า Home ได้
- [ ] Cinematic shuffle game เล่นจบ phase ทั้งหมด
- [ ] Auto-update dialog แสดงผลถูกต้อง (test กับ tag ใหม่กว่า)
