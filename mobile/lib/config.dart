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

  /// روابط الصور (الشعارات من المزود مطلقة، والأفاتار عندنا نسبية مثل
  /// "/uploads/x.png") — هذه تكمّل النسبية بعنوان السيرفر.
  static String absoluteUrl(String url) {
    if (url.startsWith('http')) return url;
    return '$apiBaseUrl$url';
  }
}
