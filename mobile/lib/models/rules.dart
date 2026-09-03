/// قواعد اللعبة كما يعمل بها الخادم الآن — من GET /api/rules.
///
/// لماذا تُجلب ولا تُكتب في التطبيق؟ لأنها كانت مكتوبة فيه:
/// "نتيجة مضبوطة = 5 · فارق الأهداف = 3 · الفائز = 2". ثم صار
/// المقياس 100/75/50 فبقي التطبيق يَعِد بخمس ويمنح مئة — والمستخدم
/// لا يقرأ ذلك تناقضاً بل يقرؤه كذباً. والأرقام يعدّلها الأدمن من
/// اللوحة، فأي رقم مكتوب في عميل يصير كذباً عند أول تعديل.
class GameRules {
  final int exact;
  final int diff;
  final int outcome;

  /// معامل المضاعِف (2) وعدد المجاني منه لكل دوري في الموسم (5).
  final int multiplierFactor;
  final int multipliersFree;

  /// أعلى جائزة لرهان البطل — في أول الموسم.
  final int championMax;

  const GameRules({
    required this.exact,
    required this.diff,
    required this.outcome,
    required this.multiplierFactor,
    required this.multipliersFree,
    required this.championMax,
  });

  /// احتياطي يطابق DEFAULT_SCORING في السيرفر — يُستعمل حين يتعذّر
  /// الجلب. أرقام قريبة من الحقيقة أفضل من شاشة بلا جدول نقاط،
  /// وأسوأ منهما أرقام من عصر آخر.
  static const fallback = GameRules(
    exact: 100,
    diff: 75,
    outcome: 50,
    multiplierFactor: 2,
    multipliersFree: 5,
    championMax: 1000,
  );

  factory GameRules.fromJson(Map<String, dynamic> json) {
    final s = (json['scoring'] as Map?) ?? const {};
    final m = (json['multipliers'] as Map?) ?? const {};
    final c = (json['champion'] as Map?) ?? const {};
    return GameRules(
      exact: (s['exact'] as num?)?.toInt() ?? fallback.exact,
      diff: (s['diff'] as num?)?.toInt() ?? fallback.diff,
      outcome: (s['outcome'] as num?)?.toInt() ?? fallback.outcome,
      multiplierFactor:
          (m['factor'] as num?)?.toInt() ?? fallback.multiplierFactor,
      multipliersFree:
          (m['free_per_season'] as num?)?.toInt() ?? fallback.multipliersFree,
      championMax: (c['max_award'] as num?)?.toInt() ?? fallback.championMax,
    );
  }
}

/// حالة المضاعِف أمام لاعب في مباراة — من
/// GET /api/predictions/multiplier/:fixtureId.
/// المضاعِف المشترى ×5 أمام هذه المباراة.
class BoostState {
  final int factor;
  final int left;
  final bool on;

  const BoostState({this.factor = 5, this.left = 0, this.on = false});

  factory BoostState.fromJson(Map<String, dynamic> j) => BoostState(
        factor: (j['factor'] as num?)?.toInt() ?? 5,
        left: (j['left'] as num?)?.toInt() ?? 0,
        on: j['on'] == true,
      );
}

class MultiplierState {
  final int factor;
  final int free;
  final int used;
  final int left;

  /// هل هذا التوقّع مضاعَف بالفعل؟
  final bool on;

  /// المضاعِف المشترى — أداة ثانية إلى جانب المجانية، ولا تُشغَّلان
  /// معاً: التوقّع يحمل مضاعِفاً واحداً بحكم عمود القاعدة.
  final BoostState boost;

  const MultiplierState({
    required this.factor,
    required this.free,
    required this.used,
    required this.left,
    required this.on,
    this.boost = const BoostState(),
  });

  factory MultiplierState.fromJson(Map<String, dynamic> json) =>
      MultiplierState(
        factor: (json['factor'] as num?)?.toInt() ?? 2,
        free: (json['free'] as num?)?.toInt() ?? 0,
        used: (json['used'] as num?)?.toInt() ?? 0,
        left: (json['left'] as num?)?.toInt() ?? 0,
        on: json['on'] == true,
        boost: BoostState.fromJson(
            (json['boost'] as Map<String, dynamic>?) ?? const {}),
      );
}
