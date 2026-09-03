// شريط الدوريات — شرائح أفقية: «الكل» ثم دوريات المستخدم ثم «+».
//
// كان خاصاً بشاشة العرش. نُقل هنا حين احتاجته شاشة المباريات:
// الدوري صار محور التطبيق (المباريات والعرش والملف كلها تُقرأ به)،
// وشريطان متشابهان بفروق لا يفسّرها شيء يجعلان المستخدم يظنهما
// أداتين مختلفتين.
//
// شريحة «+» في آخر الشريط لا زر في الترويسة: من يريد دورياً آخر
// يريده هنا، حيث يرى ما لديه ويلاحظ ما ينقصه.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../brand.dart';
import '../config.dart';
import '../models/champion.dart';

class LeagueStrip extends StatelessWidget {
  final List<LeagueFollow> leagues;

  /// المختار الآن؛ null = شريحة «الكل».
  final int? active;
  final ValueChanged<int?> onPick;

  /// نصّ الشريحة الأولى — «الكل» في المباريات، «العام» في العرش.
  final String allLabel;

  /// null = بلا شريحة «+» (الضيف مثلاً لا يتابع شيئاً).
  final VoidCallback? onAdd;

  const LeagueStrip({
    super.key,
    required this.leagues,
    required this.active,
    required this.onPick,
    this.allLabel = 'الكل',
    this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final count = leagues.length + 1 + (onAdd != null ? 1 : 0);
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (_, i) {
          if (onAdd != null && i == count - 1) return _AddChip(onTap: onAdd!);
          final l = i == 0 ? null : leagues[i - 1];
          final on = l?.id == active;
          return InkWell(
            onTap: () => onPick(l?.id),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: on ? Brand.crown : Brand.fill,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: on ? Brand.crown : Brand.border),
              ),
              child: Row(
                children: [
                  if (l?.logoUrl != null)
                    CachedNetworkImage(
                      imageUrl: AppConfig.absoluteUrl(l!.logoUrl!),
                      width: 17,
                      height: 17,
                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                    ),
                  if (l != null) const SizedBox(width: 6),
                  Text(
                    l?.name ?? allLabel,
                    style: TextStyle(
                      color: on ? Brand.onAccent : Brand.textMuted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// شريحة «+ دوري» — منقّطة الحدّ لتُقرأ فعلاً لا فلتراً.
class _AddChip extends StatelessWidget {
  final VoidCallback onTap;
  const _AddChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Brand.crownWash(0.45)),
        ),
        child: const Row(
          children: [
            Icon(Icons.add, size: 15, color: Brand.crown),
            SizedBox(width: 4),
            Text(
              'دوري',
              style: TextStyle(
                color: Brand.crown,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
