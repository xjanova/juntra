import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'app_config_repository.dart';
import 'endpoints.dart';

/// รีวิวที่ลูกค้ายินยอมให้แสดง (`GET /v1/testimonials`) — ชุดเดียวกับ "เสียงจากผู้ที่เคยเปิดดวง"
/// บนหน้าแรกของเว็บ
///
/// เว็บมีรีวิวตัวอย่างสำรองไว้เมื่อยังไม่มีของจริง แอพไม่เอามาด้วย: ไม่มีรีวิวจริง = ไม่แสดงส่วนนี้
/// ดีกว่าโชว์ชื่อคนที่ไม่มีตัวตน
@immutable
class Testimonial {
  const Testimonial({
    required this.name,
    required this.message,
    this.service,
    this.rating = 5,
  });

  final String name;
  final String message;
  final String? service;
  final int rating;

  static Testimonial? fromJson(Object? j) {
    if (j is! Map) return null;
    final message = (j['message'] ?? '').toString().trim();
    final name = (j['name'] ?? '').toString().trim();
    if (message.isEmpty || name.isEmpty) return null;
    final rating = num.tryParse('${j['rating']}')?.toInt() ?? 5;
    final service = (j['service'] ?? '').toString().trim();
    return Testimonial(
      name: name,
      message: message,
      service: service.isEmpty ? null : service,
      rating: rating.clamp(1, 5),
    );
  }
}

final testimonialsProvider = FutureProvider<List<Testimonial>>((ref) async {
  if (!ref.watch(appConfigValueProvider).has('testimonials')) return const [];
  final api = await ref.watch(apiClientProvider.future);
  try {
    final res = await api.get<Map<String, dynamic>>(
      Api.testimonials,
      query: {'limit': 3},
    );
    final data = res['data'];
    if (data is! List) return const [];
    return [
      for (final t in data) ?Testimonial.fromJson(t),
    ];
  } catch (e) {
    if (kDebugMode) debugPrint('[Testimonials] load failed: $e');
    return const [];
  }
});
