// brand_mark — علامة "ملك التوقعات": درع الصدارة.
//
// درع مصمت يحمل ثلاث درجات ترتيب محفورة سلباً، والدرجة الوسطى —
// الأعلى — يعلوها تاج.
//
// لماذا CustomPainter وليس ملف SVG؟ الشكل أربعة مسارات بسيطة، ورسمه
// مباشرة يوفّر حزمة flutter_svg كاملة ويجعل تطبيق قاعدتين من قواعد
// الهوية أمراً تلقائياً بدل أن يكون تذكّراً بشرياً:
//
// 1. "الحفر بلون الخلفية": الدرجات والتاج تُرسم بلون السطح الذي
//    يجلس عليه الدرع — لا لون ثالث داخل العلامة أبداً. هنا يصل
//    اللون كوسيط `carve`، فمن يستخدم العلامة مجبر على تحديده.
//
// 2. "النسخة المبسّطة للصغير": تحت ٦٤ بكسل تُحذف الدرجات ويبقى
//    الدرع والتاج، لأن الدرجات تتحول إلى خروق غير مقروءة. الشرط
//    مكتوب في الرسّام نفسه فلا يمكن نسيانه.
//
// الإحداثيات كلها في مربع 512×512 كما في ملف الهوية، ونقيسها للحجم
// المطلوب وقت الرسم.
import 'package:flutter/material.dart';

import '../brand.dart';

class BrandMark extends StatelessWidget {
  /// ضلع المربع بالنقاط.
  final double size;

  /// لون الدرع.
  final Color color;

  /// لون الحفر — يجب أن يساوي لون السطح خلف العلامة.
  final Color carve;

  const BrandMark({
    super.key,
    this.size = 48,
    this.color = Brand.crown,
    this.carve = Brand.night,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _ShieldPainter(color: color, carve: carve, side: size),
      ),
    );
  }
}

class _ShieldPainter extends CustomPainter {
  final Color color;
  final Color carve;
  final double side;

  _ShieldPainter({
    required this.color,
    required this.carve,
    required this.side,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 512; // معامل التحجيم من مربع الهوية

    final shield = Path()
      ..moveTo(256 * s, 40 * s)
      ..relativeLineTo(192 * s, 68 * s)
      ..lineTo(448 * s, 276 * s)
      ..cubicTo(448 * s, 356 * s, 360 * s, 428 * s, 256 * s, 468 * s)
      ..cubicTo(152 * s, 428 * s, 64 * s, 356 * s, 64 * s, 276 * s)
      ..lineTo(64 * s, 108 * s)
      ..close();

    canvas.drawPath(shield, Paint()..color = color);

    final carvePaint = Paint()..color = carve;

    // درجات الترتيب: يمين ٣، وسط ١ (الأعلى)، يسار ٢.
    // تُحذف في الأحجام الصغيرة — انظر الشرح أعلى الملف.
    if (side >= 64) {
      const steps = [
        [140.0, 300.0, 58.0, 104.0],
        [227.0, 250.0, 58.0, 154.0],
        [314.0, 284.0, 58.0, 120.0],
      ];
      for (final r in steps) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(r[0] * s, r[1] * s, r[2] * s, r[3] * s),
            Radius.circular(10 * s),
          ),
          carvePaint,
        );
      }
    }

    final crown = Path()
      ..moveTo(212 * s, 236 * s)
      ..lineTo(212 * s, 196 * s)
      ..lineTo(234 * s, 210 * s)
      ..lineTo(256 * s, 186 * s)
      ..lineTo(278 * s, 210 * s)
      ..lineTo(300 * s, 196 * s)
      ..lineTo(300 * s, 236 * s)
      ..close();

    canvas.drawPath(crown, carvePaint);
  }

  @override
  bool shouldRepaint(_ShieldPainter old) =>
      old.color != color || old.carve != carve || old.side != side;
}

/// العلامة داخل مربع بحواف مستديرة — أيقونة التطبيق كما تظهر داخل
/// الواجهة (شاشة الدخول مثلاً). الدرع ذهبي والحفر بلون المربع.
class BrandBadge extends StatelessWidget {
  final double size;

  /// أصغر مربع يبقى معه الدرع كاملاً بدرجاته.
  ///
  /// الدرع داخل المربع يشغل 0.68 من ضلعه، وعتبة الهوية للنسخة
  /// الكاملة 64، فالمربع يحتاج 64 ÷ 0.68 ≈ 94. أي شارة أصغر ستعرض
  /// النسخة المبسّطة تلقائياً — وهو السلوك الصحيح، لكن الشاشات التي
  /// تكون فيها الشارة هي البطل (الدخول، الإقلاع) يجب أن تتجاوزه.
  static const fullMarkSize = 94.0;

  const BrandBadge({super.key, this.size = fullMarkSize});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Brand.surface,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: Brand.crownWash(0.22)),
      ),
      alignment: Alignment.center,
      child: BrandMark(
        size: size * 0.68,
        color: Brand.crown,
        carve: Brand.surface, // الحفر بلون السطح الذي يجلس عليه الدرع
      ),
    );
  }
}
