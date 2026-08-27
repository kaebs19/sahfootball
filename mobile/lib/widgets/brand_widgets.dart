// مكونات الهوية المشتركة.
//
// وُضعت هنا لأنها تتكرر في أكثر من شاشة، ولأن كل واحدة منها تجسّد
// قاعدة من قواعد الهوية — فمركزتها تعني أن القاعدة تُطبّق مرة واحدة
// بدل أن تُعاد كتابتها (وتُخالف) في كل شاشة.
import 'package:flutter/material.dart';

import '../brand.dart';

/// شريحة بيضاوية. النغمة تحدد المعنى:
/// - [BrandTone.neutral] معلومة عادية (موعد، جولة، عدّاد).
/// - [BrandTone.crown] نقاط أو رتبة — ملكية.
/// - [BrandTone.correct] توقع صحيح أو اختيار مؤكَّد.
enum BrandTone { neutral, crown, correct, wrong }

class BrandChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final BrandTone tone;

  /// شريحة مصمتة (اللون كخلفية كاملة) — للحالة المختارة في المرشّحات.
  final bool solid;

  const BrandChip({
    super.key,
    required this.label,
    this.icon,
    this.tone = BrandTone.neutral,
    this.solid = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = switch (tone) {
      BrandTone.neutral => Brand.textMuted,
      BrandTone.crown => Brand.crown,
      BrandTone.correct => Brand.correct,
      BrandTone.wrong => Brand.wrong,
    };

    final Color bg, fg;
    Border? border;
    if (solid && tone != BrandTone.neutral) {
      bg = accent;
      fg = Brand.onAccent;
    } else if (tone == BrandTone.neutral) {
      bg = Brand.fill;
      fg = Brand.textMuted;
    } else {
      // النغمة الملونة الخفيفة: خلفية شفافة من نفس اللون مع حد أوضح
      // قليلاً — هكذا تظهر في ملف الهوية.
      bg = accent.withValues(alpha: 0.13);
      fg = accent;
      border = Border.all(color: accent.withValues(alpha: 0.3));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        border: border,
        borderRadius: BorderRadius.circular(Brand.radiusChip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: Brand.bodyFont,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
              fontFeatures: Brand.tabular,
            ),
          ),
        ],
      ),
    );
  }
}

/// رقم بارز (نقاط، نتيجة، عدّاد) — بخط العناوين وأرقام جدولية.
class BrandNumber extends StatelessWidget {
  final String value;
  final double size;
  final Color color;

  const BrandNumber(
    this.value, {
    super.key,
    this.size = 24,
    this.color = Brand.text,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      style: TextStyle(
        fontFamily: Brand.displayFont,
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color,
        height: 1.1,
        fontFeatures: Brand.tabular,
      ),
    );
  }
}

/// عنوان قسم صغير بالذهبي، بنمط "٠١ — العنوان" المستعمل في الهوية.
class BrandSectionLabel extends StatelessWidget {
  final String text;
  const BrandSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: Brand.displayFont,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: Brand.crown,
        letterSpacing: 0.2,
      ),
    );
  }
}

/// حالة فارغة أو خطأ، بزر إعادة محاولة اختياري.
///
/// ملفوفة في ListView داخل RefreshIndicator كي تعمل إيماءة السحب
/// للتحديث رغم أن المحتوى لا يملأ الشاشة.
class BrandEmpty extends StatelessWidget {
  final IconData icon;
  final String message;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onRetry;

  const BrandEmpty({
    super.key,
    required this.icon,
    required this.message,
    this.onRefresh,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final content = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 40),
      children: [
        const SizedBox(height: 110),
        Icon(icon, size: 44, color: Brand.textFaint),
        const SizedBox(height: 14),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Brand.textMuted, height: 1.6),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 18),
          Center(
            child: OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: Brand.text,
                side: const BorderSide(color: Brand.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Brand.radiusChip),
                ),
              ),
              child: const Text('إعادة المحاولة'),
            ),
          ),
        ],
      ],
    );

    if (onRefresh == null) return content;
    return RefreshIndicator(
      onRefresh: onRefresh!,
      color: Brand.crown,
      backgroundColor: Brand.surface,
      child: content,
    );
  }
}

/// بطاقة الهوية: سطح داكن، حد رفيع، بلا ظل.
class BrandCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// حد ذهبي خفيف — للبطاقات التي تحمل معنى ملكياً (النقاط، الرتبة).
  final bool royal;

  const BrandCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.royal = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Brand.radiusCard);
    return Container(
      decoration: BoxDecoration(
        color: Brand.surface,
        borderRadius: radius,
        border: Border.all(
          color: royal ? Brand.crownWash(0.16) : Brand.borderSoft,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
