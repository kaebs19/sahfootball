// بطاقة مباراة في تبويب "مباشر".
//
// تختلف عن FixtureCard في تبويب "المباريات" اختلافاً مقصوداً:
//
//   FixtureCard   → الموعد هو البطل، والدعوة "سجّل توقعك".
//   LiveMatchCard → النتيجة هي البطل (كبيرة في الوسط)، والدقيقة
//                   تنبض بجانبها، والسطر الأخير يقول ماذا يعني ذلك
//                   لتوقّعك أنت.
//
// نفس المباراة تظهر في التبويبين بشكلين مختلفين لأن السؤال مختلف.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../brand.dart';
import '../format.dart';
import '../models/live_fixture.dart';
import 'brand_widgets.dart';

enum LiveCardMode { live, finished }

class LiveMatchCard extends StatelessWidget {
  final LiveFixture match;
  final LiveCardMode mode;

  /// الضغط يفتح شاشة المباراة — الأحداث والإحصاءات والتشكيلة.
  final VoidCallback? onTap;

  const LiveMatchCard({
    super.key,
    required this.match,
    required this.mode,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final f = match.fixture;
    final isLive = mode == LiveCardMode.live;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BrandCard(
        // الحدّ الذهبي حين يكون توقّعك مضبوطاً الآن: أعلى لحظة في
        // التجربة تستحق أن تُرى من طرف العين قبل قراءة أي نص.
        royal: match.myPrediction?.state == PredictionState.exact,
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  Fmt.round(f.round),
                  style: const TextStyle(
                      color: Brand.textFaint,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (isLive)
                  _MinuteBadge(elapsed: match.elapsed)
                else
                  const BrandChip(label: 'انتهت'),
              ],
            ),
            const SizedBox(height: 14),

            // النتيجة في القلب — أكبر عنصر في البطاقة.
            Row(
              children: [
                Expanded(
                    child: _Team(name: f.homeTeamName, logo: f.homeTeamLogo)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _Score(
                    home: f.goalsHome,
                    away: f.goalsAway,
                    live: isLive,
                  ),
                ),
                Expanded(
                    child: _Team(name: f.awayTeamName, logo: f.awayTeamLogo)),
              ],
            ),

            const SizedBox(height: 14),
            LivePredictionLine(prediction: match.myPrediction, live: isLive),
          ],
        ),
      ),
    );
  }
}

/// الدقيقة الجارية بنقطة نابضة.
class _MinuteBadge extends StatefulWidget {
  final int? elapsed;
  const _MinuteBadge({this.elapsed});

  @override
  State<_MinuteBadge> createState() => _MinuteBadgeState();
}

class _MinuteBadgeState extends State<_MinuteBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Brand.wrong.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(Brand.radiusChip),
        border: Border.all(color: Brand.wrong.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween(begin: 1.0, end: 0.2).animate(_c),
            child: Container(
              width: 6,
              height: 6,
              decoration:
                  const BoxDecoration(color: Brand.wrong, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            // الدقيقة قد تغيب لحظة بين تحديثين — "مباشر" وحدها أصدق
            // من عرض صفر أو شرطة في مكان رقم.
            widget.elapsed != null ? "${widget.elapsed}'" : 'مباشر',
            style: const TextStyle(
              fontFamily: Brand.displayFont,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Brand.wrong,
              fontFeatures: Brand.tabular,
            ),
          ),
        ],
      ),
    );
  }
}

class _Score extends StatelessWidget {
  final int? home;
  final int? away;
  final bool live;
  const _Score({this.home, this.away, required this.live});

  @override
  Widget build(BuildContext context) {
    final text = (home != null && away != null) ? '$home - $away' : '- : -';
    return Text(
      text,
      style: TextStyle(
        fontFamily: Brand.displayFont,
        fontSize: 30,
        fontWeight: FontWeight.w700,
        // النتيجة الجارية بلون النص الكامل، والمنتهية أهدأ قليلاً:
        // الجاري يستحق الانتباه، والمنتهي صار سجلاً.
        color: live ? Brand.text : Brand.textMuted,
        height: 1.1,
        fontFeatures: Brand.tabular,
      ),
    );
  }
}

class _Team extends StatelessWidget {
  final String name;
  final String? logo;
  const _Team({required this.name, this.logo});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(color: Brand.fill, shape: BoxShape.circle),
          padding: const EdgeInsets.all(6),
          child: logo != null
              ? CachedNetworkImage(
                  imageUrl: logo!,
                  errorWidget: (_, _, _) => const Icon(Icons.shield,
                      size: 20, color: Brand.textFaint),
                )
              : const Icon(Icons.shield, size: 20, color: Brand.textFaint),
        ),
        const SizedBox(height: 7),
        Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: Brand.text, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// السطر الذي يجعل هذه الشاشة شخصية: ماذا يعني ما يحدث لتوقّعك؟
///
/// عامّ لأن شاشة المباراة تعرضه أيضاً: الشارة التي تقول «مضبوط
/// الآن» في القائمة يجب أن تكون هي نفسها بعد الضغط، لا نسخة تُقلّدها.
class LivePredictionLine extends StatelessWidget {
  final LivePrediction? prediction;
  final bool live;

  /// يُستعمل مع المباريات التي انطلقت فقط — الجارية والمنتهية.
  ///
  /// قبل الانطلاق لا معنى لحالة التوقّع (انظر
  /// [LiveFixture.predictionStateIsMeaningful])، وبطاقة "المباراة
  /// القادمة" تعرض التوقّع كنص مجرّد بلا حكم عليه.
  const LivePredictionLine({super.key, this.prediction, required this.live});

  @override
  Widget build(BuildContext context) {
    final p = prediction;

    if (p == null) {
      return const BrandChip(
        label: 'لم تتوقّع هذه المباراة',
        icon: Icons.remove_circle_outline,
      );
    }

    // الذهبي هنا مسموح: النقاط المكتسبة هي بالضبط ما تحجزه له الهوية.
    final (String label, IconData icon, BrandTone tone) = switch (p.state) {
      PredictionState.exact => (
          live
              ? 'توقعك مضبوط الآن · ${p.pointsIfNow} نقاط على الطريق'
              : 'نتيجة مضبوطة · +${p.pointsIfNow}',
          Icons.emoji_events,
          BrandTone.crown,
        ),
      PredictionState.diff => (
          live
              ? 'فارق الأهداف مضبوط · ${p.pointsIfNow} نقاط على الطريق'
              : 'فارق الأهداف · +${p.pointsIfNow}',
          Icons.trending_up,
          BrandTone.crown,
        ),
      PredictionState.outcome => (
          live
              ? 'الفائز صحيح · ${p.pointsIfNow} نقاط على الطريق'
              : 'الفائز صحيح · +${p.pointsIfNow}',
          Icons.check_circle_outline,
          BrandTone.correct,
        ),
      PredictionState.none => (
          live ? 'توقعك خارج المسار الآن' : 'بدون نقاط',
          Icons.close,
          BrandTone.wrong,
        ),
    };

    return Column(
      children: [
        // توقّعك مقابل الواقع — المقارنة التي جاء المستخدم لأجلها.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'توقعك ${p.home} - ${p.away}',
              style: const TextStyle(
                color: Brand.textMuted,
                fontSize: 12,
                fontFeatures: Brand.tabular,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        BrandChip(label: label, icon: icon, tone: tone),
      ],
    );
  }
}
