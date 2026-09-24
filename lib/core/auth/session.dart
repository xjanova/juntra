import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_state.dart';

/// id ของผู้ใช้ที่ล็อกอินอยู่ (null = แขก / ยังไม่รู้ / ออฟไลน์)
///
/// 🔴 provider ข้อมูลส่วนตัวทุกตัว (ประวัติ · คำทำนาย · แชท · วอลเลต · สายงาน) ต้อง
/// `ref.watch(sessionUserIdProvider)` — ของเดิมแคชข้อมูลไว้ตลอดอายุแอพ ออกจากระบบแล้ว
/// อีกคนล็อกอินบนเครื่องเดียวกันยังเห็นประวัติและคำทำนายของคนก่อน จนกว่าจะมีอะไรรีเฟรช
///
/// ค่าเปลี่ยนเฉพาะตอนสลับคน (ล็อกอิน/ออก/ลบบัญชี) — refresh ยอดเครดิตให้ id เดิม
/// provider ที่ watch อยู่จึงไม่ถูกโหลดใหม่โดยไม่จำเป็น
final sessionUserIdProvider = Provider<String?>((ref) {
  final s = ref.watch(authControllerProvider);
  return s is AuthAuthenticated ? s.userId : null;
});
