class Fixture {
  final int id;
  final int leagueId;
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

  // ── تفاصيل شاشة المباراة — كلها اختيارية ──────────────────────
  //
  // تصل من /api/fixtures/:id/match وحده؛ قائمة المباريات لا ترسلها
  // فتبقى null هناك. في النموذج نفسه لا في نموذج ثانٍ: المباراة
  // واحدة، والشاشة التي تفتحها من القائمة تبدأ بما تعرفه القائمة
  // ثم تكمل — ونموذجان لنفس الشيء يعني تحويلاً بينهما في كل مسار.

  /// طور المزوّد الخام: 1H / HT / 2H / ET / BT / P / FT / AET / PEN…
  /// null قبل أول مزامنة بعد إضافته، أو في قوائم لا ترسله.
  final String? phase;
  final int? htHome;
  final int? htAway;
  final int? penHome;
  final int? penAway;
  final String? venueName;
  final String? venueCity;
  final String? referee;

  const Fixture({
    required this.id,
    required this.leagueId,
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
    this.phase,
    this.htHome,
    this.htAway,
    this.penHome,
    this.penAway,
    this.venueName,
    this.venueCity,
    this.referee,
  });

  factory Fixture.fromJson(Map<String, dynamic> json) => Fixture(
        id: json['id'] as int,
        leagueId: (json['league_id'] as num?)?.toInt() ?? 0,
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
        phase: json['phase'] as String?,
        htHome: json['ht_home'] as int?,
        htAway: json['ht_away'] as int?,
        penHome: json['pen_home'] as int?,
        penAway: json['pen_away'] as int?,
        venueName: json['venue_name'] as String?,
        venueCity: json['venue_city'] as String?,
        referee: json['referee'] as String?,
      );

  bool get isLive => status == 'live';
  bool get isFinished => status == 'finished';

  /// هل للمباراة صفحة تُفتح؟ ما انطلق أو انتهى له أحداث وإحصاءات؛
  /// أما ما لم يبدأ فله التشكيلة والمواجهات السابقة — وهذا يكفي.
  /// المؤجلة والملغاة وحدهما لا شيء فيهما يُقرأ.
  bool get hasMatchPage => status != 'postponed' && status != 'cancelled';

  /// هل ما زال التوقع مفتوحاً؟ نفس شرط السيرفر حرفياً (الحالة والوقت
  /// معاً) — لكن السيرفر يبقى الحكم الأخير: هذا للعرض فقط، وشرط
  /// السيرفر هو ما يمنع الغش فعلياً. لا تثق أبداً بمنطق العميل وحده.
  bool get isOpenForPrediction =>
      status == 'scheduled' && kickoffAt.isAfter(DateTime.now());
}
