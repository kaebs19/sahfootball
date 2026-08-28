// شبكة الأوسمة.
//
// المطفأة تُعرض مع المضيئة عمداً: الوسام الذي لم تنله بعد هو الذي
// يدفعك للجولة القادمة، وإخفاؤه يحوّل القسم إلى قائمة ماضٍ. تحت كل
// مطفأ سطر يقول كيف يُنال — بلا ذلك يصبح الشكل لغزاً لا هدفاً.
//
// الذهبي هنا في محله تماماً: الهوية تحجزه للتاج والنقاط والرتب،
// والوسام إنجاز من هذه العائلة. المطفأ محايد بلا أي لون إشارة.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import '../brand.dart';
import '../models/profile_stats.dart' as models;

/// أيقونة لكل وسام. مفتاح غير معروف يأخذ الدرع كتدهور لطيف —
/// إضافة وسام في السيرفر يجب ألا تكسر الشاشة قبل تحديث التطبيق.
const _icons = <String, IconData>{
  'first_pick': Icons.flag_outlined,
  'exact_score': Icons.gps_fixed,
  'streak_5': Icons.local_fire_department_outlined,
  'streak_10': Icons.local_fire_department,
  'full_round': Icons.calendar_month_outlined,
  'against_crowd': Icons.groups_outlined,
  'derby': Icons.bolt_outlined,
  'century': Icons.filter_9_plus_outlined,
  'king': Icons.workspace_premium,
};

class BadgeGrid extends StatelessWidget {
  final List<models.Badge> badges;
  const BadgeGrid({super.key, required this.badges});

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) return const SizedBox.shrink();

    final earned = badges.where((b) => b.earned).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'الأوسمة',
              style: TextStyle(
                fontFamily: Brand.displayFont,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Brand.text,
              ),
            ),
            const Spacer(),
            Text(
              '$earned من ${badges.length}',
              style: const TextStyle(
                color: Brand.textFaint,
                fontSize: 11.5,
                fontFeatures: Brand.tabular,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // ثلاثة في الصف: أكبر يجعل الأيقونة صغيرة على هاتف ضيق،
        // وأقل يجعل القسم طويلاً يزاحم سجل التوقعات تحته.
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: badges.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.82,
          ),
          itemBuilder: (_, i) => _BadgeTile(badge: badges[i]),
        ),
      ],
    );
  }
}

class _BadgeTile extends StatelessWidget {
  final models.Badge badge;
  const _BadgeTile({required this.badge});

  @override
  Widget build(BuildContext context) {
    final on = badge.earned;
    final icon = _icons[badge.key] ?? Icons.shield_outlined;

    return GestureDetector(
      // الضغط يشرح: العنوان وحده لا يكفي لفهم "ضد الجمهور"، والشرح
      // الدائم تحت كل وسام يغرق الشبكة نصاً.
      onTap: () => _explain(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: on ? Brand.crownWash(0.10) : Brand.surface,
          borderRadius: BorderRadius.circular(Brand.radiusCard),
          border: Border.all(
            color: on ? Brand.crownWash(0.35) : Brand.borderSoft,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: on ? Brand.crownWash(0.18) : Brand.fill,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: 21,
                // المطفأ خافت جداً لا رمادي عادي: الفرق بين نلته
                // ولم تنله يجب أن يُرى من مسافة نظرة واحدة.
                color: on ? Brand.crown : Brand.textFaint,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              badge.title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: Brand.displayFont,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: on ? Brand.crown : Brand.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _explain(BuildContext context) {
    final earnedAt = badge.earnedAt;
    showModalBottomSheet(
      context: context,
      backgroundColor: Brand.surface,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Brand.fillStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 22),
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: badge.earned ? Brand.crownWash(0.18) : Brand.fill,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                _icons[badge.key] ?? Icons.shield_outlined,
                size: 32,
                color: badge.earned ? Brand.crown : Brand.textFaint,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              badge.title,
              style: TextStyle(
                fontFamily: Brand.displayFont,
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: badge.earned ? Brand.crown : Brand.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              badge.requirement,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Brand.textMuted,
                fontSize: 13.5,
                height: 1.7,
              ),
            ),
            const SizedBox(height: 16),
            if (badge.earned && earnedAt != null)
              Text(
                'نلته في ${intl.DateFormat('d MMMM yyyy', 'ar').format(earnedAt)}',
                style: const TextStyle(
                  color: Brand.correct,
                  fontSize: 12.5,
                  fontFeatures: Brand.tabular,
                ),
              )
            else if (badge.earned)
              const Text('نلته',
                  style: TextStyle(color: Brand.correct, fontSize: 12.5))
            else
              const Text('لم تنله بعد',
                  style: TextStyle(color: Brand.textFaint, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}
