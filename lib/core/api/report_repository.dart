import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'endpoints.dart';

/// รายงานเนื้อหาที่ AI (แม่หมอ) สร้าง — คำทำนายหรือข้อความในแชท
///
/// Google Play (AI-Generated Content policy) บังคับให้แอพที่สร้างเนื้อหาด้วย AI มีปุ่มรายงาน
/// ในแอพโดยไม่ต้องออกจากแอพ — ส่งถึงแอดมินทาง Telegram + คิวในหลังบ้าน
enum ReportSubject { reading, chatMessage }

enum ReportReason {
  offensive('ไม่เหมาะสม / หยาบคาย'),
  harmful('อันตราย / ชี้นำให้ทำสิ่งเสี่ยง'),
  inaccurate('ผิดพลาด / ไม่ตรงกับไพ่ที่เปิด'),
  other('อื่น ๆ');

  const ReportReason(this.label);
  final String label;
}

class ReportRepository {
  ReportRepository(this._api);
  final ApiClient _api;

  /// คืนข้อความขอบคุณจากเซิร์ฟเวอร์ · Throws [ApiException] (404 ไม่ใช่ของเรา ฯลฯ)
  Future<String> report({
    required ReportSubject subject,
    required int subjectId,
    required ReportReason reason,
    String? note,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(Api.reports, data: {
      'subject_type': subject == ReportSubject.reading ? 'reading' : 'chat_message',
      'subject_id': subjectId,
      'reason': reason.name,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
    final data = res['data'];
    return (data is Map ? data['message']?.toString() : null) ??
        'ขอบคุณที่แจ้งค่ะ ทีมงานจะตรวจสอบโดยเร็ว';
  }
}

final reportRepositoryProvider = FutureProvider<ReportRepository>((ref) async {
  final api = await ref.watch(apiClientProvider.future);
  return ReportRepository(api);
});
