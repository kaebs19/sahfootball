// مكوّنات التاج الذهبي المشتركة: شارة المشترك، بطاقة الدعوة
// للاشتراك، ومكان الإعلان.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../brand.dart';
import '../screens/premium_screen.dart';
import '../state/premium.dart';
import 'brand_widgets.dart';

/// شارة صغيرة بجانب اسم المشترك. ذهبية — وهذا موضع الذهبي بالضبط
/// في الهوية: تاجٌ ورتبة، لا زينة زرّ.
class CrownTag extends StatelessWidget {
  const CrownTag({super.key});

  @override
  Widget build(BuildContext context) {
    return const BrandChip(
      label: 'التاج الذهبي',
      icon: Icons.workspace_premium,
      tone: BrandTone.crown,
    );
  }
}

/// بطاقة تدعو إلى الاشتراك — تختفي وحدها عند المشتركين.
///
/// «تختفي وحدها» قرار مقصود: لو تُرك الشرط لكل شاشة لنُسي في واحدة،
/// فيرى من دفع دعوةً للدفع مرة أخرى — وهي أسرع طريقة لإلغاء اشتراك.
class CrownUpsell extends StatelessWidget {
  /// سبب الظهور هنا — يُكتب في البطاقة فتصير جواباً لا إعلاناً.
  final String reason;

  const CrownUpsell({super.key, required this.reason});

  @override
  Widget build(BuildContext context) {
    if (context.watch<Premium>().isPremium) return const SizedBox.shrink();

    return BrandCard(
      royal: true,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PremiumScreen()),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Brand.crownWash(0.14),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.workspace_premium,
                size: 22, color: Brand.crown),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'التاج الذهبي',
                  style: TextStyle(
                    fontFamily: Brand.displayFont,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: Brand.crown,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  reason,
                  style: const TextStyle(
                      color: Brand.textMuted, fontSize: 12, height: 1.6),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 20, color: Brand.crown),
        ],
      ),
    );
  }
}

/// مكان إعلان.
///
/// لا شبكة إعلانات موصولة بعد (تحتاج حساب AdMob ومعرّفاته)، وهذه
/// الويدجت هي الحدّ الذي ستدخل منه: اليوم تعرض إعلاننا نحن —
/// دعوةً للاشتراك — وغداً تعرض `BannerAd` في نفس المكان بنفس
/// الشرط. والشرط هو الغرض من وجودها أصلاً: **إعلان واحد لا يُعرض
/// لمشترك أبداً**، وتركُ ذلك لكل شاشة يعني أن أول شاشة تُنسى
/// تُظهر إعلاناً لمن دفع كي لا يراه.
///
/// والارتفاع ثابت حتى قبل وصول الامتيازات: مساحة تظهر فجأة وسط
/// قائمة تقفز بالمحتوى تحت إصبع المستخدم.
class AdSlot extends StatelessWidget {
  /// نصّ الدعوة — يختلف باختلاف الشاشة كي لا يتكرر نفسه.
  final String reason;

  const AdSlot({super.key, this.reason = 'بلا إعلانات، ومعزّزات كل شهر.'});

  @override
  Widget build(BuildContext context) {
    if (!context.watch<Premium>().showAds) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: CrownUpsell(reason: reason),
    );
  }
}
