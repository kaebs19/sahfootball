// اللاعب كما يراه غيره — ملف عام يُفتح من صفّ في العرش أو عضو في
// مجلس.
//
// يشترك مع ProfileStats في النماذج الفرعية (LeagueStats، RoundForm،
// Badge) عمداً: البطاقة التي ترسم حصيلة دوري في «ملفي» هي نفسها
// التي ترسمها في ملف غيري، وإن اختلف الشكلان ظنّ المستخدم أنهما
// حسابان مختلفان.
import 'profile_stats.dart';

/// نتيجة بحث — ما يكفي للتعرّف على شخص وإضافته إلى مجلس.
class PlayerSummary {
  final String id;
  final String displayName;
  final String? avatarUrl;

  const PlayerSummary({
    required this.id,
    required this.displayName,
    this.avatarUrl,
  });

  factory PlayerSummary.fromJson(Map<String, dynamic> j) => PlayerSummary(
        id: j['id'].toString(),
        displayName: (j['display_name'] ?? 'مشجع') as String,
        avatarUrl: j['avatar_url'] as String?,
      );
}

class PlayerProfile {
  final String id;
  final String displayName;
  final String? avatarUrl;
  final FavoriteTeam? favoriteTeam;

  /// null = لم ينافس بعد (نفس عقد ProfileStats).
  final int? rank;
  final int totalCompetitors;
  final int totalPoints;
  final int predictionsCount;
  final int settledPredictions;
  final int? accuracy;
  final int longestStreak;
  final int currentStreak;
  final List<RoundForm> recentForm;
  final List<LeagueStats> byLeague;
  final List<Badge> badges;

  const PlayerProfile({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.favoriteTeam,
    this.rank,
    required this.totalCompetitors,
    required this.totalPoints,
    required this.predictionsCount,
    required this.settledPredictions,
    this.accuracy,
    required this.longestStreak,
    required this.currentStreak,
    this.recentForm = const [],
    this.byLeague = const [],
    this.badges = const [],
  });

  bool get hasPlayed => settledPredictions > 0;

  factory PlayerProfile.fromJson(Map<String, dynamic> j) {
    final p = j['player'] as Map<String, dynamic>;
    // stats قد تكون null لحساب اختفى بين استعلامين — نعامله كصفر
    // لا كخطأ: الاسم موجود والشاشة تُرسم.
    final s = (j['stats'] as Map<String, dynamic>?) ?? const {};
    return PlayerProfile(
      id: p['id'].toString(),
      displayName: (p['display_name'] ?? 'مشجع') as String,
      avatarUrl: p['avatar_url'] as String?,
      favoriteTeam: p['favorite_team'] != null
          ? FavoriteTeam.fromJson(p['favorite_team'] as Map<String, dynamic>)
          : null,
      rank: (s['rank'] as num?)?.toInt(),
      totalCompetitors: (s['total_competitors'] as num?)?.toInt() ?? 0,
      totalPoints: (s['total_points'] as num?)?.toInt() ?? 0,
      predictionsCount: (s['predictions_count'] as num?)?.toInt() ?? 0,
      settledPredictions: (s['settled_predictions'] as num?)?.toInt() ?? 0,
      accuracy: (s['accuracy'] as num?)?.round(),
      longestStreak: (s['longest_streak'] as num?)?.toInt() ?? 0,
      currentStreak: (s['current_streak'] as num?)?.toInt() ?? 0,
      recentForm: (s['recent_form'] as List? ?? [])
          .map((e) => RoundForm.fromJson(e as Map<String, dynamic>))
          .toList(),
      byLeague: (s['by_league'] as List? ?? [])
          .map((e) => LeagueStats.fromJson(e as Map<String, dynamic>))
          .toList(),
      badges: (j['badges'] as List? ?? [])
          .map((e) => Badge.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
