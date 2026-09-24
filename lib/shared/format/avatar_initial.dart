/// ตัวอักษรบนวงกลมอวตาร์
///
/// ชื่อไทยที่ขึ้นต้นด้วยสระหน้า (เ แ โ ใ ไ) ถ้าตัดตัวแรกตรง ๆ จะได้แค่สระลอย
/// ("แขก" → "แ") จึงข้ามสระหน้าไปใช้พยัญชนะตัวแรก ("ข") · ตัวอังกฤษเป็นตัวพิมพ์ใหญ่
/// · ใช้ runes จึงไม่ตัดอีโมจิครึ่งตัว
String avatarInitial(String name) {
  for (final r in name.trim().runes) {
    if (r >= 0x0E40 && r <= 0x0E44) continue; // สระหน้า
    return String.fromCharCode(r).toUpperCase();
  }
  return '?';
}
