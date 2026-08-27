/// توقع من GET /api/predictions/mine — يأتي مضموماً مع معلومات مباراته
/// (السيرفر يعمل JOIN) كي تُعرض القائمة بلا طلبات إضافية.
class Prediction {
  /// نصي لا رقمي: العمود bigint، ومكتبة pg في السيرفر ترسل bigint
  /// كنص ("1") لأنه قد يتجاوز أرقام JavaScript الآمنة. لا نحسب به
  /// شيئاً — مجرد هوية — فنبقيه نصاً كما وصل بدل تحويل هش.
  final String id;
  final int fixtureId;
  final int predHome;
  final int predAway;
  final int? points; // null = لم يُحتسب بعد (المباراة لم تنته)
  final DateTime? settledAt;
  final DateTime kickoffAt;
  final String status;
  final int? goalsHome;
  final int? goalsAway;
  final String? round;
  final String homeTeamName;
  final String awayTeamName;

  const Prediction({
    required this.id,
    required this.fixtureId,
    required this.predHome,
    required this.predAway,
    this.points,
    this.settledAt,
    required this.kickoffAt,
    required this.status,
    this.goalsHome,
    this.goalsAway,
    this.round,
    required this.homeTeamName,
    required this.awayTeamName,
  });

  factory Prediction.fromJson(Map<String, dynamic> json) => Prediction(
        id: json['id'].toString(),
        fixtureId: json['fixture_id'] as int,
        predHome: json['pred_home'] as int,
        predAway: json['pred_away'] as int,
        points: json['points'] as int?,
        settledAt: json['settled_at'] != null
            ? DateTime.parse(json['settled_at'] as String).toLocal()
            : null,
        kickoffAt: DateTime.parse(json['kickoff_at'] as String).toLocal(),
        status: json['status'] as String,
        goalsHome: json['goals_home'] as int?,
        goalsAway: json['goals_away'] as int?,
        round: json['round'] as String?,
        homeTeamName: json['home_team_name'] as String,
        awayTeamName: json['away_team_name'] as String,
      );

  bool get isSettled => settledAt != null;
}
