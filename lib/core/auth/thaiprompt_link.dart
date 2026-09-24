import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../api/api_client.dart';
import '../api/api_exceptions.dart';
import '../api/endpoints.dart';

/// เปิดหน้าเชื่อมบัญชี Thaiprompt (SSO) บนเว็บ **ในนามบัญชีที่ล็อกอินในแอพอยู่**
///
/// ขอรหัส handoff อายุสั้น (ใช้ครั้งเดียว 120 วิ) แล้วส่งไปกับ URL แทน bearer — ของเดิมในหน้า
/// ตั้งค่าเปิด `/auth/thaiprompt/redirect` ตรง ๆ ซึ่งผูก Thaiprompt กับบัญชีที่ **เบราว์เซอร์**
/// ล็อกอินอยู่ (อาจเป็นคนละบัญชีกับในแอพ หรือยังไม่ได้ล็อกอินเลย)
///
/// คืน true เมื่อเปิดเบราว์เซอร์สำเร็จ — ผู้เรียกควรรีเฟรชสถานะเมื่อแอพกลับมา
Future<bool> launchThaipromptLink(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  void toast(String t) => messenger?.showSnackBar(SnackBar(
        content: Text(t),
        backgroundColor: JuntraColors.bgPurpleDeep,
        behavior: SnackBarBehavior.floating,
      ));

  Uri? uri;
  try {
    final api = await ref.read(apiClientProvider.future);
    final res = await api.post<Map<String, dynamic>>(Api.authHandoff);
    final data = res['data'];
    final code = (data is Map ? data['code'] : null)?.toString();
    if (code != null && code.isNotEmpty) {
      uri = Uri.https('xn--82c4af5bzdj.online', '/auth/thaiprompt/mobile-start', {'code': code});
    }
  } on ApiException {
    uri = null;
  } catch (_) {
    uri = null;
  }
  if (uri == null) {
    toast('เซสชันไม่พร้อม — กรุณาเข้าสู่ระบบใหม่แล้วลองอีกครั้ง');
    return false;
  }
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) toast('เปิดเบราว์เซอร์ไม่ได้ — กรุณาลองอีกครั้ง');
  return ok;
}
