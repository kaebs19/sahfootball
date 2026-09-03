// بطاقة حصيلة دوري واحد: شعاره واسمه، ثم أربعة أرقام.
//
// كانت خاصة بشاشة «ملفي». نُقلت هنا حين صار لغير صاحب الملف ملفٌ
// يُفتح (PlayerScreen): البطاقة التي تقول «12 توقّعاً في الإنجليزي»
// عني هي نفسها التي تقولها عن غيري، ونسختان تتباعدان عند أول
// تعديل فيظنّ المستخدم أن الحسابين مختلفان.
//
// المركز والدقة يتبعان عقد الملف كله: null = لا شيء محتسب في هذا
// الدوري بعد، فتُعرض شرطة لا صفراً ولا آخر مركز.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../brand.dart';
import '../config.dart';
import '../models/profile_stats.dart';
import 'brand_widgets.dart';

class LeagueStatsCard extends StatelessWidget {
  final LeagueStats league;

  /// شارة «غير متابَع» لصاحب الملف وحده: المتابعة خيار شخصي، ولا
  /// معنى لإخبار زائر بأن فلاناً لا يتابع دورياً لعب فيه.
  final bool showFollowed;

  const LeagueStatsCard({
    super.key,
    required this.league,
    this.showFollowed = true,
  });

  @override
  Widget build(BuildContext context) {
    final l = league;
    return BrandCard(
      royal: l.rank == 1,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (l.logoUrl != null)
                CachedNetworkImage(
                  imageUrl: AppConfig.absoluteUrl(l.logoUrl!),
                  width: 22,
                  height: 22,
                  errorWidget: (_, _, _) =>
                      const Icon(Icons.emoji_events_outlined, size: 18),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Brand.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (l.rank == 1)
                const BrandChip(label: 'الملك', tone: BrandTone.crown)
              else if (showFollowed && !l.followed)
                const BrandChip(label: 'غير متابَع'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _LeagueNumber(
                value: '${l.points}',
                label: 'نقطة',
                color: Brand.crown,
              ),
              _LeagueNumber(
                value: l.rank != null ? '${l.rank}' : '—',
                label: l.competitors != null && l.rank != null
                    ? 'من ${l.competitors}'
                    : 'المركز',
              ),
              _LeagueNumber(
                value: '${l.predictionsCount}',
                label: '${l.settledPredictions} محتسب',
              ),
              _LeagueNumber(
                value: l.accuracy != null ? '${l.accuracy}%' : '—',
                label: 'الدقة',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LeagueNumber extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _LeagueNumber({
    required this.value,
    required this.label,
    this.color = Brand.text,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          BrandNumber(value, size: 17, color: color),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Brand.textFaint,
              fontSize: 10.5,
              fontFeatures: Brand.tabular,
            ),
          ),
        ],
      ),
    );
  }
}
