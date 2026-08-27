// ملفي — من أنا في هذه المنافسة، وماذا فعلت.
//
// حلّت محل تبويب "توقعاتي" وابتلعته. السبب أن القائمة وحدها كانت
// تجيب على نصف السؤال: تريك ماذا توقّعت، ولا تقول لك أين أنت.
// الرتبة والدقة والسلسلة هي ما يجعل السجل ذا معنى — والسجل هو ما
// يجعل الأرقام قابلة للتصديق. فصلهما في تبويبين كان يفرّق ما
// يُقرأ معاً.
//
// الترتيب من الأعلى: من أنا (هوية ورتبة) ← كيف أؤدي (أرقام) ←
// إلى أين أتجه (شكل الأداء) ← ماذا فعلت بالضبط (السجل).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../config.dart';
import '../models/prediction.dart';
import '../models/profile_stats.dart';
import '../state/session.dart';
import '../widgets/brand_widgets.dart';

/// سلّم الرتب من ملف الهوية.
const _ranks = [
  (5000, 'الملك'),
  (3000, 'أمير'),
  (1500, 'فارس'),
  (500, 'لاعب'),
  (0, 'مشجّع'),
];

String _rankName(int points) =>
    _ranks.firstWhere((r) => points >= r.$1).$2;

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

class _ProfileScreenState extends State<ProfileScreen> {
  ProfileStats? _stats;
  List<Prediction>? _predictions;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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

          if (stats.recentForm.isNotEmpty) ...[
            const SizedBox(height: 12),
            _FormCard(form: stats.recentForm),
          ],

          if (stats.pointsDistribution.isNotEmpty) ...[
            const SizedBox(height: 12),
            _DistributionCard(buckets: stats.pointsDistribution),
          ],

          const SizedBox(height: 20),
          const BrandSectionLabel('سجلّ التوقعات'),
          const SizedBox(height: 10),
          if (preds.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Text(
                'ما سجّلت أي توقع بعد — ابدأ من شاشة المباريات',
                textAlign: TextAlign.center,
                style: TextStyle(color: Brand.textMuted, height: 1.6),
              ),
            )
          else
            for (final p in preds) _PredictionTile(prediction: p),

          const SizedBox(height: 22),
          _AccountCard(email: user?.email),
        ],
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
                    Text(
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
                            Image.network(stats.favoriteTeam!.logoUrl!,
                                width: 15, height: 15,
                                errorBuilder: (_, _, _) =>
                                    const SizedBox.shrink()),
                          const SizedBox(width: 5),
                          Text('يشجّع ${stats.favoriteTeam!.name}',
                              style: const TextStyle(
                                  color: Brand.textFaint, fontSize: 11.5)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  BrandNumber('${stats.totalPoints}',
                      size: 30, color: Brand.crown),
                  const Text('نقطة تاج',
                      style: TextStyle(color: Brand.textMuted, fontSize: 11)),
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
            Text('$remaining نقطة إلى $nextName',
                style: const TextStyle(
                    color: Brand.crown,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFeatures: Brand.tabular)),
            const Spacer(),
            Text('${(progress * 100).round()}%',
                style: const TextStyle(
                    color: Brand.textFaint,
                    fontSize: 11.5,
                    fontFeatures: Brand.tabular)),
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
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Brand.textMuted, fontSize: 11.5)),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint!,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: tone ?? Brand.textFaint,
                    fontSize: 10.5,
                    fontFeatures: Brand.tabular)),
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
      final a = older.map((f) => f.accuracy).reduce((x, y) => x + y) / older.length;
      final b = newer.map((f) => f.accuracy).reduce((x, y) => x + y) / newer.length;
      delta = (b - a).round();
    }

    final spansSeasons = form.map((f) => f.season).toSet().length > 1;

    return BrandCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('دقتك في آخر الجولات',
                  style: TextStyle(
                      fontFamily: Brand.displayFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Brand.text)),
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
                        Text('${f.accuracy}',
                            style: const TextStyle(
                                color: Brand.textFaint,
                                fontSize: 9.5,
                                height: 1.2,
                                fontFeatures: Brand.tabular)),
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
                          spansSeasons ? '${f.shortLabel}\n${f.season}' : f.shortLabel,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.clip,
                          style: const TextStyle(
                              color: Brand.textFaint,
                              fontSize: 10,
                              height: 1.2),
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
          const Text('كيف تكسب نقاطك',
              style: TextStyle(
                  fontFamily: Brand.displayFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Brand.text)),
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
                      Text('${b.count} · ${(b.count / total * 100).round()}%',
                          style: const TextStyle(
                              color: Brand.textFaint,
                              fontSize: 11.5,
                              fontFeatures: Brand.tabular)),
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
                          b.points == 0 ? Brand.fillStrong : Brand.crown),
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
        decoration: const BoxDecoration(color: Brand.fill, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(name.characters.first,
            style: const TextStyle(
                fontFamily: Brand.displayFont,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Brand.textMuted)),
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
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                Text(dateFmt.format(p.kickoffAt),
                    style: const TextStyle(
                        color: Brand.textFaint,
                        fontSize: 11,
                        fontFeatures: Brand.tabular)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _ScoreBox(
                    title: 'توقعك',
                    value: '${p.predHome} - ${p.predAway}',
                    highlight: true),
                const SizedBox(width: 8),
                _ScoreBox(
                    title: 'النتيجة',
                    value: hasResult ? '${p.goalsHome} - ${p.goalsAway}' : '—',
                    highlight: false),
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
          Text(title,
              style: TextStyle(
                  color: highlight ? Brand.correct : Brand.textMuted,
                  fontSize: 10)),
          const SizedBox(height: 1),
          BrandNumber(value,
              size: 15, color: highlight ? Brand.correct : Brand.text),
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
          tone: BrandTone.crown);
    }
    return const BrandChip(label: 'بدون نقاط', icon: Icons.close);
  }
}

/// الحساب — وهنا مكان الخروج الطبيعي: تبويب "ملفي" هو شاشة الحساب.
class _AccountCard extends StatelessWidget {
  final String? email;
  const _AccountCard({this.email});

  @override
  Widget build(BuildContext context) {
    return BrandCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('الحساب',
              style: TextStyle(
                  fontFamily: Brand.displayFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Brand.text)),
          if (email != null) ...[
            const SizedBox(height: 6),
            Text(email!,
                textDirection: TextDirection.ltr,
                style: const TextStyle(color: Brand.textMuted, fontSize: 12.5)),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _confirmLogout(context),
              icon: const Icon(Icons.logout, size: 17),
              label: const Text('تسجيل الخروج'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Brand.wrong,
                side: BorderSide(color: Brand.wrong.withValues(alpha: 0.35)),
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final session = context.read<Session>();
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('متأكد تبي تسجل خروج؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Brand.wrong),
            child: const Text('خروج'),
          ),
        ],
      ),
    );
    if (yes == true) await session.logout();
  }
}
