// ملفي — من أنا في هذه المنافسة، وماذا فعلت.
//
// حلّت محل تبويب "توقعاتي" وابتلعته. السبب أن القائمة وحدها كانت
// تجيب على نصف السؤال: تريك ماذا توقّعت، ولا تقول لك أين أنت.
// الرتبة والدقة والسلسلة هي ما يجعل السجل ذا معنى — والسجل هو ما
// يجعل الأرقام قابلة للتصديق. فصلهما في تبويبين كان يفرّق ما
// يُقرأ معاً.
//
// الترتيب من الأعلى: من أنا (هوية ورتبة) ← كيف أؤدي (أرقام) ←
// ماذا نلت (شريط الأوسمة) ← ماذا فعلت بالضبط (سجلّ).
//
// السجلّ سجلّان في مكان واحد لا قسمان متتاليان: "التوقعات" تجيب
// على "ماذا توقعت؟" و"النقاط" على "من أين جاءت نقاطي؟" — سؤالان
// لا يُقرآن معاً، وعرضهما معاً يعني تمريرة طويلة يتوه فيها الاثنان.
// المبدّل يجعل الشاشة بطول واحد مهما كثر التاريخ.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../format.dart';
import '../config.dart';
import '../models/prediction.dart';
import '../models/premium.dart';
import '../models/profile_stats.dart';
import '../state/session.dart';
import '../widgets/badge_grid.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/league_stats_card.dart';
import '../widgets/premium_widgets.dart';
import '../state/premium.dart';
import 'settings_screen.dart';

/// سلّم الرتب من ملف الهوية.
const _ranks = [
  (5000, 'الملك'),
  (3000, 'أمير'),
  (1500, 'فارس'),
  (500, 'لاعب'),
  (0, 'مشجّع'),
];

String _rankName(int points) => _ranks.firstWhere((r) => points >= r.$1).$2;

/// النقاط الناقصة للرتبة التالية، أو null عند القمة.
(int, String)? _nextRank(int points) {
  final higher = _ranks.where((r) => r.$1 > points).toList();
  if (higher.isEmpty) return null;
  final next = higher.last; // أقرب عتبة فوقه
  return (next.$1 - points, next.$2);
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

/// أي سجلّ يعرضه النصف السفلي من الشاشة.
enum _Log { predictions, points }

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

    return RefreshIndicator(
      onRefresh: _load,
      color: Brand.crown,
      backgroundColor: Brand.surface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
        children: [
          _IdentityCard(
            name: user?.nameOrFallback ?? 'مشجع',
            avatarUrl: user?.avatarUrl,
            stats: stats,
          ),
          const SizedBox(height: 12),
          _StatsGrid(stats: stats),

          // الدرع تحت الأرقام مباشرة: هو جزء من قراءة السلسلة، ولو
          // بَعُد عنها لظهرت سلسلة صمدت أمام خطأ بلا تفسير.
          if (stats.shield.available) ...[
            const SizedBox(height: 12),
            _ShieldCard(shield: stats.shield),
          ],

          const SizedBox(height: 12),
          const CrownUpsell(
            reason: 'عدّل توقّعك، واحمِ سلسلتك، وتصفّح بلا إعلانات.',
          ),

          // الحصيلة لكل دوري: الرقم الكلي فوق يخفي أن اللاعب ملكٌ في
          // السعودي ومتفرّج في الإنجليزي — وهنا يظهر ذلك دورياً دورياً.
          if (stats.byLeague.isNotEmpty) ...[
            const SizedBox(height: 18),
            const BrandSectionLabel('حسب الدوري'),
            const SizedBox(height: 10),
            for (final l in stats.byLeague)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: LeagueStatsCard(league: l),
              ),
          ],

          if (stats.badges.isNotEmpty) ...[
            const SizedBox(height: 18),
            BadgeStrip(badges: stats.badges),
          ],

          const SizedBox(height: 20),
          BrandSegmented(
            labels: const ['التوقعات', 'النقاط'],
            selected: _log == _Log.predictions ? 0 : 1,
            onChanged: (i) => setState(
                () => _log = i == 0 ? _Log.predictions : _Log.points),
          ),
          const SizedBox(height: 12),

          if (_log == _Log.predictions)
            ..._predictionsLog(preds)
          else
            ..._pointsLog(stats, preds),

          const SizedBox(height: 22),
          _AccountCard(email: user?.email),
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
    return [for (final p in preds) _PredictionTile(prediction: p)];
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

/// من أنا: الصورة والاسم والرتبة والمركز.
class _IdentityCard extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final ProfileStats stats;

  const _IdentityCard({
    required this.name,
    this.avatarUrl,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    final rank = _rankName(stats.totalPoints);
    final next = _nextRank(stats.totalPoints);
    final premium = context.watch<Premium>().isPremium;

    return BrandCard(
      royal: true,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              _Avatar(url: avatarUrl, name: name),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: Brand.displayFont,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Brand.text,
                            ),
                          ),
                        ),
                        // تاجٌ صغير بجانب الاسم — الذهبي في موضعه:
                        // رتبة ودور، لا زينة.
                        if (premium) ...[
                          const SizedBox(width: 7),
                          const Icon(Icons.workspace_premium,
                              size: 17, color: Brand.crown),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        BrandChip(label: rank, tone: BrandTone.crown),
                        const SizedBox(width: 6),
                        // المركز فقط لمن شارك: عرض "المركز —" على من
                        // لم يلعب يوحي بأنه خاسر، وهو لم يبدأ بعد.
                        if (stats.rank != null)
                          BrandChip(
                            label:
                                'المركز ${stats.rank} من ${stats.totalCompetitors}',
                          )
                        else
                          const BrandChip(label: 'لم تنافس بعد'),
                      ],
                    ),
                    if (stats.favoriteTeam != null) ...[
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          if (stats.favoriteTeam!.logoUrl != null)
                            Image.network(
                              stats.favoriteTeam!.logoUrl!,
                              width: 15,
                              height: 15,
                              errorBuilder: (_, _, _) =>
                                  const SizedBox.shrink(),
                            ),
                          const SizedBox(width: 5),
                          Text(
                            'يشجّع ${stats.favoriteTeam!.name}',
                            style: const TextStyle(
                              color: Brand.textFaint,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  BrandNumber(
                    '${stats.totalPoints}',
                    size: 30,
                    color: Brand.crown,
                  ),
                  const Text(
                    'نقطة تاج',
                    style: TextStyle(color: Brand.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          if (next != null) ...[
            const SizedBox(height: 14),
            _RankProgress(
              points: stats.totalPoints,
              remaining: next.$1,
              nextName: next.$2,
            ),
          ],
        ],
      ),
    );
  }
}

/// شريط التقدّم نحو الرتبة التالية.
///
/// الرقم المجرّد ("2480 نقطة") لا يقول شيئاً عن القرب. الشريط يحوّل
/// المجموع إلى مسافة باقية، وهي ما يدفع للعب جولة أخرى.
class _RankProgress extends StatelessWidget {
  final int points;
  final int remaining;
  final String nextName;

  const _RankProgress({
    required this.points,
    required this.remaining,
    required this.nextName,
  });

  @override
  Widget build(BuildContext context) {
    final target = points + remaining;
    final floor = _ranks.firstWhere((r) => points >= r.$1).$1;
    final span = (target - floor).clamp(1, 1 << 30);
    final progress = ((points - floor) / span).clamp(0.0, 1.0);

    return Column(
      children: [
        Row(
          children: [
            Text(
              '$remaining نقطة إلى $nextName',
              style: const TextStyle(
                color: Brand.crown,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFeatures: Brand.tabular,
              ),
            ),
            const Spacer(),
            Text(
              '${(progress * 100).round()}%',
              style: const TextStyle(
                color: Brand.textFaint,
                fontSize: 11.5,
                fontFeatures: Brand.tabular,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: Brand.fill,
            valueColor: const AlwaysStoppedAnimation(Brand.crown),
          ),
        ),
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final ProfileStats stats;
  const _StatsGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatBox(
            value: stats.accuracy != null ? '${stats.accuracy}%' : '—',
            label: 'دقة التوقّع',
            hint: stats.accuracy == null ? 'لا شيء محتسب' : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatBox(
            value: '×${stats.longestStreak}',
            label: 'أطول سلسلة',
            hint: stats.currentStreak > 0
                ? 'الحالية ×${stats.currentStreak}'
                : null,
            tone: stats.currentStreak > 0 ? Brand.correct : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatBox(
            value: '${stats.predictionsCount}',
            label: 'توقّع كلي',
            hint: '${stats.settledPredictions} محتسب',
          ),
        ),
      ],
    );
  }
}

/// درع السلسلة: هل يحميه الآن، وكم يفصله عن الدرع التالي.
///
/// يُعرض للجميع لا للمشتركين وحدهم: الدرع يُكتسب بالإصابات المتتالية،
/// والتاج يعطي درعاً جاهزاً فوقه. وإخفاؤه عن غير المشترك كان سيجعل
/// سلسلته تنكسر يوماً وتصمد يوماً بلا سبب يراه.
class _ShieldCard extends StatelessWidget {
  final ShieldState shield;
  const _ShieldCard({required this.shield});

  @override
  Widget build(BuildContext context) {
    final on = shield.active;
    return BrandCard(
      royal: on,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(on ? Icons.shield : Icons.shield_outlined,
              size: 22, color: on ? Brand.crown : Brand.textFaint),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  on ? 'درع السلسلة فعّال' : 'درع السلسلة',
                  style: TextStyle(
                    color: on ? Brand.crown : Brand.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  on
                      ? 'توقّع خاطئ واحد لن يكسر سلسلتك.'
                      : shield.nextIn != null
                          // العدّ العربي من Fmt: "1 توقّعات" خطأ يظهر
                          // في نصّ يُقرأ كل يوم.
                          ? 'يبقى ${Fmt.counted(shield.nextIn!, 'توقّع صحيح واحد', 'توقّعان صحيحان', 'توقّعات صحيحة', 'توقّعاً صحيحاً')} لتنال درعاً.'
                          : 'يُكتسب بالتوقّعات الصحيحة المتتالية.',
                  style: const TextStyle(
                      color: Brand.textMuted, fontSize: 11.5, height: 1.6),
                ),
              ],
            ),
          ),
          if (shield.stock > 0 || shield.max > 1)
            Text(
              // المشترى فوق الحدّ الأقصى للمكتسب، فالمقام يجمعهما —
              // "2/1" كانت ستبدو خطأً.
              '${shield.stock}/${shield.max > shield.stock ? shield.max : shield.stock}',
              style: const TextStyle(
                fontFamily: Brand.displayFont,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Brand.crown,
                fontFeatures: Brand.tabular,
              ),
            ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String value;
  final String label;
  final String? hint;
  final Color? tone;

  const _StatBox({
    required this.value,
    required this.label,
    this.hint,
    this.tone,
  });

  @override
  Widget build(BuildContext context) {
    return BrandCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      child: Column(
        children: [
          BrandNumber(value, size: 21, color: tone ?? Brand.text),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Brand.textMuted, fontSize: 11.5),
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: tone ?? Brand.textFaint,
                fontSize: 10.5,
                fontFeatures: Brand.tabular,
              ),
            ),
          ],
        ],
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

class _Avatar extends StatelessWidget {
  final String? url;
  final String name;
  const _Avatar({this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    const size = 54.0;
    if (url == null) {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Brand.fill,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          name.characters.first,
          style: const TextStyle(
            fontFamily: Brand.displayFont,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Brand.textMuted,
          ),
        ),
      );
    }
    return ClipOval(
      child: Image.network(
        AppConfig.absoluteUrl(url!),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          color: Brand.fill,
          alignment: Alignment.center,
          child: const Icon(Icons.person, color: Brand.textFaint),
        ),
      ),
    );
  }
}

class _PredictionTile extends StatelessWidget {
  final Prediction prediction;
  const _PredictionTile({required this.prediction});

  @override
  Widget build(BuildContext context) {
    final p = prediction;
    final dateFmt = intl.DateFormat('d MMM • h:mm a', 'ar');
    final hasResult = p.goalsHome != null && p.goalsAway != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BrandCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${p.homeTeamName} — ${p.awayTeamName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Brand.text,
                      fontFamily: Brand.displayFont,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  Fmt.date(dateFmt, p.kickoffAt),
                  style: const TextStyle(
                    color: Brand.textFaint,
                    fontSize: 11,
                    fontFeatures: Brand.tabular,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // محايد لا أخضر. كان "توقعك" أخضر دائماً — والأخضر
                // في الهوية يعني "صحيح"، فكان يهنّئ صاحب التوقع
                // الخاطئ بلون النجاح. والقاعدة الثانية تمنع الأخضر
                // أن يتقاسم بطاقة مع الذهبي، والنقاط ذهبية. الحكم
                // على التوقع تقوله شريحة النقاط وحدها.
                _ScoreBox(
                  title: 'توقعك',
                  value: '${p.predHome} - ${p.predAway}',
                  highlight: false,
                ),
                const SizedBox(width: 8),
                _ScoreBox(
                  title: 'النتيجة',
                  value: hasResult ? '${p.goalsHome} - ${p.goalsAway}' : '—',
                  highlight: false,
                ),
                const Spacer(),
                _PointsChip(points: p.isSettled ? (p.points ?? 0) : null),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreBox extends StatelessWidget {
  final String title;
  final String value;
  final bool highlight;

  const _ScoreBox({
    required this.title,
    required this.value,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: highlight ? Brand.correctWash(0.11) : Brand.fill,
        borderRadius: BorderRadius.circular(Brand.radiusSmall),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              color: highlight ? Brand.correct : Brand.textMuted,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 1),
          BrandNumber(
            value,
            size: 15,
            color: highlight ? Brand.correct : Brand.text,
          ),
        ],
      ),
    );
  }
}

class _PointsChip extends StatelessWidget {
  final int? points;
  const _PointsChip({required this.points});

  @override
  Widget build(BuildContext context) {
    if (points == null) {
      return const BrandChip(label: 'بانتظار المباراة', icon: Icons.schedule);
    }
    if (points! > 0) {
      return BrandChip(
        label: '+$points نقطة',
        icon: Icons.emoji_events,
        tone: BrandTone.crown,
      );
    }
    return const BrandChip(label: 'بدون نقاط', icon: Icons.close);
  }
}

/// الحساب — وهنا مكان الخروج الطبيعي: تبويب "ملفي" هو شاشة الحساب.
/// أسفل الملف: البريد ومدخل الإعدادات.
///
/// زر الخروج انتقل إلى الإعدادات مع بقية أفعال الحساب. إبقاؤه هنا
/// كان يضع الفعل الوحيد الذي لا رجعة فيه في نهاية شاشة تُمرَّر
/// يومياً — بينما كل ما يجاوره (تعديل الملف، البريد، الحذف) في
/// مكان واحد آخر.
class _AccountCard extends StatelessWidget {
  final String? email;
  const _AccountCard({this.email});

  @override
  Widget build(BuildContext context) {
    return BrandCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      ),
      child: Row(
        children: [
          const Icon(Icons.settings_outlined, size: 20, color: Brand.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'الإعدادات',
                  style: TextStyle(
                    fontFamily: Brand.displayFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Brand.text,
                  ),
                ),
                if (email != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    email!,
                    textDirection: TextDirection.ltr,
                    style:
                        const TextStyle(color: Brand.textFaint, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 20, color: Brand.textFaint),
        ],
      ),
    );
  }
}
