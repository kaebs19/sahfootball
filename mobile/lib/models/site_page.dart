/// صفحة نصية من الموقع (سياسة الخصوصية، الشروط، عن التطبيق).
///
/// النص يعيش في قاعدة السيرفر ويحرّره الأدمن من اللوحة، لا داخل
/// التطبيق. السبب عملي وقانوني معاً: تعديل سطر في سياسة الخصوصية
/// يجب ألا ينتظر مراجعة App Store أسبوعاً — والمراجعة نفسها تفتح
/// رابط السياسة وتتحقق أنه يعمل.
///
/// نستعمل [body] الخام (Markdown) لا body_html: عرض HTML يحتاج
/// WebView كاملاً بكل ثقله وفجواته الأمنية، بينما نصوص قانونية من
/// عناوين وفقرات وقوائم يرسمها عارض بسيط بخطوط التطبيق نفسها.
class SitePage {
  final String slug;
  final String title;
  final String body;
  final DateTime? updatedAt;

  const SitePage({
    required this.slug,
    required this.title,
    required this.body,
    this.updatedAt,
  });

  factory SitePage.fromJson(Map<String, dynamic> j) => SitePage(
        slug: (j['slug'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        body: (j['body'] ?? '') as String,
        updatedAt: j['updated_at'] != null
            ? DateTime.parse(j['updated_at'] as String).toLocal()
            : null,
      );
}
