// brand — هوية "ملك التوقعات" في ملف واحد.
//
// كل لون ومقاس في التطبيق يأتي من هنا. السبب ليس الترتيب فقط:
// الهوية تفرض قواعد استعمال (الذهبي للملكية، الأخضر للصح) وهذه
// القواعد لا تُحفظ إن تناثرت أرقام الألوان في عشرين ملفاً. حين
// يكون المصدر واحداً، مخالفة القاعدة تصبح مرئية في المراجعة.
import 'package:flutter/material.dart';

class Brand {
  Brand._();

  // ---------------------------- الألوان ----------------------------

  /// ليل — خلفية التطبيق. الهوية داكنة فقط، فلا يوجد وضع فاتح.
  /// أسود حيادي (لا درجة خضراء): الثيم أسود/أبيض احترافي.
  static const night = Color(0xFF0A0A0A);

  /// سطح — البطاقات وكل ما يعلو الخلفية.
  static const surface = Color(0xFF161616);

  /// التاج — ذهبي الملكية.
  ///
  /// قاعدة الهوية: هذا اللون للتاج والنقاط والرتب **فقط**. لا يُستخدم
  /// للأزرار العادية ولا كخلفية واسعة. سبب القاعدة أن الذهبي يفقد
  /// معناه إن صار لون كل زر — نريده أن يعني "إنجاز" حين يظهر.
  static const crown = Color(0xFFF2C14E);

  /// صح — التوقع الصحيح والاختيار المؤكَّد فقط.
  /// قاعدة الهوية: لا يتشارك مع الذهبي في نفس البطاقة.
  static const correct = Color(0xFF12E07E);

  /// خطأ.
  static const wrong = Color(0xFFFF5A4E);

  /// النص الأساسي — أبيض شبه صافٍ.
  static const text = Color(0xFFF5F5F5);

  /// نص ثانوي (الشروح والتواريخ) — رمادي حيادي.
  static const textMuted = Color(0xFFA1A1A1);

  /// نص خافت (التسميات الصغيرة تحت العناصر).
  static const textFaint = Color(0xFF6B6B6B);

  /// النص فوق الذهبي أو الأخضر أو الزر الأبيض — أسود حيادي.
  static const onAccent = Color(0xFF0A0A0A);

  /// الزر الأساسي — أبيض بنص أسود. أعلى تباين ممكن على الثيم الأسود،
  /// وهو النمط الاحترافي المعتمد في التطبيقات الداكنة الحديثة.
  /// الأخضر يبقى دلالياً (توقع صحيح) والذهبي يبقى للملكية فقط.
  static const primaryButton = Color(0xFFFFFFFF);

  /// حدود البطاقات: أبيض شفاف لا لون مصمت، فيبقى الحد ناعماً فوق
  /// أي سطح ولا يتحول لخط صلب.
  static const border = Color(0x14FFFFFF); // 8%
  static const borderSoft = Color(0x12FFFFFF); // 7%

  /// خلفية العناصر المحايدة (الشرائح غير المختارة، الأفاتار).
  static const fill = Color(0x0FFFFFFF); // 6%
  static const fillStrong = Color(0x24FFFFFF); // 14%

  /// نسخ شفافة من لوني الإشارة — للخلفيات الخفيفة خلف النص الملون.
  static Color crownWash(double opacity) => crown.withValues(alpha: opacity);
  static Color correctWash(double opacity) => correct.withValues(alpha: opacity);

  // ---------------------------- الخطوط ----------------------------

  /// العناوين والأرقام البارزة.
  static const displayFont = 'Readex Pro';

  /// نصوص الواجهة.
  static const bodyFont = 'IBM Plex Sans Arabic';

  /// أرقام جدولية: كل رقم بنفس العرض.
  ///
  /// الهوية تفرضها على النقاط والنتائج والدقائق، والسبب عملي: في
  /// قائمة الصدارة تتغير الأرقام كل جولة، ومع الأرقام المتناسبة
  /// (الافتراضية) يتحرك عمود النقاط يميناً ويساراً مع كل تحديث.
  /// الجدولية تثبّته.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  // ---------------------------- المقاسات ----------------------------

  static const radiusCard = 20.0;
  static const radiusCardLarge = 24.0;
  static const radiusChip = 999.0;
  static const radiusSmall = 12.0;
}

/// السمة المشتقة من الهوية.
///
/// نبني ColorScheme يدوياً بدل fromSeed: البذرة تشتق درجات متناسقة
/// لكنها تخترع ألواناً لم يخترها المصمم. الهوية هنا محددة سلفاً،
/// فالتقيد بها أهم من التناسق المولَّد.
ThemeData buildBrandTheme() {
  const scheme = ColorScheme.dark(
    primary: Brand.primaryButton,
    onPrimary: Brand.onAccent,
    secondary: Brand.correct,
    onSecondary: Brand.onAccent,
    error: Brand.wrong,
    onError: Brand.onAccent,
    surface: Brand.night,
    onSurface: Brand.text,
    surfaceContainerHighest: Brand.surface,
    onSurfaceVariant: Brand.textMuted,
    outline: Brand.textFaint,
    outlineVariant: Brand.border,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Brand.night,
    fontFamily: Brand.bodyFont,

    appBarTheme: const AppBarTheme(
      backgroundColor: Brand.night,
      surfaceTintColor: Colors.transparent, // بلا تلوّن عند التمرير
      foregroundColor: Brand.text,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: Brand.displayFont,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Brand.text,
      ),
    ),

    cardTheme: CardThemeData(
      color: Brand.surface,
      elevation: 0, // الهوية تفصل بالحدود لا بالظلال
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Brand.radiusCard),
        side: const BorderSide(color: Brand.borderSoft),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Brand.surface,
      hintStyle: const TextStyle(color: Brand.textFaint),
      labelStyle: const TextStyle(color: Brand.textMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Brand.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Brand.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        // الحد المركَّز أبيض: التركيز حالة تفاعل عادية، والألوان
        // الدلالية (الأخضر/الذهبي) محجوزة لمعانيها.
        borderSide: const BorderSide(color: Brand.text, width: 1.5),
      ),
    ),

    // الزر الأساسي أبيض بنص أسود — أعلى تباين على الثيم الأسود.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Brand.primaryButton,
        foregroundColor: Brand.onAccent,
        disabledBackgroundColor: Brand.fillStrong,
        disabledForegroundColor: Brand.textFaint,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: const TextStyle(
          fontFamily: Brand.displayFont,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Brand.textMuted),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Brand.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Brand.fillStrong,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: Brand.bodyFont,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? Brand.text
              : Brand.textMuted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected)
              ? Brand.text
              : Brand.textMuted,
        ),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: Brand.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Brand.radiusCardLarge),
        side: const BorderSide(color: Brand.border),
      ),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Brand.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),

    datePickerTheme: DatePickerThemeData(
      backgroundColor: Brand.surface,
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: Brand.surface,
      headerForegroundColor: Brand.text,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Brand.radiusCardLarge),
        side: const BorderSide(color: Brand.border),
      ),
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Brand.text,
    ),

    textTheme: const TextTheme(
      headlineLarge: TextStyle(
          fontFamily: Brand.displayFont,
          fontWeight: FontWeight.w700,
          color: Brand.text),
      headlineMedium: TextStyle(
          fontFamily: Brand.displayFont,
          fontWeight: FontWeight.w700,
          color: Brand.text),
      headlineSmall: TextStyle(
          fontFamily: Brand.displayFont,
          fontWeight: FontWeight.w700,
          color: Brand.text),
      titleLarge: TextStyle(
          fontFamily: Brand.displayFont,
          fontWeight: FontWeight.w700,
          color: Brand.text),
      titleMedium: TextStyle(
          fontFamily: Brand.displayFont,
          fontWeight: FontWeight.w600,
          color: Brand.text),
      titleSmall: TextStyle(
          fontFamily: Brand.displayFont,
          fontWeight: FontWeight.w600,
          color: Brand.text),
      bodyLarge: TextStyle(color: Brand.text),
      bodyMedium: TextStyle(color: Brand.text),
      bodySmall: TextStyle(color: Brand.textMuted),
      labelLarge: TextStyle(color: Brand.text),
      labelMedium: TextStyle(color: Brand.textMuted),
      labelSmall: TextStyle(color: Brand.textFaint),
    ),
  );
}
