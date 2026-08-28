// اختبارات طبقة التنسيق — كلها قواعد لغة وأرقام، لا واجهة ولا شبكة،
// فهي أرخص ما يمكن اختباره وأكثر ما يُكسر بصمت عند التعديل.
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart' as intl;
import 'package:mobile/format.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ar'));

  group('الأرقام', () {
    test('تحويل العربية-الهندية إلى غربية', () {
      expect(Fmt.digits('٦:٥٠ م'), '6:50 م');
      expect(Fmt.digits('٢٨ أغسطس ٢٠٢٦'), '28 أغسطس 2026');
    });

    test('النص بلا أرقام يبقى كما هو', () {
      expect(Fmt.digits('الجمعة'), 'الجمعة');
      expect(Fmt.digits(''), '');
    });

    test('التاريخ العربي يخرج بأرقام غربية', () {
      final when = DateTime(2026, 8, 28, 18, 50);
      expect(Fmt.date(intl.DateFormat('d MMMM yyyy', 'ar'), when),
          contains('28'));
      expect(Fmt.date(intl.DateFormat('h:mm', 'ar'), when), '6:50');
    });
  });

  group('صيغ المعدود', () {
    test('المفرد والمثنى بلا رقم', () {
      expect(Fmt.until(const Duration(days: 1)), 'بعد يوم');
      expect(Fmt.until(const Duration(days: 2)), 'بعد يومين');
    });

    test('من ٣ إلى ١٠ جمع، وما فوقها مفرد', () {
      expect(Fmt.until(const Duration(days: 3)), 'بعد 3 أيام');
      expect(Fmt.until(const Duration(days: 11)), 'بعد 11 يوماً');
    });

    test('الساعات مع الدقائق، والدقائق تُحذف حين تكون صفراً', () {
      expect(Fmt.until(const Duration(hours: 14, minutes: 34)),
          'بعد 14 ساعة و34 دقيقة');
      expect(Fmt.until(const Duration(hours: 14)), 'بعد 14 ساعة');
      expect(Fmt.until(const Duration(hours: 2)), 'بعد ساعتين');
    });

    test('تحت الساعة تظهر الثواني', () {
      expect(Fmt.until(const Duration(minutes: 12, seconds: 45)),
          'بعد 12 دقيقة و45 ثانية');
      expect(Fmt.until(const Duration(seconds: 30)), 'بعد 30 ثانية');
    });

    test('المدة المنتهية', () {
      expect(Fmt.until(Duration.zero), 'تنطلق الآن');
      expect(Fmt.until(const Duration(seconds: -5)), 'تنطلق الآن');
    });

    test('الصيغة القصيرة للشريحة', () {
      expect(Fmt.untilShort(const Duration(hours: 14, minutes: 34)), '14 س');
      expect(Fmt.untilShort(const Duration(minutes: 40)), '40 د');
    });
  });

  group('اسم الجولة', () {
    test('جولة الدوري تُترجم مع رقمها', () {
      expect(Fmt.round('Regular Season - 4'), 'الجولة 4');
      expect(Fmt.round('Regular Season - 27'), 'الجولة 27');
    });

    test('الأدوار الإقصائية', () {
      expect(Fmt.round('Quarter-finals'), 'ربع النهائي');
      expect(Fmt.round('Group Stage - 2'), 'دور المجموعات 2');
    });

    test('النص المجهول يُعرض كما هو بدل إخفائه', () {
      expect(Fmt.round('Promotion Play-offs'), 'Promotion Play-offs');
    });

    test('الفارغ يقع على البديل', () {
      expect(Fmt.round(null), 'دوري روشن');
      expect(Fmt.round('  '), 'دوري روشن');
    });
  });
}
