/// URL สื่อจากเซิร์ฟเวอร์ (ภาพห้อง · คลิป idle · เสียงพากย์) ที่โหลดได้จริงบนเครื่อง
///
/// `HttpClient` ของ Dart บน Android ไม่แปลงโดเมนภาษาไทยเป็น punycode ให้ (ดู api_client.dart)
/// ถ้าเซิร์ฟเวอร์ประกอบ URL ด้วย "จันทรา.online" ภาพ/เสียงจะโหลดไม่ขึ้นเงียบ ๆ ทุกเครื่อง
/// จึงเปลี่ยนเป็นโดเมนเดียวกันแบบ ASCII ก่อนส่งให้ตัวโหลด — โดเมนอื่นปล่อยตามเดิม
String mediaUrl(String url) {
  const thai = 'จันทรา.online';
  const ascii = 'xn--82c4af5bzdj.online';
  if (!url.contains(thai)) return url;
  return url
      .replaceFirst('://$thai', '://$ascii')
      .replaceFirst('://www.$thai', '://www.$ascii');
}

/// URL นี้อยู่บนโฮสต์เดียวกับ API ไหม — ส่ง bearer ได้เฉพาะโฮสต์ของเราเท่านั้น
/// (ห้ามแนบ token ไปกับ CDN/โดเมนอื่นที่เซิร์ฟเวอร์อาจชี้ไปในอนาคต)
bool sameHost(String url, String baseUrl) {
  final a = Uri.tryParse(mediaUrl(url));
  final b = Uri.tryParse(baseUrl);
  if (a == null || b == null || a.host.isEmpty) return false;
  return a.scheme == 'https' && a.host.toLowerCase() == b.host.toLowerCase();
}
