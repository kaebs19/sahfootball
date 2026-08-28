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
import '../format.dart';
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
          itemBuilder: (_, i) => BadgeTile(badge: badges[i]),
        ),
      ],
    );
  }
}

class BadgeTile extends StatelessWidget {
  final models.Badge badge;
  const BadgeTile({super.key, required this.badge});

  @override
  Widget build(BuildContext context) {
    final on = badge.earned;
    final icon = _icons[badge.key] ?? Icons.shield_outlined;

    return GestureDetector(
      // الضغط يشرح: العنوان وحده لا يكفي لفهم "ضد الجمهور"، والشرح
      // الدائم تحت كل وسام يغرق الشبكة نصاً.
      onTap: () => showBadgeSheet(context, badge),
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
}

/// ورقة شرح الوسام — يفتحها كل من الشبكة والشريط.
///
/// الشرح ورقة لا سطر تحت الأيقونة: "ضد الجمهور" لا يُفهم من عنوانه،
/// وشرح دائم تحت تسعة أوسمة يغرق القسم نصاً.
void showBadgeSheet(BuildContext context, models.Badge badge) {
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
              // محايد لا أخضر: القاعدة الثانية في الهوية تمنع أن
              // يتقاسم الأخضر بطاقة مع الذهبي، والوسام ذهبي.
              'نلته في ${Fmt.date(intl.DateFormat('d MMMM yyyy', 'ar'), earnedAt)}',
              style: const TextStyle(
                color: Brand.textMuted,
                fontSize: 12.5,
                fontFeatures: Brand.tabular,
              ),
            )
          else if (badge.earned)
            const Text(
              'نلته',
              style: TextStyle(color: Brand.textMuted, fontSize: 12.5),
            )
          else
            const Text(
              'لم تنله بعد',
              style: TextStyle(color: Brand.textFaint, fontSize: 12.5),
            ),
        ],
      ),
    ),
  );
}

/// شريط الأوسمة — النسخة المختصرة في أعلى الملف الشخصي.
///
/// الشبكة الكاملة كانت تأكل شاشتين قبل أن يصل المستخدم إلى سجله،
/// وهي تسعة عناصر ثمانية منها مطفأة في الغالب. الشريط يعرضها كلها
/// في سطر واحد يُمسح بالإبهام، والمكتسبة أولاً كي يرى ما ناله قبل
/// ما ينقصه — و"الكل" تفتح الشبكة لمن أرادها.
class BadgeStrip extends StatelessWidget {
  final List<models.Badge> badges;
  const BadgeStrip({super.key, required this.badges});

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) return const SizedBox.shrink();

    // ترتيب ثابت: المكتسبة أولاً وداخل كل مجموعة يبقى ترتيب السيرفر
    // كما هو — قائمة تعيد ترتيب نفسها بين تحديثين تربك العين.
    final ordered = [
      ...badges.where((b) => b.earned),
      ...badges.where((b) => !b.earned),
    ];
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
            const SizedBox(width: 8),
            Text(
              '$earned من ${badges.length}',
              style: const TextStyle(
                color: Brand.textFaint,
                fontSize: 11.5,
                fontFeatures: Brand.tabular,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => _showAll(context),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'الكل',
                style: TextStyle(fontSize: 12.5, color: Brand.textMuted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: ordered.length,
            separatorBuilder: (_, _) => const SizedBox(width: 9),
            itemBuilder: (_, i) => _StripTile(badge: ordered[i]),
          ),
        ),
      ],
    );
  }

  void _showAll(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Brand.surface,
      isScrollControlled: true, // الشبكة أطول من نصف الشاشة
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Brand.fillStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            BadgeGrid(badges: badges),
          ],
        ),
      ),
    );
  }
}

/// عنصر الشريط: قرص الأيقونة والعنوان تحته، بعرض ثابت كي تصطف
/// الأقراص أفقياً مهما اختلف طول العناوين.
class _StripTile extends StatelessWidget {
  final models.Badge badge;
  const _StripTile({required this.badge});

  @override
  Widget build(BuildContext context) {
    final on = badge.earned;

    return GestureDetector(
      onTap: () => showBadgeSheet(context, badge),
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: on ? Brand.crownWash(0.13) : Brand.fill,
                shape: BoxShape.circle,
                border: Border.all(
                  color: on ? Brand.crownWash(0.40) : Brand.borderSoft,
                ),
              ),
              alignment: Alignment.center,
              child: Icon(
                _icons[badge.key] ?? Icons.shield_outlined,
                size: 24,
                color: on ? Brand.crown : Brand.textFaint,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              badge.title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.25,
                fontWeight: FontWeight.w600,
                color: on ? Brand.crown : Brand.textFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
