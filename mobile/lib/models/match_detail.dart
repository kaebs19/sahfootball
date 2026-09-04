// شاشة المباراة — كل ما يعرضه /api/fixtures/:id/match.
//
// كل قسم قد يكون فارغاً لسبب مشروع لا لعطل: التشكيلة لا تُنشر قبل
// ساعة من الانطلاق، والإحصاءات لا توجد قبل صافرة البداية، ولا
// مواجهات سابقة لفريقين يلتقيان أول مرة. لذلك القوائم فارغة لا
// null، والشاشة تكتب لكل قسم فارغ جملته الخاصة بدل «تعذّر الجلب».
import 'live_fixture.dart';

/// نوع الحدث في الخط الزمني — يقرّر الأيقونة واللون.
enum MatchEventKind {
  goal,
  ownGoal,
  penaltyGoal,
  missedPenalty,
  yellow,
  red,
  substitution;

  /// السيرفر يصنّف (cls) ويترجم (label) في مكان واحد يخدم الموقع
  /// والتطبيق؛ هنا نقرأ تصنيفه لا نصّه كي لا يتفرّق التصنيفان.
  static MatchEventKind parse(String? cls, String? detail) => switch (cls) {
        'own' => ownGoal,
        'miss' => missedPenalty,
        'red' => red,
        'yellow' => yellow,
        'subst' => substitution,
        'goal' => detail == 'هدف من ركلة جزاء' ? penaltyGoal : goal,
        _ => goal,
      };

  bool get isGoal => this == goal || this == ownGoal || this == penaltyGoal;
}

class MatchEvent {
  final int minute;

  /// الوقت بدل الضائع: 90+3 يصل minute=90 و extra=3.
  final int? extra;
  final bool home;
  final String player;
  final String? assist;
  final MatchEventKind kind;
  final String label;

  const MatchEvent({
    required this.minute,
    this.extra,
    required this.home,
    required this.player,
    this.assist,
    required this.kind,
    required this.label,
  });

  /// "90+3'" — الشكل الذي يعرفه كل من شاهد مباراة.
  String get minuteLabel =>
      extra != null && extra! > 0 ? "$minute+$extra'" : "$minute'";

  factory MatchEvent.fromJson(Map<String, dynamic> j) => MatchEvent(
        minute: (j['minute'] as num?)?.toInt() ?? 0,
        extra: (j['extra'] as num?)?.toInt(),
        home: j['side'] == 'home',
        player: (j['player'] ?? '') as String,
        assist: j['assist'] as String?,
        kind: MatchEventKind.parse(j['cls'] as String?, j['label'] as String?),
        label: (j['label'] ?? '') as String,
      );
}

/// صفّ إحصاء: قيمة لكل فريق. تصل نصاً أحياناً ("55%") ورقماً أحياناً،
/// فنحفظ النصّ للعرض والرقم للشريط.
class MatchStat {
  final String label;
  final String home;
  final String away;
  final double homeValue;
  final double awayValue;

  const MatchStat({
    required this.label,
    required this.home,
    required this.away,
    required this.homeValue,
    required this.awayValue,
  });

  static double _num(Object? v) =>
      double.tryParse(v.toString().replaceAll('%', '').trim()) ?? 0;

  factory MatchStat.fromJson(Map<String, dynamic> j) => MatchStat(
        label: (j['label'] ?? '') as String,
        home: (j['home'] ?? 0).toString(),
        away: (j['away'] ?? 0).toString(),
        homeValue: _num(j['home']),
        awayValue: _num(j['away']),
      );

  /// نصيب المضيف من المجموع — لرسم الشريط. نصف-نصف حين لا شيء.
  double get homeShare {
    final total = homeValue + awayValue;
    return total == 0 ? 0.5 : homeValue / total;
  }
}

class LineupPlayer {
  final int? number;
  final String name;
  final String pos;

  /// موضعه على الملعب "صف:عمود" من المزوّد — الصف 1 الحارس. null حين
  /// لا يرسله (بعض الدوريات الصغيرة)، فتُرسم التشكيلة قائمةً لا ملعباً.
  final int? row;
  final int? col;

  const LineupPlayer({
    this.number,
    required this.name,
    required this.pos,
    this.row,
    this.col,
  });

  factory LineupPlayer.fromJson(Map<String, dynamic> j) => LineupPlayer(
        number: (j['number'] as num?)?.toInt(),
        name: (j['name'] ?? '') as String,
        pos: (j['pos'] ?? '') as String,
        row: (j['row'] as num?)?.toInt(),
        col: (j['col'] as num?)?.toInt(),
      );

  /// الاسم الأخير وحده تحت الدائرة: "K. Benzema" لا يتّسع تحت دائرة
  /// بعرض ثلاثين نقطة، و"Benzema" يكفي لمن يعرفه.
  String get shortName {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? name : parts.last;
  }
}

class Lineup {
  final String? formation;
  final String? coach;
  final List<LineupPlayer> starters;
  final List<LineupPlayer> bench;

  const Lineup({
    this.formation,
    this.coach,
    required this.starters,
    required this.bench,
  });

  /// هل تُرسم ملعباً؟ يكفي أن يكون لكل الأساسيين موضع.
  bool get hasGrid =>
      starters.isNotEmpty && starters.every((p) => p.row != null && p.col != null);

  factory Lineup.fromJson(Map<String, dynamic> j) => Lineup(
        formation: j['formation'] as String?,
        coach: j['coach'] as String?,
        starters: (j['starters'] as List? ?? [])
            .map((e) => LineupPlayer.fromJson(e as Map<String, dynamic>))
            .toList(),
        bench: (j['bench'] as List? ?? [])
            .map((e) => LineupPlayer.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class HeadToHead {
  final int id;
  final DateTime date;
  final String league;
  final int? homeId;
  final String home;
  final String away;
  final int goalsHome;
  final int goalsAway;

  const HeadToHead({
    required this.id,
    required this.date,
    required this.league,
    this.homeId,
    required this.home,
    required this.away,
    required this.goalsHome,
    required this.goalsAway,
  });

  factory HeadToHead.fromJson(Map<String, dynamic> j) => HeadToHead(
        id: (j['id'] as num).toInt(),
        date: DateTime.parse(j['date'] as String).toLocal(),
        league: (j['league'] ?? '') as String,
        homeId: (j['homeId'] as num?)?.toInt(),
        home: (j['home'] ?? '') as String,
        away: (j['away'] ?? '') as String,
        goalsHome: (j['goalsHome'] as num?)?.toInt() ?? 0,
        goalsAway: (j['goalsAway'] as num?)?.toInt() ?? 0,
      );
}

class MatchDetail {
  /// المباراة بتوقّعي — نفس نموذج تبويب «مباشر»، فالشارة التي تقول
  /// «مضبوط الآن» في القائمة هي نفسها هنا.
  final LiveFixture match;
  final List<MatchEvent> events;
  final List<MatchStat> statistics;
  final Lineup? homeLineup;
  final Lineup? awayLineup;
  final List<HeadToHead> h2h;

  const MatchDetail({
    required this.match,
    required this.events,
    required this.statistics,
    this.homeLineup,
    this.awayLineup,
    required this.h2h,
  });

  /// الأهداف وحدها، لكتابة الهدّافين تحت النتيجة.
  List<MatchEvent> get goals => events.where((e) => e.kind.isGoal).toList();

  factory MatchDetail.fromJson(Map<String, dynamic> j) {
    final lineups = (j['lineups'] as Map<String, dynamic>?) ?? const {};
    Lineup? lineup(Object? raw) =>
        raw is Map<String, dynamic> ? Lineup.fromJson(raw) : null;
    return MatchDetail(
      match: LiveFixture.fromJson(j['fixture'] as Map<String, dynamic>),
      events: (j['events'] as List? ?? [])
          .map((e) => MatchEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
      statistics: (j['statistics'] as List? ?? [])
          .map((e) => MatchStat.fromJson(e as Map<String, dynamic>))
          .toList(),
      homeLineup: lineup(lineups['home']),
      awayLineup: lineup(lineups['away']),
      h2h: (j['h2h'] as List? ?? [])
          .map((e) => HeadToHead.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
