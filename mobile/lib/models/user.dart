// نماذج البيانات — تحويل JSON السيرفر لكائنات Dart مضبوطة الأنواع.
//
// السيرفر يرسل snake_case (display_name) لأنه يعكس أعمدة القاعدة
// مباشرة، والتحويل لـ camelCase يحصل هنا في الـ fromJson — طبقة
// الترجمة الوحيدة بين العالمين. نفس دور Codable و CodingKeys في Swift.
class User {
  /// UUID نصي — معرّف المستخدم في القاعدة من نوع uuid وليس رقماً
  /// متسلسلاً (يمنع تخمين معرّفات المستخدمين الآخرين بالعد).
  final String id;
  final String? email; // قد يغيب مع دخول Apple (المستخدم أخفى بريده)
  final String? displayName;
  final String? avatarUrl;
  final int? favoriteTeamId;

  const User({
    required this.id,
    this.email,
    this.displayName,
    this.avatarUrl,
    this.favoriteTeamId,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        email: json['email'] as String?,
        displayName: json['display_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        favoriteTeamId: json['favorite_team_id'] as int?,
      );

  /// الاسم المعروض مع تدهور لطيف — نفس COALESCE في استعلامات السيرفر.
  String get nameOrFallback =>
      (displayName?.trim().isNotEmpty ?? false) ? displayName!.trim() : 'مشجع';
}
