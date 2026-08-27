class Fixture {
  final int id;
  final String? round;
  final DateTime kickoffAt; // محلي — التحويل من UTC يحصل في fromJson
  final String status;
  final int? goalsHome;
  final int? goalsAway;
  final int homeTeamId;
  final String homeTeamName;
  final String? homeTeamLogo;
  final int awayTeamId;
  final String awayTeamName;
  final String? awayTeamLogo;

  const Fixture({
    required this.id,
    this.round,
    required this.kickoffAt,
    required this.status,
    this.goalsHome,
    this.goalsAway,
    required this.homeTeamId,
    required this.homeTeamName,
    this.homeTeamLogo,
    required this.awayTeamId,
    required this.awayTeamName,
    this.awayTeamLogo,
  });

  factory Fixture.fromJson(Map<String, dynamic> json) => Fixture(
        id: json['id'] as int,
        round: json['round'] as String?,
        // السيرفر يخزن kickoff_at بتوقيت UTC ويرسله بلاحقة Z؛
        // toLocal() تعرضه بتوقيت جهاز المستخدم أياً كان.
        kickoffAt: DateTime.parse(json['kickoff_at'] as String).toLocal(),
        status: json['status'] as String,
        goalsHome: json['goals_home'] as int?,
        goalsAway: json['goals_away'] as int?,
        homeTeamId: json['home_team_id'] as int,
        homeTeamName: json['home_team_name'] as String,
        homeTeamLogo: json['home_team_logo'] as String?,
        awayTeamId: json['away_team_id'] as int,
        awayTeamName: json['away_team_name'] as String,
        awayTeamLogo: json['away_team_logo'] as String?,
      );

  /// هل ما زال التوقع مفتوحاً؟ نفس شرط السيرفر حرفياً (الحالة والوقت
  /// معاً) — لكن السيرفر يبقى الحكم الأخير: هذا للعرض فقط، وشرط
  /// السيرفر هو ما يمنع الغش فعلياً. لا تثق أبداً بمنطق العميل وحده.
  bool get isOpenForPrediction =>
      status == 'scheduled' && kickoffAt.isAfter(DateTime.now());
}
