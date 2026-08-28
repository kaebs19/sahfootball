// ذيل شاشة "حول التطبيق": الإصدار وحقوق النشر.
//
// رقم الإصدار مكتوب هنا لا مقروءاً من الحزمة: قراءته وقت التشغيل
// تحتاج package_info_plus وقناة أصلية لسطرين نصيين. الثمن أن على
// من يرفع version في pubspec أن يرفعه هنا — ولهذا الاختبار في
// test/version_test.dart يقارن الاثنين ويفشل حين يفترقان.
import 'package:flutter/material.dart';

import '../brand.dart';
import '../widgets/brand_mark.dart';

class AboutFooter extends StatelessWidget {
  static const version = '1.0.0';

  const AboutFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(color: Brand.borderSoft, height: 30),
        const BrandMark(size: 46, carve: Brand.night),
        const SizedBox(height: 12),
        const Text(
          'ملك التوقعات',
          style: TextStyle(
            fontFamily: Brand.displayFont,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Brand.text,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'الإصدار $version',
          style: TextStyle(
            color: Brand.textFaint,
            fontSize: 12,
            fontFeatures: Brand.tabular,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'توقّع بذكاء. اجمع التاج. اجلس على العرش.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Brand.textMuted, fontSize: 12.5),
        ),
      ],
    );
  }
}
