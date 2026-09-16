// نماذج «فريقي» — لاعبٌ في السوق، وتشكيلة، وصفٌّ في نقاط الجولة.
//
// «اللاعب» هنا كرويٌّ في الملعب لا مستخدمٌ عندنا (ذاك Player في
// models/player.dart). الاسمان متشابهان والفرق جوهري، فاللاحقة
// Fantasy تحسم الالتباس عند القراءة بلا أن تُقرأ الاستيرادات.
import '../format.dart';

/// المراكز كما يخزّنها الخادم — مفاتيح قواعد لا نصوص عرض.
enum FantasyPosition { goalkeeper, defender, midfielder, attacker }

extension FantasyPositionX on FantasyPosition {
  static FantasyPosition parse(String? raw) => switch (raw) {
        'Goalkeeper' => FantasyPosition.goalkeeper,
        'Defender' => FantasyPosition.defender,
        'Midfielder' => FantasyPosition.midfielder,
        _ => FantasyPosition.attacker,
      };

  String get wire => switch (this) {
        FantasyPosition.goalkeeper => 'Goalkeeper',
        FantasyPosition.defender => 'Defender',
        FantasyPosition.midfielder => 'Midfielder',
        FantasyPosition.attacker => 'Attacker',
      };

  /// الاسم العربي الكامل — لعناوين الأقسام ورسائل الخطأ.
  String get label => switch (this) {
        FantasyPosition.goalkeeper => 'حراسة',
        FantasyPosition.defender => 'دفاع',
        FantasyPosition.midfielder => 'وسط',
        FantasyPosition.attacker => 'هجوم',
      };

  /// حرفٌ واحد لشارة البطاقة على الملعب — المساحة هناك ضيّقة.
  String get short => switch (this) {
        FantasyPosition.goalkeeper => 'حا',
        FantasyPosition.defender => 'مد',
        FantasyPosition.midfielder => 'وس',
        FantasyPosition.attacker => 'مه',
      };
}

class FantasyPlayer {
  final int id;
  final String name;
  final String? photoUrl;
  final FantasyPosition position;
  final int? teamId;
  final String teamName;
  final String? teamLogo;
  final double price;
  final int totalPoints;

  // حالته داخل تشكيلتي — لاغية لمن هو في السوق وحده.
  final bool onBench;
  final bool isCaptain;
  final bool isVice;

  const FantasyPlayer({
    required this.id,
    required this.name,
    required this.position,
    required this.price,
    this.photoUrl,
    this.teamId,
    this.teamName = '',
    this.teamLogo,
    this.totalPoints = 0,
    this.onBench = false,
    this.isCaptain = false,
    this.isVice = false,
  });

  factory FantasyPlayer.fromJson(Map<String, dynamic> j) => FantasyPlayer(
        id: j['player_id'] as int,
        name: (j['name'] as String?) ?? 'لاعب',
        photoUrl: j['photo_url'] as String?,
        position: FantasyPositionX.parse(j['position'] as String?),
        teamId: j['team_id'] as int?,
        teamName: (j['team_name'] as String?) ?? '',
        teamLogo: j['team_logo'] as String?,
        // السعر يصل نصّاً من NUMERIC — عمود مالي لا يُرسل عائماً.
        price: double.tryParse('${j['price']}') ?? 0,
        totalPoints: (j['total_points'] as int?) ?? 0,
        onBench: j['on_bench'] == true,
        isCaptain: j['is_captain'] == true,
        isVice: j['is_vice'] == true,
      );

  FantasyPlayer copyWith({bool? onBench, bool? isCaptain, bool? isVice}) =>
      FantasyPlayer(
        id: id,
        name: name,
        photoUrl: photoUrl,
        position: position,
        teamId: teamId,
        teamName: teamName,
        teamLogo: teamLogo,
        price: price,
        totalPoints: totalPoints,
        onBench: onBench ?? this.onBench,
        isCaptain: isCaptain ?? this.isCaptain,
        isVice: isVice ?? this.isVice,
      );

  /// السعر كما يُعرض: خانة عشرية واحدة بأرقام غربية دائماً.
  String get priceLabel => Fmt.number(price, decimals: 1);
}

class FantasySquad {
  final String id;
  final String? name;
  final int? clubTeamId;
  final String formation;
  final double budgetLeft;
  final int freeTransfers;
  final int totalPoints;
  final List<FantasyPlayer> players;

  const FantasySquad({
    required this.id,
    required this.formation,
    required this.budgetLeft,
    required this.players,
    this.name,
    this.clubTeamId,
    this.freeTransfers = 1,
    this.totalPoints = 0,
  });

  factory FantasySquad.fromJson(Map<String, dynamic> j) => FantasySquad(
        id: '${j['id']}',
        name: j['name'] as String?,
        clubTeamId: j['club_team_id'] as int?,
        formation: (j['formation'] as String?) ?? '4-4-2',
        budgetLeft: double.tryParse('${j['budget_left']}') ?? 0,
        freeTransfers: (j['free_transfers'] as int?) ?? 1,
        totalPoints: (j['total_points'] as int?) ?? 0,
        players: ((j['players'] as List?) ?? const [])
            .map((p) => FantasyPlayer.fromJson(p as Map<String, dynamic>))
            .toList(),
      );

  List<FantasyPlayer> get starters =>
      players.where((p) => !p.onBench).toList(growable: false);
  List<FantasyPlayer> get bench =>
      players.where((p) => p.onBench).toList(growable: false);
}

/// حدود اللعبة كما يقولها الخادم — لا تُكتب أرقامها هنا.
///
/// التشكيلة خمسة عشر والميزانية مئة اليوم، وقد تتغيّر من اللوحة
/// غداً. نسخةٌ ثانية من الأرقام في التطبيق تعني شاشةً تمنع ما
/// يقبله الخادم، أو تعد بما يرفضه.
class FantasyRules {
  final int squadSize;
  final int starters;
  final double budget;
  final int minFromClub;
  final int maxFromClub;
  final List<String> formations;
  final Map<FantasyPosition, int> quota;

  const FantasyRules({
    required this.squadSize,
    required this.starters,
    required this.budget,
    required this.minFromClub,
    required this.maxFromClub,
    required this.formations,
    required this.quota,
  });

  static const fallback = FantasyRules(
    squadSize: 15,
    starters: 11,
    budget: 100,
    minFromClub: 3,
    maxFromClub: 3,
    formations: ['4-4-2', '4-3-3', '4-5-1', '3-5-2', '3-4-3', '5-3-2', '5-4-1'],
    quota: {
      FantasyPosition.goalkeeper: 2,
      FantasyPosition.defender: 5,
      FantasyPosition.midfielder: 5,
      FantasyPosition.attacker: 3,
    },
  );

  factory FantasyRules.fromJson(Map<String, dynamic>? rules,
      List? formations, Map<String, dynamic>? quota) {
    if (rules == null) return fallback;
    return FantasyRules(
      squadSize: (rules['squad_size'] as int?) ?? 15,
      starters: (rules['starters'] as int?) ?? 11,
      budget: double.tryParse('${rules['budget']}') ?? 100,
      minFromClub: (rules['min_from_club'] as int?) ?? 3,
      maxFromClub: (rules['max_from_club'] as int?) ?? 3,
      formations: formations?.cast<String>() ?? fallback.formations,
      quota: quota == null
          ? fallback.quota
          : {
              for (final e in quota.entries)
                FantasyPositionX.parse(e.key): e.value as int,
            },
    );
  }

  /// عدد كل خط في الأساسي حسب الخطة — «4-4-2» ← ٤ دفاع، ٤ وسط، ٢ هجوم.
  static Map<FantasyPosition, int> shapeOf(String formation) {
    final parts = formation.split('-').map(int.tryParse).toList();
    if (parts.length != 3 || parts.any((p) => p == null)) {
      return shapeOf('4-4-2');
    }
    return {
      FantasyPosition.goalkeeper: 1,
      FantasyPosition.defender: parts[0]!,
      FantasyPosition.midfielder: parts[1]!,
      FantasyPosition.attacker: parts[2]!,
    };
  }
}

/// صفٌّ في شاشة نقاط الجولة.
class FantasyRoundRow {
  final FantasyPlayer player;
  final int points;
  final int multiplier;
  final bool autoSubbed;
  final bool onBench;

  const FantasyRoundRow({
    required this.player,
    required this.points,
    required this.multiplier,
    required this.autoSubbed,
    required this.onBench,
  });

  factory FantasyRoundRow.fromJson(Map<String, dynamic> j) => FantasyRoundRow(
        player: FantasyPlayer.fromJson(j),
        points: (j['points'] as int?) ?? 0,
        multiplier: (j['multiplier'] as int?) ?? 1,
        autoSubbed: j['auto_subbed'] == true,
        onBench: j['on_bench'] == true,
      );
}

/// صفٌّ في عرش «فريقي».
class FantasyRankRow {
  final int rank;
  final String name;
  final String? avatarUrl;
  final String? clubName;
  final String? clubLogo;
  final int totalPoints;
  final bool isMe;

  const FantasyRankRow({
    required this.rank,
    required this.name,
    required this.totalPoints,
    required this.isMe,
    this.avatarUrl,
    this.clubName,
    this.clubLogo,
  });

  factory FantasyRankRow.fromJson(Map<String, dynamic> j) => FantasyRankRow(
        rank: (j['rank'] as int?) ?? 0,
        name: (j['name'] as String?) ?? 'مشجع',
        avatarUrl: j['avatar_url'] as String?,
        clubName: j['club_name'] as String?,
        clubLogo: j['club_logo'] as String?,
        totalPoints: (j['total_points'] as int?) ?? 0,
        isMe: j['is_me'] == true,
      );
}

/// حمولة شاشة السوق كاملة: الحدود واللاعبون في ردٍّ واحد.
///
/// طلبٌ واحد لا اثنان: الشاشة لا تُرسم قبل وصول الاثنين معاً،
/// وطلبان متتاليان يعنيان دوّارةً مرتين على شبكةٍ بطيئة.
class FantasyMarket {
  final FantasyRules rules;
  final List<FantasyPlayer> players;
  final int? leagueId;
  final String? leagueName;
  final bool followRequired;

  const FantasyMarket({
    required this.rules,
    required this.players,
    this.leagueId,
    this.leagueName,
    this.followRequired = false,
  });

  factory FantasyMarket.fromJson(Map<String, dynamic> j) => FantasyMarket(
        rules: FantasyRules.fromJson(
          j['rules'] as Map<String, dynamic>?,
          j['formations'] as List?,
          j['quota'] as Map<String, dynamic>?,
        ),
        players: ((j['players'] as List?) ?? const [])
            .map((p) => FantasyPlayer.fromJson(p as Map<String, dynamic>))
            .toList(),
        leagueId: (j['league'] as Map<String, dynamic>?)?['id'] as int?,
        leagueName: (j['league'] as Map<String, dynamic>?)?['name'] as String?,
        followRequired: j['follow_required'] == true,
      );
}
