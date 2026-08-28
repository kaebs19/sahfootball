/// تفضيلات الإشعارات كما يحفظها السيرفر.
///
/// ليست هي إذن النظام: الإذن بوابة أولى يمنحها المستخدم لـ iOS مرة
/// واحدة، وهذه بوابة ثانية داخل التطبيق. الفرق يهم — من يريد نتائج
/// المباريات دون تذكيرات لا سبيل له إلا إيقاف الإشعارات كلها من
/// إعدادات الهاتف، وحينها نفقده نهائياً لأن iOS لا يعيد السؤال.
class NotificationPrefs {
  /// تذكير قبل صافرة البداية بمباريات لم يتوقّع لها.
  final bool reminders;

  /// نتيجة توقعاته بعد احتساب النقاط.
  final bool results;

  const NotificationPrefs({required this.reminders, required this.results});

  factory NotificationPrefs.fromJson(Map<String, dynamic> j) =>
      NotificationPrefs(
        reminders: j['reminders'] as bool? ?? true,
        results: j['results'] as bool? ?? true,
      );

  NotificationPrefs copyWith({bool? reminders, bool? results}) =>
      NotificationPrefs(
        reminders: reminders ?? this.reminders,
        results: results ?? this.results,
      );
}
