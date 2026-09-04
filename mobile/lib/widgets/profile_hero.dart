// ترويسة الملف — من هذا، وأين هو، وكيف يلعب.
//
// مشتركة بين «ملفي» وملف اللاعب العام عمداً: الشاشتان تُقرآن بالعين
// نفسها، ونسختان تتباعدان عند أول تعديل فيظنّ المستخدم أن حسابه
// وحساب غيره يُحسبان بطريقتين.
//
// الشكل: صورة في المنتصف لا في الزاوية — الملف عن شخص لا عن بطاقة —
// ثم الاسم والرتبة، ثم شريط واحد بثلاثة أرقام يفصلها خيط رفيع بدل
// ثلاث بطاقات متجاورة: البطاقات الثلاث كانت تصنع ثلاث جزر بلا صلة،
// والشريط يقول إنها قراءة واحدة: نقاط ← مركز ← دقّة.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../brand.dart';
import '../config.dart';
import '../format.dart';
import '../models/premium.dart';
import '../models/profile_stats.dart';
import '../models/rank.dart';
import 'brand_widgets.dart';

class ProfileHero extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final bool premium;
  final bool isMe;
  final FavoriteTeam? favoriteTeam;
  final int totalPoints;

  /// null = لم ينافس بعد (عقد ProfileStats).
  final int? rank;
  final int totalCompetitors;
  final int? accuracy;

  const ProfileHero({
    super.key,
    required this.name,
    this.avatarUrl,
    this.premium = false,
    this.isMe = false,
    this.favoriteTeam,
    required this.totalPoints,
    this.rank,
    required this.totalCompetitors,
    this.accuracy,
  });

  @override
  Widget build(BuildContext context) {
    final tier = Rank.of(totalPoints);
    final next = _nextRank(totalPoints);

    return Column(
      children: [
        _Avatar(url: avatarUrl, name: name, premium: premium),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: Brand.displayFont,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Brand.text,
                ),
              ),
            ),
            // تاجٌ صغير بجانب الاسم — الذهبي في موضعه: رتبة ودور،
            // لا زينة.
            if (premium) ...[
              const SizedBox(width: 6),
              const Icon(Icons.workspace_premium, size: 18, color: Brand.crown),
            ],
            if (isMe && !premium) ...[
              const SizedBox(width: 6),
              const Text('· أنت',
                  style: TextStyle(color: Brand.textFaint, fontSize: 12)),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            BrandChip(
              label: tier.label,
              icon: Icons.workspace_premium,
              tone: BrandTone.crown,
            ),
            if (favoriteTeam != null)
              _TeamChip(team: favoriteTeam!),
          ],
        ),
        const SizedBox(height: 14),

        // شريط الأرقام الثلاثة. ذهبيٌّ حدُّه لأن ما فيه ملكيّ: نقاط
        // ومركز — وهذا حرفياً موضع الذهبي في الهوية.
        BrandCard(
          royal: true,
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
          child: Column(
            children: [
              IntrinsicHeight(
                child: Row(
                  children: [
                    _Cell(
                      value: '$totalPoints',
                      label: 'نقطة تاج',
                      color: Brand.crown,
                      size: 26,
                    ),
                    const _Hairline(),
                    _Cell(
                      value: rank != null ? '$rank' : '—',
                      // «من 120» يقول حجم المنافسة؛ ومن لم يلعب لا يُقال
                      // له «آخر مركز» — يُقال لم ينافس بعد.
                      label: rank != null
                          ? 'من ${Fmt.digits('$totalCompetitors')}'
                          : 'لم ينافس بعد',
                    ),
                    const _Hairline(),
                    _Cell(
                      value: accuracy != null ? '$accuracy%' : '—',
                      label: accuracy != null ? 'دقّة التوقّع' : 'لا شيء محتسب',
                    ),
                  ],
                ),
              ),
              if (next != null) ...[
                const SizedBox(height: 14),
                _RankProgress(
                  points: totalPoints,
                  floor: tier.from,
                  target: next.from,
                  nextName: next.label,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// الرتبة التالية فوق هذه النقاط، أو null عند القمة.
Rank? _nextRank(int points) {
  for (final r in Rank.values) {
    if (r.from > points) return r;
  }
  return null;
}

class _Cell extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final double size;
  const _Cell({
    required this.value,
    required this.label,
    this.color = Brand.text,
    this.size = 21,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          BrandNumber(value, size: size, color: color),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Brand.textMuted,
              fontSize: 11,
              fontFeatures: Brand.tabular,
            ),
          ),
        ],
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: Brand.borderSoft,
    );
  }
}

/// شريط التقدّم نحو الرتبة التالية.
///
/// الرقم المجرّد ("2480 نقطة") لا يقول شيئاً عن القرب. الشريط يحوّل
/// المجموع إلى مسافة باقية، وهي ما يدفع للعب جولة أخرى.
class _RankProgress extends StatelessWidget {
  final int points;
  final int floor;
  final int target;
  final String nextName;

  const _RankProgress({
    required this.points,
    required this.floor,
    required this.target,
    required this.nextName,
  });

  @override
  Widget build(BuildContext context) {
    final span = (target - floor).clamp(1, 1 << 30);
    final progress = ((points - floor) / span).clamp(0.0, 1.0);
    final remaining = target - points;

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            backgroundColor: Brand.fill,
            valueColor: const AlwaysStoppedAnimation(Brand.crown),
          ),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            Text(
              '$remaining نقطة إلى $nextName',
              style: const TextStyle(
                color: Brand.textMuted,
                fontSize: 11.5,
                fontFeatures: Brand.tabular,
              ),
            ),
            const Spacer(),
            Text(
              '${(progress * 100).round()}%',
              style: const TextStyle(
                color: Brand.textFaint,
                fontSize: 11,
                fontFeatures: Brand.tabular,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TeamChip extends StatelessWidget {
  final FavoriteTeam team;
  const _TeamChip({required this.team});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 11, 4),
      decoration: BoxDecoration(
        color: Brand.fill,
        borderRadius: BorderRadius.circular(Brand.radiusChip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (team.logoUrl != null)
            CachedNetworkImage(
              imageUrl: AppConfig.absoluteUrl(team.logoUrl!),
              width: 16,
              height: 16,
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            ),
          const SizedBox(width: 6),
          Text(
            'يشجّع ${team.name}',
            style: const TextStyle(color: Brand.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? url;
  final String name;
  final bool premium;
  const _Avatar({this.url, required this.name, required this.premium});

  @override
  Widget build(BuildContext context) {
    const size = 84.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Brand.fill,
        // حلقة ذهبية للمشترك — التاج حول الوجه لا حوله كلمة.
        border: Border.all(
          color: premium ? Brand.crown : Brand.border,
          width: premium ? 2.5 : 1.5,
        ),
        image: url != null
            ? DecorationImage(
                image: CachedNetworkImageProvider(AppConfig.absoluteUrl(url!)),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: url == null
          ? Text(
              name.isEmpty ? '' : name.characters.first,
              style: const TextStyle(
                fontFamily: Brand.displayFont,
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: Brand.textMuted,
              ),
            )
          : null,
    );
  }
}

/// كيف يلعب: السلسلة والتوقعات، والدرع لصاحب الملف وحده.
///
/// الدرع صار خانة بين الأرقام لا بطاقة مستقلة: هو جزء من قراءة
/// السلسلة (كم صمدت، وهل ستصمد أمام الخطأ التالي) وبطاقة كاملة له
/// كانت تطيل الشاشة وتفصله عمّا يفسّره.
class PerformanceStrip extends StatelessWidget {
  final int longestStreak;
  final int currentStreak;
  final int predictionsCount;
  final int settledPredictions;
  final ShieldState? shield;

  const PerformanceStrip({
    super.key,
    required this.longestStreak,
    required this.currentStreak,
    required this.predictionsCount,
    required this.settledPredictions,
    this.shield,
  });

  @override
  Widget build(BuildContext context) {
    final s = shield;
    final shieldOn = s?.active ?? false;
    return BrandCard(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _Cell(
              value: '×$longestStreak',
              label: currentStreak > 0 ? 'سلسلة · الحالية ×$currentStreak' : 'أطول سلسلة',
              color: currentStreak > 0 ? Brand.correct : Brand.text,
            ),
            const _Hairline(),
            _Cell(
              value: '$predictionsCount',
              label: '$settledPredictions محتسب',
            ),
            if (s != null && s.available) ...[
              const _Hairline(),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      shieldOn ? Icons.shield : Icons.shield_outlined,
                      size: 22,
                      color: shieldOn ? Brand.crown : Brand.textFaint,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      shieldOn
                          ? 'درع فعّال ${s.stock}/${s.max > s.stock ? s.max : s.stock}'
                          : s.nextIn != null
                              ? 'درع بعد ${s.nextIn}'
                              : 'بلا درع',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: shieldOn ? Brand.crown : Brand.textMuted,
                        fontSize: 11,
                        fontFeatures: Brand.tabular,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
