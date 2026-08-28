// format — كل ما يتحول إلى نص معروض للمستخدم يمر من هنا.
//
// سبب وجود الملف: قبله كان التطبيق يعرض نظامي أرقام في البطاقة
// الواحدة. التواريخ والأوقات تمر بـ locale العربية فتخرج ٦:٥٠،
// وبقية الأرقام تُطبع بـ '$n' فتخرج 14 — لأن Dart لا يعرف أنها
// "أرقام" أصلاً، هي نصوص. الفرق لا يلاحظه من كتب الشاشة ويلاحظه
// كل مستخدم.
//
// القرار: أرقام غربية في كل مكان (٠-٩ العربية-الهندية تُحوَّل بعد
// التنسيق). ولأن كل تاريخ يمر من Fmt.date، تغيير القرار لاحقاً
// سطر واحد هنا لا جولة على الشاشات.
import 'package:intl/intl.dart' as intl;

class Fmt {
  Fmt._();

  /// يحوّل الأرقام العربية-الهندية إلى غربية داخل أي نص.
  static String digits(String s) {
    if (s.isEmpty) return s;
    final buf = StringBuffer();
    for (final rune in s.runes) {
      // ٠ = 0x0660، والعشرة متتالية — فالفرق وحده يكفي للتحويل.
      if (rune >= 0x0660 && rune <= 0x0669) {
        buf.write(rune - 0x0660);
      } else {
        buf.writeCharCode(rune);
      }
    }
    return buf.toString();
  }

  /// تنسيق تاريخ عربي بأرقام غربية. استعملها بدل fmt.format() مباشرة.
  static String date(intl.DateFormat fmt, DateTime when) =>
      digits(fmt.format(when));

  // ── الجموع العربية ────────────────────────────────────────────
  //
  // العربية تصرّف المعدود على أربع صور: واحد، اثنان، ٣–١٠ جمع،
  // و١١ فأكثر مفرد منصوب. طباعة "بعد 3 يوم" أو "بعد 11 أيام" خطأ
  // يقرؤه كل عربي فوراً، ولا تمسكه أي أداة.
  static String _counted(int n, String one, String two, String few, String many) {
    if (n == 1) return one;
    if (n == 2) return two;
    if (n >= 3 && n <= 10) return '$n $few';
    return '$n $many';
  }

  // صيغة المثنى مجرورة (يومين لا يومان) لأنها تأتي دائماً بعد
  // "بعد" أو معطوفة عليها.
  static String days(int n) => _counted(n, 'يوم', 'يومين', 'أيام', 'يوماً');
  static String hours(int n) => _counted(n, 'ساعة', 'ساعتين', 'ساعات', 'ساعة');
  static String minutes(int n) => _counted(n, 'دقيقة', 'دقيقتين', 'دقائق', 'دقيقة');
  static String seconds(int n) => _counted(n, 'ثانية', 'ثانيتين', 'ثوانٍ', 'ثانية');

  /// "بعد 14 ساعة و34 دقيقة" — نص كامل لبطاقة المباراة القادمة.
  ///
  /// لماذا لا نعرض 14:34 كما كان؟ لأن الساعة الرقمية تعني وقتاً في
  /// اليوم لا مدة، فـ"بعد 14:34 ساعة" تُقرأ خطأً أول مرة ثم تُقرأ
  /// خطأً كل مرة.
  static String until(Duration left) {
    if (left.inSeconds <= 0) return 'تنطلق الآن';

    if (left.inHours >= 24) return 'بعد ${days(left.inDays)}';

    if (left.inHours >= 1) {
      final m = left.inMinutes % 60;
      final h = 'بعد ${hours(left.inHours)}';
      // الدقائق تُذكر فقط حين تضيف معلومة: "بعد 14 ساعة و34 دقيقة"
      // مفيدة، و"بعد 14 ساعة و0 دقيقة" ضجيج.
      return m == 0 ? h : '$h و${minutes(m)}';
    }

    if (left.inMinutes >= 1) {
      // تحت الساعة نُبقي الثواني: هي التي تجعل العدّاد يتحرك كل
      // ثانية، وهي اللحظة التي يقرر فيها المستخدم فعلاً.
      final s = left.inSeconds % 60;
      final m = 'بعد ${minutes(left.inMinutes)}';
      return s == 0 ? m : '$m و${seconds(s)}';
    }

    return 'بعد ${seconds(left.inSeconds)}';
  }

  /// الصيغة القصيرة لشريحة الإقفال: "14 س" / "40 د".
  static String untilShort(Duration left) {
    if (left.inSeconds <= 0) return 'الآن';
    if (left.inHours >= 1) return '${left.inHours} س';
    return '${left.inMinutes} د';
  }

  // ── اسم الجولة ────────────────────────────────────────────────
  //
  // المزوّد يرسل الجولة نصاً إنجليزياً حراً: "Regular Season - 4"،
  // "Quarter-finals"، "Group Stage - 2". كنا نعرضه كما هو داخل
  // واجهة عربية بالكامل.
  static final _roundNumber = RegExp(r'-\s*(\d+)\s*$');

  static const _stagePrefixes = {
    'regular season': 'الجولة',
    'group stage': 'دور المجموعات',
    'round of 16': 'دور الـ16',
    'quarter-finals': 'ربع النهائي',
    'semi-finals': 'نصف النهائي',
    'final': 'النهائي',
    '3rd place final': 'تحديد المركز الثالث',
  };

  /// "Regular Season - 4" → "الجولة 4". النص غير المعروف يُعاد كما
  /// هو: عرض إنجليزية نادرة أفضل من إخفاء معلومة صحيحة.
  static String round(String? raw, {String fallback = 'دوري روشن'}) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return fallback;

    final number = _roundNumber.firstMatch(value)?.group(1);
    final head = value.replaceAll(_roundNumber, '').trim().toLowerCase();
    final arabic = _stagePrefixes[head];

    if (arabic == null) return digits(value);
    return number == null ? arabic : '$arabic $number';
  }
}
