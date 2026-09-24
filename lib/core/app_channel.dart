import 'package:flutter/services.dart' show appFlavor;

/// ช่องทางที่แอพตัวนี้ถูกแจกจ่าย — ตัดสินจาก Gradle flavor ตอน build
/// (`android/app/build.gradle.kts` → productFlavors)
///
/// - [play]   — Google Play: อัปเดตผ่าน Play เท่านั้น และเติมเครดิตผ่าน
///   Google Play Billing (นโยบาย Payments ของ Play ห้ามชี้ไปจ่ายช่องทางอื่น)
/// - [direct] — APK บน GitHub Releases: มีตัวอัปเดตในแอพ + เติมเงินพร้อมเพย์
enum AppChannel { play, direct }

/// ไม่รู้ flavor (เช่นตอนรันเทสต์) = ถือเป็น Play ไว้ก่อน เพราะเป็นโหมดที่
/// เข้มกว่า — ถ้าพลาดไปทางนี้ ผลคือซ่อนตัวอัปเดต/พร้อมเพย์ ไม่ใช่เผลอโชว์
/// ของต้องห้ามในแอพบน Play
AppChannel get appChannel =>
    appFlavor == 'direct' ? AppChannel.direct : AppChannel.play;

bool get isPlayChannel => appChannel == AppChannel.play;

/// หน้าแอพบน Google Play — ใช้เป็นทางสำรองเมื่อ in-app update ใช้ไม่ได้
const kPlayStoreListingUrl =
    'https://play.google.com/store/apps/details?id=com.xjanova.juntra';
