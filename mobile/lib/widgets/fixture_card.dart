// بطاقة مباراة: الفريقان، الموعد أو النتيجة، وتوقع المستخدم إن وُجد.
//
// الويدجت "غبي" عمداً: يستقبل كل شيء جاهزاً (المباراة، توقعي،
// ماذا يحدث عند الضغط) ولا يعرف API ولا حالة — فيسهل استخدامه
// في أي شاشة مستقبلاً (مباريات المجموعة مثلاً) واختباره معزولاً.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import '../brand.dart';
import '../format.dart';
import '../models/fixture.dart';
import 'brand_widgets.dart';

class FixtureCard extends StatelessWidget {
  final Fixture fixture;
  final ({int home, int away})? myPick;
  final VoidCallback? onTap; // null = التوقع مقفل، البطاقة غير قابلة للضغط

  const FixtureCard({
    super.key,
    required this.fixture,
    this.myPick,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final timeFmt = intl.DateFormat('h:mm a', 'ar');
    final hasScore = fixture.goalsHome != null && fixture.goalsAway != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BrandCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          children: [
            // سطر علوي: الجولة على جهة والحالة على الأخرى — نفس
            // ترويسة بطاقة المباراة في ملف الهوية.
            Row(
              children: [
                Text(
                  Fmt.round(fixture.round),
                  style: const TextStyle(
                      color: Brand.textFaint,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                _StatusChip(fixture: fixture),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _TeamCell(
                      name: fixture.homeTeamName, logo: fixture.homeTeamLogo),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: hasScore
                      // المباراة المنتهية تعرض نتيجتها، والمجدولة تعرض
                      // موعدها — الرقم الأهم في كل حالة.
                      ? BrandNumber(
                          '${fixture.goalsHome} - ${fixture.goalsAway}',
                          size: 22)
                      : Column(
                          children: [
                            Text(
                              Fmt.date(timeFmt, fixture.kickoffAt),
                              style: const TextStyle(
                                fontFamily: Brand.displayFont,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Brand.text,
                                fontFeatures: Brand.tabular,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text('ضد',
                                style: TextStyle(
                                    color: Brand.textFaint, fontSize: 10.5)),
                          ],
                        ),
                ),
                Expanded(
                  child: _TeamCell(
                      name: fixture.awayTeamName, logo: fixture.awayTeamLogo),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _PickRow(pick: myPick, open: fixture.isOpenForPrediction),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final Fixture fixture;
  const _StatusChip({required this.fixture});

  @override
  Widget build(BuildContext context) {
    if (fixture.status == 'finished') {
      return const BrandChip(label: 'انتهت');
    }
    if (!fixture.isOpenForPrediction) {
      return const BrandChip(label: 'جارية', tone: BrandTone.wrong);
    }

    // عدّاد الإقفال: الهوية تعرض "يُقفل بعد ٤٠ د" لأن الإلحاح جزء من
    // اللعبة — الموعد وحده لا يخبر المستخدم كم بقي له ليقرر.
    final left = fixture.kickoffAt.difference(DateTime.now());
    if (left.inHours < 24) {
      // الأحمر للساعة الأخيرة فقط. كان يُصبغ به كل ما دون ٢٤ ساعة،
      // أي كل مباريات اليوم — ولون التحذير الذي يظهر دائماً يتوقف
      // عن كونه تحذيراً، فلا يبقى شيء يميّز المباراة التي توشك
      // فعلاً أن تُقفل.
      final urgent = left.inHours < 1;
      return BrandChip(
        label: 'يُقفل بعد ${Fmt.untilShort(left)}',
        tone: urgent ? BrandTone.wrong : BrandTone.neutral,
      );
    }
    return const BrandChip(label: 'مفتوح', tone: BrandTone.correct);
  }
}

class _TeamCell extends StatelessWidget {
  final String name;
  final String? logo;
  const _TeamCell({required this.name, this.logo});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            color: Brand.fill, // قرص محايد خلف الشعار كما في الهوية
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(6),
          child: logo != null
              ? CachedNetworkImage(
                  imageUrl: logo!,
                  // بديل رمزي لو فشل التحميل — شعار مكسور أسوأ من
                  // أيقونة عامة
                  errorWidget: (_, _, _) =>
                      const Icon(Icons.shield, size: 20, color: Brand.textFaint),
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

class _PickRow extends StatelessWidget {
  final ({int home, int away})? pick;
  final bool open;
  const _PickRow({required this.pick, required this.open});

  @override
  Widget build(BuildContext context) {
    // التوقع المسجَّل نغمته "صح" لأنه اختيار مؤكَّد — وهذا استعمال
    // الأخضر الذي تسمح به الهوية. لا ذهبي هنا: الذهبي يظهر فقط حين
    // تتحول التوقعات إلى نقاط، في شاشة توقعاتي والعرش.
    final (String label, IconData icon, BrandTone tone) =
        switch ((pick, open)) {
      ((var p)?, true) => (
          'توقعك ${p.home} - ${p.away} — اضغط للتعديل',
          Icons.edit_outlined,
          BrandTone.correct,
        ),
      ((var p)?, false) => (
          'توقعك ${p.home} - ${p.away}',
          Icons.lock_outline,
          BrandTone.neutral,
        ),
      (null, true) => (
          'اضغط وسجّل توقعك',
          Icons.add_circle_outline,
          BrandTone.correct,
        ),
      (null, false) => ('أُغلق التوقع', Icons.lock_outline, BrandTone.neutral),
    };

    return SizedBox(
      width: double.infinity,
      child: Align(
        alignment: Alignment.center,
        child: BrandChip(label: label, icon: icon, tone: tone),
      ),
    );
  }
}
