// config — إعدادات التطبيق في مكان واحد.
//
// لماذا String.fromEnvironment وليس ملف .env؟ في Flutter القيم تُحقن
// وقت الترجمة عبر --dart-define، فتصبح ثابتة داخل الباينري — لا ملفات
// إعداد تُنسى داخل حزمة التطبيق. نفس فلسفة xcconfig في iOS.
//
// للتشغيل ضد سيرفر آخر:
//   flutter run --dart-define=API_URL=http://192.168.1.10:3000
//
// ملاحظة للمحاكي: localhost داخل محاكي iOS يشير لجهاز الماك نفسه،
// فالقيمة الافتراضية تعمل مباشرة مع السيرفر المحلي. محاكي أندرويد
// يحتاج 10.0.2.2 بدلها.
class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:3000',
  );

  // ── الدخول بحساب جوجل ──────────────────────────────────────────
  //
  // معرّفات عملاء OAuth من Google Cloud Console — معرّفات عامة
  // (تظهر في روابط OAuth لكل مستخدم) لا أسرار، فوضعها هنا آمن.
  //
  // إن بقيت فارغة اختفى زر جوجل من الشاشات ولم ينكسر شيء — نفس
  // فلسفة الموقع (googleAuth.isConfigured يخفي الزر هناك).
  //
  // serverClientId: عميل "Web application" نفسه المستعمل في السيرفر
  // (GOOGLE_CLIENT_ID) — به يُصدر أندرويد توكنه، وبه يتحقق السيرفر.
  // iosClientId: عميل من نوع iOS لحزمة com.sahfootball.app —
  // يُنشأ مرة واحدة من Console ويُلصق هنا وفي Info.plist (CFBundleURLTypes).
  static const googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    // عميل الويب الحي نفسه (GOOGLE_CLIENT_ID في سيرفر الإنتاج) —
    // مأخوذ من رابط تحويل /auth/google العام في الموقع.
    defaultValue:
        '574556220987-e1dnkgmscv20cun4pgfui5bv4amba02i.apps.googleusercontent.com',
  );
  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    // عميل iOS (أُنشئ 2026-09-02 لحزمة com.sahfootball.app).
    // معكوسه مسجّل في Info.plist كمخطط URL للعودة من رحلة جوجل.
    defaultValue:
        '574556220987-l59ck4rrucs4qo7atngb5nrp74phqo12.apps.googleusercontent.com',
  );

  /// روابط الصور (الشعارات من المزود مطلقة، والأفاتار عندنا نسبية مثل
  /// "/uploads/x.png") — هذه تكمّل النسبية بعنوان السيرفر.
  static String absoluteUrl(String url) {
    if (url.startsWith('http')) return url;
    return '$apiBaseUrl$url';
  }
}
