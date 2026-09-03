// إحصاءات الملف الشخصي.
//
// كلها محسوبة في السيرفر لا في التطبيق، وسبب واحد يحسم ذلك:
// الرتبة. استعلام لوحة الصدارة محدود بخمسين، فمن كان ترتيبه بعدها
// لا يجد نفسه في القائمة أصلاً — ولا يستطيع التطبيق أن يعرف رقمه
// مهما حسب. والباقي (الدقة، السلسلة) تبعها للسيرفر كي لا تتفرق
// طريقة الحساب بين واجهتين.
import 'premium.dart';

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

/// وسام — إنجاز يُكتسب مرة ولا يُفقد.
///
/// غير المكتسب يصل من السيرفر أيضاً ولا يُخفى: رؤية ما لم تنله بعد
/// هي نصف الفائدة. لذلك [requirement] موجود دائماً — تحت الوسام
/// المطفأ يقول كيف يُنال، وتحت المضيء لا يُعرض.
class Badge {
  final String key;
  final String title;
  final String requirement;
  final bool earned;
  final DateTime? earnedAt;

  const Badge({
    required this.key,
    required this.title,
    required this.requirement,
    required this.earned,
    this.earnedAt,
  });

  factory Badge.fromJson(Map<String, dynamic> j) => Badge(
        key: (j['key'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        requirement: (j['requirement'] ?? '') as String,
        earned: j['earned'] == true,
        earnedAt: j['earned_at'] != null
            ? DateTime.parse(j['earned_at'] as String).toLocal()
            : null,
      );
}

/// حصيلة اللاعب في دوري واحد — نقاطه ومركزه ودقّته وتوقعاته فيه.
///
/// [rank] و[accuracy] بنفس عقد ProfileStats: null = لا شيء محتسب
/// في هذا الدوري بعد، لا صفر.
class LeagueStats {
  final int leagueId;
  final String name;
  final String? logoUrl;
  final int points;
  final int predictionsCount;
  final int settledPredictions;
  final int? accuracy;
  final int? rank;
  final int? competitors;
  final bool followed;

  const LeagueStats({
    required this.leagueId,
    required this.name,
    this.logoUrl,
    required this.points,
    required this.predictionsCount,
    required this.settledPredictions,
    this.accuracy,
    this.rank,
    this.competitors,
    required this.followed,
  });

  bool get hasPlayed => settledPredictions > 0;

  factory LeagueStats.fromJson(Map<String, dynamic> j) => LeagueStats(
        leagueId: (j['league_id'] as num).toInt(),
        name: (j['name'] ?? '') as String,
        logoUrl: j['logo_url'] as String?,
        points: (j['points'] as num?)?.toInt() ?? 0,
        predictionsCount: (j['predictions_count'] as num?)?.toInt() ?? 0,
        settledPredictions: (j['settled_predictions'] as num?)?.toInt() ?? 0,
        accuracy: (j['accuracy'] as num?)?.round(),
        rank: (j['rank'] as num?)?.toInt(),
        competitors: (j['competitors'] as num?)?.toInt(),
        followed: j['followed'] == true,
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
  final List<Badge> badges;

  /// الحصيلة لكل دوري يتابعه أو له فيه أثر — مرتبة بالنقاط.
  final List<LeagueStats> byLeague;

  /// درع السلسلة — يأتي من نفس حساب السلسلة في السيرفر، فلا يمكن
  /// أن يقول أحدهما شيئاً ويقول الآخر غيره.
  final ShieldState shield;

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
    this.badges = const [],
    this.byLeague = const [],
    this.shield = const ShieldState(),
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
        badges: (j['badges'] as List? ?? [])
            .map((e) => Badge.fromJson(e as Map<String, dynamic>))
            .toList(),
        byLeague: (j['by_league'] as List? ?? [])
            .map((e) => LeagueStats.fromJson(e as Map<String, dynamic>))
            .toList(),
        shield: ShieldState.fromJson(
            (j['shield'] as Map<String, dynamic>?) ?? const {}),
      );
}
