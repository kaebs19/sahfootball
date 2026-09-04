// مكوّنات التاج الذهبي المشتركة: شارة المشترك، بطاقة الدعوة
// للاشتراك، ومكان الإعلان.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../brand.dart';
import '../screens/premium_screen.dart';
import '../state/premium.dart';
import 'ads.dart';
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

/// مكان إعلان داخل قائمة.
///
/// غلافٌ حول [NativeAdSlot] يبقي اسماً واحداً في الشاشات مهما تبدّلت
/// شبكة الإعلانات تحته: الشاشة تقول "هنا إعلان" ولا تعرف من يملؤه.
/// والشرط الذي لا يتغيّر: **لا إعلان لمشترك أبداً** — وهو مطبَّق في
/// مكان واحد لا في كل شاشة.
class AdSlot extends StatelessWidget {
  /// نصّ الدعوة الذي يحلّ محلّ الإعلان إن لم يصل.
  final String reason;

  const AdSlot({super.key, this.reason = 'بلا إعلانات، ومعزّزات كل شهر.'});

  @override
  Widget build(BuildContext context) => NativeAdSlot(fallbackReason: reason);
}
