// ملفي — من أنا في هذه المنافسة، وماذا فعلت.
//
// حلّت محل تبويب "توقعاتي" وابتلعته. السبب أن القائمة وحدها كانت
// تجيب على نصف السؤال: تريك ماذا توقّعت، ولا تقول لك أين أنت.
// الرتبة والدقة والسلسلة هي ما يجعل السجل ذا معنى — والسجل هو ما
// يجعل الأرقام قابلة للتصديق.
//
// الترتيب من الأعلى: من أنا (صورة واسم ورتبة، ثم نقاط ومركز ودقّة
// في شريط واحد) ← كيف ألعب (سلسلة وتوقعات ودرع في شريط واحد) ←
// ماذا فعلت بالضبط (سجلّ بثلاثة تبويبات: توقعات، نقاط، أوسمة) ←
// أين ألعب (الدوريات، أفقياً).
//
// أعيد ترتيبها حين صارت تسع بطاقات متتالية بعرض الشاشة: بطاقة
// للهوية، وثلاث للأرقام، وواحدة للدرع، وواحدة للتاج، وواحدة لكل
// دوري… كلٌّ منها صحيحة وحدها، ومجموعها جدارٌ من البطاقات تتوه فيه
// العين. القاعدة الآن: **ما يُقرأ معاً يجلس معاً** — الأرقام الثلاثة
// شريط، والأداء شريط، والدوريات صفّ يُمرَّر — فتقصر الشاشة إلى
// النصف ولا يسقط منها رقم.
//
// السجلّ سجلّان في مكان واحد لا قسمان متتاليان: "التوقعات" تجيب
// على "ماذا توقعت؟" و"النقاط" على "من أين جاءت نقاطي؟" — سؤالان
// لا يُقرآن معاً. المبدّل يجعل الشاشة بطول واحد مهما كثر التاريخ.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../format.dart';
import '../models/prediction.dart';
import '../models/profile_stats.dart';
import '../state/premium.dart';
import '../state/session.dart';
import '../widgets/badge_grid.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/league_stats_card.dart';
import '../widgets/premium_widgets.dart';
import '../widgets/profile_hero.dart';

/// بعد كم توقّعاً يُدرج الإعلان المدمج — نفس رقم شاشة المباريات
/// كي يكون للإعلان موضعٌ واحد مفهوم في التطبيق كله.
const _adAfterCard = 3;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

/// أي سجلّ يعرضه النصف السفلي من الشاشة.
enum _Log { predictions, points, badges }

class _ProfileScreenState extends State<ProfileScreen> {
  /// الاشتراك يغيّر أرقاماً في هذه الشاشة (درع السلسلة)، وتبويب
  /// "ملفي" يعيش داخل IndexedStack فلا يُبنى من جديد بعد الشراء.
  /// بلا هذا المستمع يرى المشترك درعه القديم حتى يسحب للتحديث.
  Premium? _premium;

  void _onPremiumChanged() {
    if (mounted) _load();
  }

  ProfileStats? _stats;
  List<Prediction>? _predictions;
  String? _error;
  _Log _log = _Log.predictions;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final premium = context.read<Premium>();
    if (identical(premium, _premium)) return;
    _premium?.removeListener(_onPremiumChanged);
    _premium = premium..addListener(_onPremiumChanged);
  }

  @override
  void dispose() {
    _premium?.removeListener(_onPremiumChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    setState(() => _error = null);
    try {
      // الاثنان معاً: الشاشة لا تُقرأ ناقصة، وطلبان متوازيان أسرع
      // من متتاليين بلا أي تعقيد إضافي.
      final results = await Future.wait([
        api.profileStats(),
        api.myPredictions(),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as ProfileStats;
        _predictions = results[1] as List<Prediction>;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return BrandEmpty(icon: Icons.wifi_off, message: _error!, onRetry: _load);
    }
    final stats = _stats;
    final preds = _predictions;
    if (stats == null || preds == null) {
      return const Center(child: CircularProgressIndicator(color: Brand.crown));
    }

    final user = context.watch<Session>().user;
    final premium = context.watch<Premium>().isPremium;

    return RefreshIndicator(
      onRefresh: _load,
      color: Brand.crown,
      backgroundColor: Brand.surface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 20),
        children: [
          ProfileHero(
            name: user?.nameOrFallback ?? 'مشجع',
            avatarUrl: user?.avatarUrl,
            premium: premium,
            favoriteTeam: stats.favoriteTeam,
            totalPoints: stats.totalPoints,
            rank: stats.rank,
            totalCompetitors: stats.totalCompetitors,
            accuracy: stats.accuracy,
          ),
          const SizedBox(height: 10),
          PerformanceStrip(
            longestStreak: stats.longestStreak,
            currentStreak: stats.currentStreak,
            predictionsCount: stats.predictionsCount,
            settledPredictions: stats.settledPredictions,
            shield: stats.shield,
          ),

          // السجلّ مباشرة تحت الأرقام: هو ما يفتح المستخدم الشاشة
          // لأجله يومياً («كم أخذت أمس؟»)، فلا يُدفن تحت الدوريات
          // والأوسمة. والأوسمة تبويبٌ فيه لا قسمٌ مستقل: هي سجلّ
          // أيضاً — سجلّ ما نلت — وثلاثة سجلّات خلف مبدّل واحد أقصر
          // من ثلاثة أقسام متتالية.
          const SizedBox(height: 22),
          const _SectionTitle('السجلّ'),
          const SizedBox(height: 10),
          BrandSegmented(
            labels: const ['التوقعات', 'النقاط', 'الأوسمة'],
            selected: _log.index,
            onChanged: (i) => setState(() => _log = _Log.values[i]),
          ),
          const SizedBox(height: 12),

          ...switch (_log) {
            _Log.predictions => _predictionsLog(preds),
            _Log.points => _pointsLog(stats, preds),
            _Log.badges => [BadgeGrid(badges: stats.badges)],
          },

          // دعوة الاشتراك تختفي وحدها عند المشترك (راجع CrownUpsell).
          const SizedBox(height: 22),
          const CrownUpsell(
            reason: 'عدّل توقّعك، واحمِ سلسلتك، وتصفّح بلا إعلانات.',
          ),

          // الحصيلة لكل دوري: الرقم الكلي فوق يخفي أن اللاعب ملكٌ في
          // السعودي ومتفرّج في الإنجليزي — وهنا يظهر ذلك دورياً دورياً.
          if (stats.byLeague.isNotEmpty) ...[
            const SizedBox(height: 22),
            const _SectionTitle('حسب الدوري'),
            const SizedBox(height: 10),
            LeagueCarousel(leagues: stats.byLeague),
          ],

          // لا بطاقة إعدادات هنا: الترس في شريط التبويب يفتحها، وبطاقة
          // ثانية بنفس الاسم أسفل الشاشة كانت تُقرأ خللاً لا اختصاراً.
        ],
      ),
    );
  }

  /// سجلّ التوقعات: كل ما سجّلته، الأحدث أولاً كما يصل من السيرفر.
  List<Widget> _predictionsLog(List<Prediction> preds) {
    if (preds.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 30),
          child: Text(
            'ما سجّلت أي توقع بعد — ابدأ من شاشة المباريات',
            textAlign: TextAlign.center,
            style: TextStyle(color: Brand.textMuted, height: 1.6),
          ),
        ),
      ];
    }
    // إعلان واحد بين التوقعات، بنفس موضعه في شاشة المباريات: بعد
    // ثلاثة، فيراه من يتصفّح سجلّه ولا يعترض من يفتحه لينظر أعلاه.
    return [
      for (final (i, p) in preds.indexed) ...[
        _PredictionTile(prediction: p),
        if (i == _adAfterCard - 1)
          const AdSlot(reason: 'راجع توقعاتك بلا إعلانات.'),
      ],
    ];
  }

  /// سجلّ النقاط: من أين جاءت النقاط بالضبط.
  ///
  /// المحتسبة وحدها. توقع على مباراة لم تُلعب ليس صفر نقطة بل لا
  /// شيء بعد، وإدراجه في سجلّ نقاط يجعل المجموع لا يطابق الرصيد.
  List<Widget> _pointsLog(ProfileStats stats, List<Prediction> preds) {
    final settled = preds.where((p) => p.isSettled).toList();

    if (settled.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 30),
          child: Text(
            'لا نقاط محتسبة بعد — تُحتسب توقعاتك فور انتهاء مبارياتها',
            textAlign: TextAlign.center,
            style: TextStyle(color: Brand.textMuted, height: 1.6),
          ),
        ),
      ];
    }

    // تجميع بالجولة: النقاط تُجمع في الأذهان جولةً جولة ("كم أخذت
    // في الجولة الماضية؟")، والقائمة المسطحة لا تجيب على ذلك.
    // LinkedHashMap ضمنياً: ترتيب الإدراج محفوظ، والقائمة أصلاً
    // مرتبة تنازلياً بموعد المباراة.
    final byRound = <String, List<Prediction>>{};
    for (final p in settled) {
      byRound.putIfAbsent(Fmt.round(p.round), () => []).add(p);
    }

    return [
      _PointsSummary(stats: stats),
      const SizedBox(height: 12),
      if (stats.recentForm.isNotEmpty) ...[
        _FormCard(form: stats.recentForm),
        const SizedBox(height: 12),
      ],
      if (stats.pointsDistribution.isNotEmpty) ...[
        _DistributionCard(buckets: stats.pointsDistribution),
        const SizedBox(height: 12),
      ],
      for (final entry in byRound.entries) ...[
        _RoundLedger(round: entry.key, predictions: entry.value),
        const SizedBox(height: 10),
      ],
    ];
  }
}

/// عنوان قسم: أكبر قليلاً من BrandSectionLabel وبلون النصّ لا الذهبي.
///
/// الذهبي هنا كان يجعل «حسب الدوري» يبدو رتبةً أو نقاطاً، والعنوان
/// مجرّد لافتة. والأقسام صارت أقلّ وأوضح، فتستحق لافتة تُقرأ.
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: Brand.displayFont,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Brand.text,
        ),
      ),
    );
  }
}

/// ترويسة سجلّ النقاط: الرصيد ومن أين تكوّن.
class _PointsSummary extends StatelessWidget {
  final ProfileStats stats;
  const _PointsSummary({required this.stats});

  @override
  Widget build(BuildContext context) {
    final exact = stats.pointsDistribution
        .where((b) => b.points >= 3)
        .fold(0, (sum, b) => sum + b.count);

    return BrandCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BrandNumber('${stats.totalPoints}', size: 26, color: Brand.crown),
              const SizedBox(height: 2),
              const Text(
                'نقطة تاج',
                style: TextStyle(color: Brand.textMuted, fontSize: 11.5),
              ),
            ],
          ),
          const Spacer(),
          _SummaryCell(
            value: '${stats.settledPredictions}',
            label: 'توقّع محتسب',
          ),
          const SizedBox(width: 18),
          _SummaryCell(value: '$exact', label: 'نتيجة مضبوطة'),
        ],
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  final String value;
  final String label;
  const _SummaryCell({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        BrandNumber(value, size: 16),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Brand.textFaint, fontSize: 10.5),
        ),
      ],
    );
  }
}

/// نقاط جولة واحدة: مجموعها في الترويسة وتفصيلها تحتها.
///
/// الصف الواحد سطر لا بطاقة: هذا سجلّ يُمسح بالعين بحثاً عن رقم،
/// لا قائمة بطاقات تُقرأ واحدة واحدة — بطاقة كاملة لكل مباراة كانت
/// ستجعل جولة واحدة أطول من شاشة.
class _RoundLedger extends StatelessWidget {
  final String round;
  final List<Prediction> predictions;

  const _RoundLedger({required this.round, required this.predictions});

  @override
  Widget build(BuildContext context) {
    final total = predictions.fold(0, (sum, p) => sum + (p.points ?? 0));

    return BrandCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                round,
                style: const TextStyle(
                  fontFamily: Brand.displayFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Brand.text,
                ),
              ),
              const Spacer(),
              Text(
                // الصفر بلا إشارة موجبة: "+0" وعدٌ لم يتحقق.
                total > 0 ? '+$total' : '$total',
                style: TextStyle(
                  fontFamily: Brand.displayFont,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFeatures: Brand.tabular,
                  color: total > 0 ? Brand.crown : Brand.textFaint,
                ),
              ),
            ],
          ),
          const Divider(color: Brand.borderSoft, height: 18),
          // ترويسة الأعمدة: رقمان متجاوران بلا تسمية لغز — أيهما
          // توقعي وأيهما ما حدث فعلاً؟ سطر واحد يحسمها للجولة كلها.
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(child: SizedBox.shrink()),
                _LedgerHead('توقعك', _LedgerRow.scoreWidth),
                _LedgerHead('النتيجة', _LedgerRow.scoreWidth),
                _LedgerHead('نقاط', _LedgerRow.pointsWidth),
              ],
            ),
          ),
          for (final p in predictions) _LedgerRow(prediction: p),
        ],
      ),
    );
  }
}

class _LedgerHead extends StatelessWidget {
  final String label;
  final double width;
  const _LedgerHead(this.label, this.width);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Brand.textFaint, fontSize: 9.5),
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  /// أعمدة بعرض ثابت كي تصطف الأرقام تحت ترويستها مهما اختلفت
  /// أطوال أسماء الفرق — العمود المصطف يُقرأ بنظرة واحدة.
  static const scoreWidth = 58.0;
  static const pointsWidth = 46.0;

  final Prediction prediction;
  const _LedgerRow({required this.prediction});

  @override
  Widget build(BuildContext context) {
    final p = prediction;
    final points = p.points ?? 0;
    final hasResult = p.goalsHome != null && p.goalsAway != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${p.homeTeamName} — ${p.awayTeamName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Brand.text, fontSize: 12.5),
            ),
          ),
          // النتيجة بمسافات حول الشرطة كما في بقية التطبيق: هكذا
          // يضع ترتيب العربية رقم المستضيف على اليمين تحت اسمه.
          // "2-1" بلا مسافات رمز واحد يُرسم يساراً-يميناً فينقلب.
          _LedgerCell('${p.predHome} - ${p.predAway}', Brand.textMuted),
          _LedgerCell(
            hasResult ? '${p.goalsHome} - ${p.goalsAway}' : '—',
            Brand.text,
          ),
          SizedBox(
            width: pointsWidth,
            child: Text(
              points > 0 ? '+$points' : '—',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: Brand.displayFont,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFeatures: Brand.tabular,
                color: points > 0 ? Brand.crown : Brand.textFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerCell extends StatelessWidget {
  final String value;
  final Color color;
  const _LedgerCell(this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _LedgerRow.scoreWidth,
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontFeatures: Brand.tabular,
        ),
      ),
    );
  }
}

/// شكل الأداء عبر الجولات الأخيرة.
class _FormCard extends StatelessWidget {
  final List<RoundForm> form;
  const _FormCard({required this.form});

  @override
  Widget build(BuildContext context) {
    // الاتجاه: مقارنة نصف الفترة الأخير بالأول. رقم واحد يلخّص
    // "هل أتحسّن؟" وهو السؤال الحقيقي خلف الرسم.
    final half = form.length ~/ 2;
    int? delta;
    if (form.length >= 4) {
      final older = form.take(half);
      final newer = form.skip(half);
      final a =
          older.map((f) => f.accuracy).reduce((x, y) => x + y) / older.length;
      final b =
          newer.map((f) => f.accuracy).reduce((x, y) => x + y) / newer.length;
      delta = (b - a).round();
    }

    final spansSeasons = form.map((f) => f.season).toSet().length > 1;

    return BrandCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'دقتك في آخر الجولات',
                style: TextStyle(
                  fontFamily: Brand.displayFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Brand.text,
                ),
              ),
              const Spacer(),
              if (delta != null)
                BrandChip(
                  label: delta > 0 ? '+$delta%' : '$delta%',
                  tone: delta >= 0 ? BrandTone.correct : BrandTone.wrong,
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final f in form)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${f.accuracy}',
                          style: const TextStyle(
                            color: Brand.textFaint,
                            fontSize: 9.5,
                            height: 1.2,
                            fontFeatures: Brand.tabular,
                          ),
                        ),
                        const SizedBox(height: 3),
                        // ارتفاع أدنى للجولة بصفر دقة: العمود المعدوم
                        // يجعل الجولة تبدو غير موجودة، وهي موجودة
                        // وسيئة — فرق يجب أن يُرى.
                        //
                        // والارتفاع محسوب لا مقيَّد بصندوق ثابت: الصف
                        // الثابت كان يفيض بمقدار بكسل حين تبلغ الدقة
                        // مئة، لأن النص والتسمية يضافان فوق العمود.
                        Container(
                          height: 6 + f.accuracy * 0.46,
                          decoration: BoxDecoration(
                            color: f.accuracy >= 50
                                ? Brand.correct
                                : Brand.correct.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          // عند حدود الموسم تعود "ج1" مرتين في نفس
                          // الرسم — جولة من الموسم الماضي وأخرى من
                          // هذا. نضيف الموسم حينها فقط: إضافته دائماً
                          // ضجيج، وإغفاله يجعل التكرار يبدو خللاً.
                          spansSeasons
                              ? '${f.shortLabel}\n${f.season}'
                              : f.shortLabel,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.clip,
                          style: const TextStyle(
                            color: Brand.textFaint,
                            fontSize: 10,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DistributionCard extends StatelessWidget {
  final List<PointsBucket> buckets;
  const _DistributionCard({required this.buckets});

  @override
  Widget build(BuildContext context) {
    final total = buckets.fold<int>(0, (s, b) => s + b.count);
    if (total == 0) return const SizedBox.shrink();

    return BrandCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'كيف تكسب نقاطك',
            style: TextStyle(
              fontFamily: Brand.displayFont,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Brand.text,
            ),
          ),
          const SizedBox(height: 14),
          for (final b in buckets)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        b.points == 0 ? 'بدون نقاط' : '${b.points} نقاط',
                        style: TextStyle(
                          color: b.points == 0 ? Brand.textMuted : Brand.crown,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${b.count} · ${(b.count / total * 100).round()}%',
                        style: const TextStyle(
                          color: Brand.textFaint,
                          fontSize: 11.5,
                          fontFeatures: Brand.tabular,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: b.count / total,
                      minHeight: 5,
                      backgroundColor: Brand.fill,
                      valueColor: AlwaysStoppedAnimation(
                        b.points == 0 ? Brand.fillStrong : Brand.crown,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// صفّ توقّع واحد — دفتر لا بطاقة.
///
/// كان صندوقين («توقعك» و«النتيجة») تحت سطر أسماء الفرق. الشكل
/// الجديد سطران، سطر لكل فريق، وعمودان ثابتان للأرقام: توقّعك ثم
/// ما حدث. هكذا يقع رقم المضيف تحت اسم المضيف ورقم الضيف تحت اسمه،
/// وتُقرأ المقارنة عمودياً بنظرة — والأعمدة تصطفّ من صفّ إلى صفّ
/// فيُمسح السجلّ كله كجدول.
class _PredictionTile extends StatelessWidget {
  final Prediction prediction;
  const _PredictionTile({required this.prediction});

  static const _col = 42.0;

  @override
  Widget build(BuildContext context) {
    final p = prediction;
    final dateFmt = intl.DateFormat('d MMM', 'ar');
    final hasResult = p.goalsHome != null && p.goalsAway != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: BrandCard(
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${Fmt.date(dateFmt, p.kickoffAt)} · ${Fmt.round(p.round)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Brand.textFaint,
                            fontSize: 10.5,
                            fontFeatures: Brand.tabular,
                          ),
                        ),
                      ),
                      const _ColHead('توقعك'),
                      const _ColHead('النتيجة'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _TeamLine(
                    name: p.homeTeamName,
                    pick: p.predHome,
                    goals: hasResult ? p.goalsHome : null,
                  ),
                  const SizedBox(height: 4),
                  _TeamLine(
                    name: p.awayTeamName,
                    pick: p.predAway,
                    goals: hasResult ? p.goalsAway : null,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _PointsChip(points: p.isSettled ? (p.points ?? 0) : null),
          ],
        ),
      ),
    );
  }
}

class _ColHead extends StatelessWidget {
  final String text;
  const _ColHead(this.text);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _PredictionTile._col,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Brand.textFaint, fontSize: 9.5),
      ),
    );
  }
}

class _TeamLine extends StatelessWidget {
  final String name;
  final int pick;
  final int? goals;
  const _TeamLine({required this.name, required this.pick, this.goals});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Brand.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(
          width: _PredictionTile._col,
          child: Text(
            '$pick',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: Brand.displayFont,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Brand.textMuted,
              fontFeatures: Brand.tabular,
            ),
          ),
        ),
        SizedBox(
          width: _PredictionTile._col,
          child: Text(
            goals != null ? '$goals' : '—',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: Brand.displayFont,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: goals != null ? Brand.text : Brand.textFaint,
              fontFeatures: Brand.tabular,
            ),
          ),
        ),
      ],
    );
  }
}

/// حكم التوقّع في شريحة عمودية قصيرة: الرقم كبيراً وتحته كلمة —
/// «+75 نقطة» في سطر واحد كانت تأكل ثلث عرض الصفّ.
class _PointsChip extends StatelessWidget {
  final int? points;
  const _PointsChip({required this.points});

  @override
  Widget build(BuildContext context) {
    final (String value, String label, Color color, Color bg) = switch (points) {
      null => ('⏳', 'بانتظار', Brand.textMuted, Brand.fill),
      > 0 => ('+$points', 'نقطة', Brand.crown, Brand.crownWash(0.12)),
      _ => ('0', 'نقاط', Brand.textFaint, Brand.fill),
    };
    return Container(
      width: 62,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Brand.radiusSmall),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontFamily: Brand.displayFont,
              fontSize: points == null ? 13 : 16,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: Brand.tabular,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: color, fontSize: 10)),
        ],
      ),
    );
  }
}
