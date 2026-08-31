/// دوري في قائمة المتابعة — من GET /api/leagues.
class LeagueFollow {
  final int id;
  final String name;
  final String? logoUrl;
  final bool followed;

  const LeagueFollow({
    required this.id,
    required this.name,
    this.logoUrl,
    required this.followed,
  });

  factory LeagueFollow.fromJson(Map<String, dynamic> json) => LeagueFollow(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        logoUrl: json['logo_url'] as String?,
        followed: json['followed'] == true,
      );

  LeagueFollow copyWith({bool? followed}) => LeagueFollow(
        id: id,
        name: name,
        logoUrl: logoUrl,
        followed: followed ?? this.followed,
      );
}

/// نادٍ في شبكة اختيار البطل.
class ChampionTeam {
  final int id;
  final String name;
  final String? logoUrl;

  const ChampionTeam({required this.id, required this.name, this.logoUrl});

  factory ChampionTeam.fromJson(Map<String, dynamic> json) => ChampionTeam(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        logoUrl: json['logo_url'] as String?,
      );
}

/// رهانٌ محفوظ: النادي والجائزة المقفلة لحظة الاختيار.
class ChampionPick {
  final int teamId;
  final String teamName;
  final int award;
  final int? points; // null = لم يُسوَّ بعد (الموسم جارٍ)

  const ChampionPick({
    required this.teamId,
    required this.teamName,
    required this.award,
    this.points,
  });

  factory ChampionPick.fromJson(Map<String, dynamic> json) => ChampionPick(
        teamId: json['team_id'] as int,
        teamName: json['team_name'] as String? ?? '',
        award: (json['award'] as num?)?.toInt() ?? 0,
        points: (json['points'] as num?)?.toInt(),
      );
}

/// بطاقة رهان دوري واحد — من GET /api/champion.
class ChampionCard {
  final int leagueId;
  final String leagueName;
  final List<ChampionTeam> teams;

  /// سعر الرهان اليوم، وكم انقضى من الموسم.
  final int award;
  final int maxAward;
  final double progress;

  final ChampionPick? mine;

  const ChampionCard({
    required this.leagueId,
    required this.leagueName,
    required this.teams,
    required this.award,
    required this.maxAward,
    required this.progress,
    this.mine,
  });

  /// نسبة مئوية جاهزة للعرض.
  int get progressPct => (progress * 100).round();

  factory ChampionCard.fromJson(Map<String, dynamic> json) {
    final league = (json['league'] as Map?) ?? const {};
    final quote = (json['quote'] as Map?) ?? const {};
    final mine = json['mine'] as Map<String, dynamic>?;
    return ChampionCard(
      leagueId: league['id'] as int,
      leagueName: league['name'] as String? ?? '',
      teams: ((json['teams'] as List?) ?? const [])
          .map((t) => ChampionTeam.fromJson(t as Map<String, dynamic>))
          .toList(),
      award: (quote['award'] as num?)?.toInt() ?? 0,
      maxAward: (quote['max'] as num?)?.toInt() ?? 1000,
      progress: (quote['progress'] as num?)?.toDouble() ?? 0,
      mine: mine == null ? null : ChampionPick.fromJson(mine),
    );
  }
}
