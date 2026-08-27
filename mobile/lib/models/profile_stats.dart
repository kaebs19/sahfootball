// إحصاءات الملف الشخصي.
//
// كلها محسوبة في السيرفر لا في التطبيق، وسبب واحد يحسم ذلك:
// الرتبة. استعلام لوحة الصدارة محدود بخمسين، فمن كان ترتيبه بعدها
// لا يجد نفسه في القائمة أصلاً — ولا يستطيع التطبيق أن يعرف رقمه
// مهما حسب. والباقي (الدقة، السلسلة) تبعها للسيرفر كي لا تتفرق
// طريقة الحساب بين واجهتين.
class RoundForm {
  final String round;
  final int season;
  final int accuracy; // نسبة مئوية
  final int settled;

  const RoundForm({
    required this.round,
    required this.season,
    required this.accuracy,
    required this.settled,
  });

  factory RoundForm.fromJson(Map<String, dynamic> j) => RoundForm(
        round: (j['round'] ?? '') as String,
        season: (j['season'] as num?)?.toInt() ?? 0,
        accuracy: (j['accuracy'] as num?)?.round() ?? 0,
        settled: (j['settled'] as num?)?.toInt() ?? 0,
      );

  /// رقم الجولة، مثل "12" من "Regular Season - 12".
  String get roundNumber {
    final m = RegExp(r'(\d+)\s*$').firstMatch(round);
    return m?.group(1) ?? round;
  }

  /// "ج12" — التسمية الكاملة لا تتسع تحت عمود بعرض أربعين بكسلاً.
  String get shortLabel => 'ج$roundNumber';
}

class PointsBucket {
  final int points;
  final int count;
  const PointsBucket({required this.points, required this.count});

  factory PointsBucket.fromJson(Map<String, dynamic> j) => PointsBucket(
        points: (j['points'] as num).toInt(),
        count: (j['count'] as num).toInt(),
      );
}

class FavoriteTeam {
  final int id;
  final String name;
  final String? logoUrl;
  const FavoriteTeam({required this.id, required this.name, this.logoUrl});

  factory FavoriteTeam.fromJson(Map<String, dynamic> j) => FavoriteTeam(
        id: (j['id'] as num).toInt(),
        name: (j['name'] ?? '') as String,
        logoUrl: j['logo_url'] as String?,
      );
}

class ProfileStats {
  /// null = لم يشارك بعد. ليست صفراً ولا آخر مركز: من لم يلعب ليس
  /// خاسراً، والفرق بينهما يجب أن يظهر في الشاشة لا أن يُطمس.
  final int? rank;
  final int totalCompetitors;

  final int totalPoints;
  final int predictionsCount;
  final int settledPredictions;

  /// null = لا توقعات محتسبة بعد. صفر بالمئة يعني "جرّبت وأخطأت"،
  /// والغياب يعني "لم يُحتسب شيء" — رسالتان مختلفتان تماماً.
  final int? accuracy;

  final int longestStreak;
  final int currentStreak;
  final List<PointsBucket> pointsDistribution;
  final List<RoundForm> recentForm;
  final FavoriteTeam? favoriteTeam;

  const ProfileStats({
    this.rank,
    required this.totalCompetitors,
    required this.totalPoints,
    required this.predictionsCount,
    required this.settledPredictions,
    this.accuracy,
    required this.longestStreak,
    required this.currentStreak,
    required this.pointsDistribution,
    required this.recentForm,
    this.favoriteTeam,
  });

  bool get hasPlayed => settledPredictions > 0;

  factory ProfileStats.fromJson(Map<String, dynamic> j) => ProfileStats(
        rank: (j['rank'] as num?)?.toInt(),
        totalCompetitors: (j['total_competitors'] as num?)?.toInt() ?? 0,
        totalPoints: (j['total_points'] as num?)?.toInt() ?? 0,
        predictionsCount: (j['predictions_count'] as num?)?.toInt() ?? 0,
        settledPredictions: (j['settled_predictions'] as num?)?.toInt() ?? 0,
        accuracy: (j['accuracy'] as num?)?.round(),
        longestStreak: (j['longest_streak'] as num?)?.toInt() ?? 0,
        currentStreak: (j['current_streak'] as num?)?.toInt() ?? 0,
        pointsDistribution: (j['points_distribution'] as List? ?? [])
            .map((e) => PointsBucket.fromJson(e as Map<String, dynamic>))
            .toList(),
        recentForm: (j['recent_form'] as List? ?? [])
            .map((e) => RoundForm.fromJson(e as Map<String, dynamic>))
            .toList(),
        favoriteTeam: j['favorite_team'] != null
            ? FavoriteTeam.fromJson(j['favorite_team'] as Map<String, dynamic>)
            : null,
      );
}
