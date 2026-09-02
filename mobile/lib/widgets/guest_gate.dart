// بوابة الضيف — تحل محل الشاشات التي تحتاج حساباً في وضع الضيف.
//
// ليست شاشة خطأ بل دعوة: تقول ماذا يوجد خلف الباب تحديداً (لا
// "سجّل أولاً" المجردة) وتضع زر التسجيل في متناول الإبهام. الضيف
// الذي يفهم ما سيكسبه يسجّل؛ الذي يُصدّ بجدار يحذف التطبيق.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../brand.dart';
import '../state/session.dart';

class GuestGate extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const GuestGate({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(icon, size: 52, color: Brand.textFaint),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontSize: 19),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Brand.textMuted, fontSize: 14, height: 1.7),
            ),
            const SizedBox(height: 24),
            FilledButton(
              // leaveGuest يبدّل الجذر لشاشة الدخول — وفيها التسجيل
              // والدخول بالمزوّدات كلها.
              onPressed: () => context.read<Session>().leaveGuest(),
              child: const Text('سجّل الدخول أو أنشئ حساباً'),
            ),
          ],
        ),
      ),
    );
  }
}

/// حوار "التوقع يحتاج حساباً" — لضغطة توقّع من ضيف.
///
/// حوار لا استبدال شاشة: الضيف في منتصف تصفح المباريات، والسؤال
/// عابر — إما أن يقفز للتسجيل أو يكمل تصفحه من حيث كان.
Future<void> showGuestPredictDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('التوقّع يحتاج حساباً'),
      content: const Text(
        'سجّل خلال دقيقة وابدأ جمع النقاط — توقّعك الأول قد '
        'يساوي 100 نقطة.',
        style: TextStyle(color: Brand.textMuted, height: 1.6),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('لاحقاً'),
        ),
        FilledButton(
          onPressed: () {
            // إغلاق الحوار قبل تبديل الجذر: الحوار مسار مدفوع فوق
            // الجذر، وتبديل home لا يُسقطه (نفس فخ الخروج الموثّق
            // في main).
            Navigator.pop(dialogContext);
            dialogContext.read<Session>().leaveGuest();
          },
          child: const Text('سجّل الآن'),
        ),
      ],
    ),
  );
}
