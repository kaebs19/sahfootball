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

  /// حركة سعره في الجولة الأخيرة — تُعرض شارةً ▲/▼ بجوار السعر.
  ///
  /// السعر وحده يقول «كم يساوي»، والحركة تقول «إلى أين يتّجه»،
  /// وهي نصف قرار الشراء: من يصعد اشترِه قبل أن يغلو.
  final double priceDelta;
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
    this.priceDelta = 0,
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
        priceDelta: double.tryParse('${j['price_delta']}') ?? 0,
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
        priceDelta: priceDelta,
        totalPoints: totalPoints,
        onBench: onBench ?? this.onBench,
        isCaptain: isCaptain ?? this.isCaptain,
        isVice: isVice ?? this.isVice,
      );

  /// السعر كما يُعرض: خانة عشرية واحدة بأرقام غربية دائماً.
  String get priceLabel => Fmt.number(price, decimals: 1);

  /// حركة السعر كنصّ بإشارتها — فارغ حين لا حركة.
  String get deltaLabel => priceDelta == 0
      ? ''
      : '${priceDelta > 0 ? '+' : '−'}${Fmt.number(priceDelta.abs(), decimals: 1)}';
}

class FantasySquad {
  final String id;
  final String? name;
  final int? clubTeamId;

  /// هوية «فريقي» كما يقولها الخادم — لا تُستنبط من اللاعبين.
  ///
  /// استنباطها من أول لاعبٍ ناديه هو النادي كان يعمل ما دامت
  /// التشكيلة مبنيّة، ويسكت في اللحظة الوحيدة التي تهمّ: من ثبّت
  /// ناديه ولم يشترِ بعد لا لاعب له يُستنبط منه شيء.
  final String? clubName;
  final String? clubLogo;
  final String formation;
  final double budgetLeft;

  /// أسعار لاعبيك اليوم. والمحفظة + هذه = **قيمة فريقك** — وهو
  /// المقياس الثاني بعد النقاط: من ينمو فريقه يشتري ما لا
  /// يستطيعه غيره.
  final double squadValue;
  final int freeTransfers;
  final int totalPoints;
  final List<FantasyPlayer> players;

  const FantasySquad({
    required this.id,
    required this.formation,
    required this.budgetLeft,
    required this.players,
    this.squadValue = 0,
    this.name,
    this.clubTeamId,
    this.clubName,
    this.clubLogo,
    this.freeTransfers = 1,
    this.totalPoints = 0,
  });

  factory FantasySquad.fromJson(Map<String, dynamic> j) => FantasySquad(
        id: '${j['id']}',
        name: j['name'] as String?,
        clubTeamId: j['club_team_id'] as int?,
        clubName: j['club_name'] as String?,
        clubLogo: j['club_logo'] as String?,
        formation: (j['formation'] as String?) ?? '4-4-2',
        budgetLeft: double.tryParse('${j['budget_left']}') ?? 0,
        squadValue: double.tryParse('${j['squad_value']}') ?? 0,
        freeTransfers: (j['free_transfers'] as int?) ?? 1,
        totalPoints: (j['total_points'] as int?) ?? 0,
        players: ((j['players'] as List?) ?? const [])
            .map((p) => FantasyPlayer.fromJson(p as Map<String, dynamic>))
            .toList(),
      );

  /// قيمة فريقك كاملةً.
  double get totalValue => budgetLeft + squadValue;

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
/// سطرٌ واحد من تفصيل النقاط: «هدف ٥».
class PointLine {
  final String label;
  final int points;
  const PointLine({required this.label, required this.points});

  factory PointLine.fromJson(Map<String, dynamic> j) => PointLine(
        label: (j['label'] as String?) ?? '',
        points: (j['points'] as int?) ?? 0,
      );
}

class FantasyRoundRow {
  final FantasyPlayer player;
  final int points;
  final int multiplier;
  final bool autoSubbed;
  final bool onBench;

  /// من أين جاءت نقاطه — كما حُسبت يوم الجولة لا بجدول اليوم.
  final List<PointLine> lines;

  const FantasyRoundRow({
    required this.player,
    required this.points,
    required this.multiplier,
    required this.autoSubbed,
    required this.onBench,
    this.lines = const [],
  });

  factory FantasyRoundRow.fromJson(Map<String, dynamic> j) => FantasyRoundRow(
        player: FantasyPlayer.fromJson(j),
        points: (j['points'] as int?) ?? 0,
        multiplier: (j['multiplier'] as int?) ?? 1,
        autoSubbed: j['auto_subbed'] == true,
        onBench: j['on_bench'] == true,
        lines: ((j['lines'] as List?) ?? const [])
            .map((l) => PointLine.fromJson(l as Map<String, dynamic>))
            .toList(),
      );
}

/// صفٌّ في عرش «فريقي».
class FantasyRankRow {
  final int rank;

  /// معرّف صاحبه — الصفّ بابٌ إلى تشكيلته لا سطرٌ يُقرأ.
  final String? userId;
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
    this.userId,
    this.avatarUrl,
    this.clubName,
    this.clubLogo,
  });

  factory FantasyRankRow.fromJson(Map<String, dynamic> j) => FantasyRankRow(
        rank: (j['rank'] as int?) ?? 0,
        userId: j['user_id']?.toString(),
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

/// حال انتقالات هذا الأسبوع — يُقرأ قبل الإقفال لا بعده.
///
/// الخصم الذي يُكتشف بعد وقوعه عقوبة، والذي يُرى قبله قرار.
class FantasyTransfers {
  final String? round;
  final int used;
  final int free;

  /// سالبة أو صفر — ما سيُخصم من نقاط الجولة.
  final int cost;
  final bool wildcardActive;
  final bool wildcardAvailable;

  const FantasyTransfers({
    required this.used,
    required this.free,
    required this.cost,
    required this.wildcardActive,
    required this.wildcardAvailable,
    this.round,
  });

  factory FantasyTransfers.fromJson(Map<String, dynamic> j) => FantasyTransfers(
        round: j['round'] as String?,
        used: (j['used'] as int?) ?? 0,
        free: (j['free'] as int?) ?? 1,
        cost: (j['cost'] as int?) ?? 0,
        wildcardActive: j['wildcard_active'] == true,
        wildcardAvailable: j['wildcard_available'] == true,
      );

  /// كم انتقالاً يبقى مجانياً.
  int get freeLeft => (free - used).clamp(0, free);
}

/// دوريٌ في شاشة التهيئة — واسمه وشعاره وهل بدأ فيه.
class FantasySetupLeague {
  final int id;
  final String name;
  final String logoUrl;
  final bool hasSquad;

  const FantasySetupLeague({
    required this.id,
    required this.name,
    required this.logoUrl,
    required this.hasSquad,
  });

  factory FantasySetupLeague.fromJson(Map<String, dynamic> j) =>
      FantasySetupLeague(
        id: j['id'] as int,
        name: (j['name'] as String?) ?? 'دوري',
        logoUrl: (j['logo_url'] as String?) ?? '',
        hasSquad: j['has_squad'] == true,
      );
}

/// نادٍ يُختار ليكون «فريقي».
class FantasyClub {
  final int id;
  final String name;
  final String? logoUrl;

  const FantasyClub({required this.id, required this.name, this.logoUrl});

  factory FantasyClub.fromJson(Map<String, dynamic> j) => FantasyClub(
        id: j['id'] as int,
        name: (j['name'] as String?) ?? 'نادٍ',
        logoUrl: j['logo_url'] as String?,
      );
}

/// حمولة شاشة التهيئة: الدوريات وأندية المختار منها والقواعد.
class FantasySetup {
  final List<FantasySetupLeague> leagues;
  final List<FantasyClub> clubs;
  final FantasyRules rules;
  final int? leagueId;

  /// النادي المثبَّت في هذا الدوري — لا يتغيّر بعد اختياره، فالشبكة
  /// تعرضه مقفلاً بدل أن تدعو إلى اختيارٍ يرفضه الخادم.
  final int? club;
  final bool followRequired;

  const FantasySetup({
    required this.leagues,
    required this.clubs,
    required this.rules,
    this.leagueId,
    this.club,
    this.followRequired = false,
  });

  factory FantasySetup.fromJson(Map<String, dynamic> j) => FantasySetup(
        leagues: ((j['leagues'] as List?) ?? const [])
            .map((l) => FantasySetupLeague.fromJson(l as Map<String, dynamic>))
            .toList(),
        clubs: ((j['clubs'] as List?) ?? const [])
            .map((c) => FantasyClub.fromJson(c as Map<String, dynamic>))
            .toList(),
        rules: FantasyRules.fromJson(
            j['rules'] as Map<String, dynamic>?, null, null),
        leagueId: (j['league'] as Map<String, dynamic>?)?['id'] as int?,
        club: j['club'] as int?,
        followRequired: j['follow_required'] == true,
      );
}

/// تشكيلة مدرّبٍ آخر كما تُعرض في ملفه.
///
/// **مجمَّدة لا حيّة** (راجع FANTASY.md): ما يُعرض هو تشكيلة آخر
/// جولةٍ أُقفلت. ورؤية التشكيلة الحيّة قبل صافرة البداية تعني أن
/// من يتصدّر يُنسَخ، فتموت المفاضلة التي هي اللعبة كلها.
class FantasyManagerView {
  final String? name;
  final String? avatarUrl;
  final String? clubName;
  final String? clubLogo;
  final String formation;
  final int? rank;
  final int totalPoints;
  final double teamValue;

  /// الجولة المعروضة — null لمن لم تُقفل له جولة بعد.
  final String? round;
  final int roundPoints;
  final List<FantasyRoundRow> players;

  const FantasyManagerView({
    required this.formation,
    required this.totalPoints,
    required this.teamValue,
    required this.players,
    this.name,
    this.avatarUrl,
    this.clubName,
    this.clubLogo,
    this.rank,
    this.round,
    this.roundPoints = 0,
  });

  /// لا تشكيلة بعد — إمّا لم يبنِ، أو لم تُقفل له جولة.
  bool get isEmpty => players.isEmpty;

  factory FantasyManagerView.fromJson(Map<String, dynamic> j) {
    final m = (j['manager'] as Map<String, dynamic>?) ?? const {};
    return FantasyManagerView(
      name: m['name'] as String?,
      avatarUrl: m['avatar_url'] as String?,
      clubName: m['club_name'] as String?,
      clubLogo: m['club_logo'] as String?,
      formation: (m['formation'] as String?) ?? '4-4-2',
      rank: m['rank'] as int?,
      totalPoints: (m['total_points'] as int?) ?? 0,
      teamValue: double.tryParse('${m['squad_value']}') ?? 0,
      round: j['round'] as String?,
      roundPoints: (j['total'] as int?) ?? 0,
      players: ((j['players'] as List?) ?? const [])
          .map((p) => FantasyRoundRow.fromJson(p as Map<String, dynamic>))
          .toList(),
    );
  }
}
