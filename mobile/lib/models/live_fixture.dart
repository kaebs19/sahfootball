// مباراة في تبويب "مباشر" — مباراة مضمومة بتوقّع صاحبها.
//
// لماذا نموذج مستقل عن Fixture بدل إضافة حقول إليه؟ لأن الفرق بين
// التبويبين فرق معنى لا فرق حقول: "المباريات" تعرض جدولاً يخص
// الجميع بالتساوي، و"مباشر" تجيب على سؤال شخصي — ماذا يحدث لتوقّعي
// أنا الآن؟ خلط الاثنين في نموذج واحد كان سيجعل نصف حقوله فارغة
// في كل استخدام.
import 'fixture.dart';

/// حال توقّعك مقابل النتيجة الجارية.
enum PredictionState {
  /// النتيجة مطابقة تماماً لما توقّعت.
  exact,

  /// فارق الأهداف صحيح لكن النتيجة مختلفة.
  diff,

  /// الفريق الفائز صحيح فقط.
  outcome,

  /// لا شيء منها ينطبق — التوقّع خارج المسار الآن.
  none;

  static PredictionState parse(String? raw) => switch (raw) {
        'exact' => exact,
        'diff' => diff,
        'outcome' => outcome,
        _ => none,
      };
}

class LivePrediction {
  final int home;
  final int away;

  /// النقاط التي ستُحتسب لو انتهت المباراة على النتيجة الحالية.
  ///
  /// السيرفر يحسبها بنفس دالة الاحتساب النهائي لا بنسخة موازية —
  /// وإلا لأمكن أن تَعِد الشاشة بخمس نقاط ثم تُحتسب ثلاث.
  final int pointsIfNow;

  final PredictionState state;

  const LivePrediction({
    required this.home,
    required this.away,
    required this.pointsIfNow,
    required this.state,
  });

  factory LivePrediction.fromJson(Map<String, dynamic> json) => LivePrediction(
        home: json['home'] as int,
        away: json['away'] as int,
        pointsIfNow: (json['points_if_now'] as int?) ?? 0,
        state: PredictionState.parse(json['state'] as String?),
      );
}

class LiveFixture {
  final Fixture fixture;

  /// دقيقة اللعب الحالية. تصل من المزوّد لا تُحسب من وقت الانطلاق:
  /// الوقت بدل الضائع والاستراحة والتوقف تجعل الحساب بالساعة خاطئاً.
  final int? elapsed;

  final LivePrediction? myPrediction;

  const LiveFixture({
    required this.fixture,
    this.elapsed,
    this.myPrediction,
  });

  /// هل لحالة التوقّع معنى بعد؟
  ///
  /// قبل انطلاق المباراة تكون النتيجة null، والسيرفر يعاملها صفراً-صفر
  /// كي تبقى الأنواع موحّدة — فيصل `state = none` لتوقّع سليم تماماً
  /// لم يُختبر بعد. عرض "توقعك خارج المسار" على مباراة لم تبدأ كذبة
  /// صريحة، لذلك تُقرأ الحالة خلف هذا الشرط لا مباشرة.
  bool get predictionStateIsMeaningful => fixture.status != 'scheduled';

  factory LiveFixture.fromJson(Map<String, dynamic> json) => LiveFixture(
        fixture: Fixture.fromJson(json),
        elapsed: json['elapsed'] as int?,
        myPrediction: json['my_prediction'] != null
            ? LivePrediction.fromJson(
                json['my_prediction'] as Map<String, dynamic>)
            : null,
      );
}

/// حمولة شاشة "مباشر" كاملة.
///
/// تحمل أكثر من المباريات الجارية عمداً: معظم الوقت لا توجد مباراة
/// جارية أصلاً، وتبويب فارغ في تسعين بالمئة من اليوم تبويب ميت.
/// المباراة القادمة ونتائج اليوم تجعل الشاشة تستحق الفتح دائماً.
class LiveState {
  final List<LiveFixture> live;
  final LiveFixture? nextKickoff;
  final List<LiveFixture> finishedToday;

  const LiveState({
    required this.live,
    this.nextKickoff,
    required this.finishedToday,
  });

  bool get isQuiet => live.isEmpty;

  factory LiveState.fromJson(Map<String, dynamic> json) => LiveState(
        live: (json['live'] as List? ?? [])
            .map((e) => LiveFixture.fromJson(e as Map<String, dynamic>))
            .toList(),
        nextKickoff: json['next_kickoff'] != null
            ? LiveFixture.fromJson(json['next_kickoff'] as Map<String, dynamic>)
            : null,
        finishedToday: (json['finished_today'] as List? ?? [])
            .map((e) => LiveFixture.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
