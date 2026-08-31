/// مباراة في شاشة توقّع الجولة — من GET /api/round.
class RoundFixture {
  final int id;
  final DateTime kickoffAt;
  final bool open;

  final String homeName;
  final String homeLogo;
  final String awayName;
  final String awayLogo;

  final int? goalsHome;
  final int? goalsAway;

  /// توقّعه المحفوظ إن وُجد.
  final int? predHome;
  final int? predAway;
  final int multiplier;

  const RoundFixture({
    required this.id,
    required this.kickoffAt,
    required this.open,
    required this.homeName,
    required this.homeLogo,
    required this.awayName,
    required this.awayLogo,
    this.goalsHome,
    this.goalsAway,
    this.predHome,
    this.predAway,
    required this.multiplier,
  });

  factory RoundFixture.fromJson(Map<String, dynamic> j) => RoundFixture(
        id: j['id'] as int,
        kickoffAt: DateTime.parse(j['kickoff_at'] as String).toLocal(),
        open: j['open'] == true,
        homeName: j['home_team_name'] as String? ?? '',
        homeLogo: j['home_logo'] as String? ?? '',
        awayName: j['away_team_name'] as String? ?? '',
        awayLogo: j['away_logo'] as String? ?? '',
        goalsHome: (j['goals_home'] as num?)?.toInt(),
        goalsAway: (j['goals_away'] as num?)?.toInt(),
        predHome: (j['pred_home'] as num?)?.toInt(),
        predAway: (j['pred_away'] as num?)?.toInt(),
        multiplier: (j['multiplier'] as num?)?.toInt() ?? 1,
      );
}

/// جولة في شريط التنقّل.
class RoundRef {
  final String round;
  final int total;
  final int open;

  const RoundRef({required this.round, required this.total, required this.open});

  factory RoundRef.fromJson(Map<String, dynamic> j) => RoundRef(
        round: j['round'] as String? ?? '',
        total: (j['total'] as num?)?.toInt() ?? 0,
        open: (j['open'] as num?)?.toInt() ?? 0,
      );
}

/// جولة كاملة جاهزة للعرض.
class RoundPage {
  final int leagueId;
  final String leagueName;
  final String leagueLogo;
  final List<RoundRef> rounds;
  final String? round;
  final List<RoundFixture> fixtures;
  final int multiplierLeft;
  final int multiplierFactor;

  const RoundPage({
    required this.leagueId,
    required this.leagueName,
    required this.leagueLogo,
    required this.rounds,
    this.round,
    required this.fixtures,
    required this.multiplierLeft,
    required this.multiplierFactor,
  });

  factory RoundPage.fromJson(Map<String, dynamic> j) {
    final league = (j['league'] as Map?) ?? const {};
    final mult = (j['multiplier'] as Map?) ?? const {};
    return RoundPage(
      leagueId: (league['id'] as num?)?.toInt() ?? 0,
      leagueName: league['name'] as String? ?? '',
      leagueLogo: league['logo_url'] as String? ?? '',
      rounds: ((j['rounds'] as List?) ?? const [])
          .map((r) => RoundRef.fromJson(r as Map<String, dynamic>))
          .toList(),
      round: j['round'] as String?,
      fixtures: ((j['fixtures'] as List?) ?? const [])
          .map((f) => RoundFixture.fromJson(f as Map<String, dynamic>))
          .toList(),
      multiplierLeft: (mult['left'] as num?)?.toInt() ?? 0,
      multiplierFactor: (mult['factor'] as num?)?.toInt() ?? 2,
    );
  }
}

/// حصيلة حفظ جولة: كم حُفظ، وكم لم يُطبَّق مضاعِفه، وكم فات موعده.
class RoundSaveResult {
  final int saved;
  final int denied;
  final int late;

  const RoundSaveResult(
      {required this.saved, required this.denied, required this.late});

  factory RoundSaveResult.fromJson(Map<String, dynamic> j) => RoundSaveResult(
        saved: (j['saved'] as num?)?.toInt() ?? 0,
        denied: (j['denied'] as num?)?.toInt() ?? 0,
        late: (j['late'] as num?)?.toInt() ?? 0,
      );
}
