// goal_splash — أنميشن الافتتاح: تمريرة، تسديدة، هدف، احتفال، ثم
// تسليم الشاشة للتطبيق.
//
// مبني على المواصفة في design/goal-splash.json — وهي وثيقة تصميم
// (مشاهد وتوقيتات وألوان) لا ملف Lottie، فلا شيء يُشغَّل منها
// مباشرة: الرسم كله هنا بـ CustomPainter.
//
// لماذا رسم أصلي بلا حزمة؟ نفس منطق brand_mark وأيقونة جوجل: حزمة
// lottie تجرّ محرك تشغيل كاملاً (~مئات الكيلوبايتات) وملف JSON
// ثقيلاً لأجل لقطة واحدة، والرسم المباشر يجعل ألوان الهوية مرتبطة
// بـ Brand حرفياً — فتغيير الذهبي في ملف الهوية يغيّر الأنميشن معه،
// ولا يبقى لوناً مجمّداً داخل أصل خارجي.
//
// انحرافان مقصودان عن المواصفة، وكلاهما لحماية الهوية:
//   • لوحة المواصفة الخضراء (#0d3f26) وخط Cairo لم يُعتمدا: الخلفية
//     تبقى ليل الهوية الحيادي وخطها Readex Pro. الملعب وحده يأخذ
//     أثراً أخضر شديد العتمة (#101710) — عنصر مشهد لا سطح واجهة —
//     ويُقرأ كعشب بخطوط الجزّ أكثر مما يُقرأ باللون.
//   • مدة المواصفة 5 ثوانٍ صارت 2.4: خمس ثوانٍ تُدفع عند كل إقلاع،
//     والمشاهد الخمسة محفوظة بنِسَبها كما تنص الملاحظة "كل الحركة
//     على محور زمني واحد فتقصيره يعيد التوقيت دون قطع".
//
// وتُحترم إعدادات تقليل الحركة في النظام: من فعّلها لا يرى شيئاً.
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../brand.dart';
import 'brand_mark.dart';

// ── المحور الزمني (ثوانٍ) — نِسَب المواصفة مضغوطة ───────────────
const double _tShot = 0.45; // نهاية التمرير / بداية التسديد
const double _tGoal = 0.85; // لحظة الاصطدام بالشبكة
const double _tCeleb = 1.25; // بداية الاحتفال
const double _tSettle = 1.80; // بداية التسليم للتطبيق
const double _tEnd = 2.40;

// ── مسرح الرسم بأبعاد المواصفة (1080×1920) ─────────────────────
// كل الإحداثيات أدناه بوحداته، وتُقاس للشاشة وقت الرسم بأسلوب
// cover — فالتكوين واحد على كل الأجهزة.
const double _stageW = 1080;
const double _stageH = 1920;
const double _ground = 1180; // خط الأرض
const double _ballR = 26;

/// نقطة اصطدام الكرة بالشبكة — مركز كل ما يقع عند الهدف
/// (الانتفاخ، الوميض، الرشّ).
const Offset _impact = Offset(300, 872);

/// مرمى على اليسار والحركة من اليمين إليه — اتجاه القراءة العربية،
/// وهو ما تنص عليه المواصفة (pan: يمين إلى يسار).
///
/// موضعه ليس على الحافة: القصّ بأسلوب cover يأكل نحو 100 وحدة من
/// كل جانب على شاشة 19.5:9، فالقائم عند x=70 كان يخرج من الكادر
/// في لقطة الهدف نفسها.
const Rect _goalMouth = Rect.fromLTRB(150, 780, 610, _ground);

double _seg(double t, double a, double b) =>
    ((t - a) / (b - a)).clamp(0.0, 1.0);

class GoalSplash extends StatefulWidget {
  final Widget child;

  const GoalSplash({super.key, required this.child});

  @override
  State<GoalSplash> createState() => _GoalSplashState();
}

class _GoalSplashState extends State<GoalSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (_tEnd * 1000).round()),
  );

  /// الكونفيتي يُولَّد مرة واحدة ببذرة ثابتة: الرسّام يُستدعى ستين
  /// مرة في الثانية، وتوليد عشوائي داخله يجعل كل قصاصة تقفز مكاناً
  /// جديداً في كل إطار.
  late final List<_Confetti> _confetti = _makeConfetti();

  bool _done = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    // من طلب تقليل الحركة من إعدادات هاتفه لا يُستثنى: الأنميشن
    // زينة، وتجاهل الإعداد في الزينة تحديداً هو أسوأ أنواع تجاهله.
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduced) {
      _done = true;
      return;
    }

    _c.forward().whenComplete(() {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// التخطي باللمس: من رأى الأنميشن مرة لا يجوز حبسه فيه مرة أخرى.
  void _skip() {
    if (_c.value >= 1) return;
    _c.animateTo(1, duration: const Duration(milliseconds: 260));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (!_done)
          Positioned.fill(
            child: GestureDetector(
              onTap: _skip,
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => _frame(_c.value * _tEnd),
              ),
            ),
          ),
      ],
    );
  }

  Widget _frame(double t) {
    // التلاشي الأخير يكشف ما تحته تدريجياً — والتطبيق يكون قد بنى
    // شاشته وأطلق طلباته خلف الأنميشن، فالثواني ليست انتظاراً ضائعاً.
    final fade = 1 - _seg(t, _tEnd - 0.5, _tEnd);

    return Opacity(
      opacity: fade,
      // Material شفافة ضرورية لا زينة: نصّ بلا سلف Material يرث
      // النمط الاحتياطي في Flutter — أصفر بخط سفلي — فكان «هدف!»
      // يظهر وتحته شريط أصفر غريب.
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _scene(t),
            // ستارة تعتيم تحت العلامة: بدونها يجلس الدرع على العارضة
            // والاسم على الحارس، فيتزاحم النصّ مع المشهد ولا يُقرأ
            // أيّهما. تبدأ مع صعود العلامة لا قبله — المشهد يجب أن
            // يُرى كاملاً في لحظة الاحتفال أولاً.
            IgnorePointer(
              child: ColoredBox(
                color: Brand.night.withValues(
                  alpha: 0.74 * _seg(t, _tCeleb + 0.05, _tSettle),
                ),
              ),
            ),
            _goalWord(t),
            _brandReveal(t),
          ],
        ),
      ),
    );
  }

  /// المشهد المرسوم، ويُشوَّش في المقطع الأخير فقط.
  ///
  /// التشويش من المواصفة («تعتيم وتشويش المشهد» في مشهد الدخول)،
  /// ومشروط بأن يكون فعّالاً: ImageFiltered تكلّف تمريرة رسم إضافية
  /// في كل إطار، فتُركَّب في الستّمئة مللي ثانية الأخيرة وحدها بدل
  /// أن تُحمَّل على الأنميشن كله بلا أثر يُرى.
  Widget _scene(double t) {
    final scene = RepaintBoundary(
      child: CustomPaint(
        painter: _ScenePainter(t: t, confetti: _confetti),
      ),
    );
    final sigma = 7 * _seg(t, _tSettle, _tEnd);
    if (sigma < 0.1) return scene;
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: scene,
    );
  }

  /// «هدف!» — نصّ ويدجت لا رسماً في الكانفس: تشكيل الحروف العربية
  /// ووصلها من عمل محرّك النصوص، ورسمها يدوياً يعني حروفاً منفصلة.
  Widget _goalWord(double t) {
    final inP = _seg(t, _tGoal, _tGoal + 0.20);
    final outP = _seg(t, _tCeleb + 0.30, _tCeleb + 0.55);
    if (inP == 0 || outP == 1) return const SizedBox.shrink();

    // تجاوز بسيط في الحجم ثم استقرار — الضربة تصل قبل أن تهدأ.
    final scale = Curves.easeOutBack.transform(inP) * (1 - outP * 0.12);

    return IgnorePointer(
      child: Center(
        child: Opacity(
          opacity: (inP * (1 - outP)).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, -MediaQuery.sizeOf(context).height * 0.19),
            child: Transform.scale(
              scale: scale,
              child: const Text(
                'هدف!',
                style: TextStyle(
                  fontFamily: Brand.displayFont,
                  fontSize: 62,
                  fontWeight: FontWeight.w700,
                  color: Brand.text,
                  letterSpacing: 1,
                  shadows: [
                    Shadow(color: Brand.crown, blurRadius: 38),
                    Shadow(color: Brand.night, blurRadius: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// العلامة والاسم — يصعدان بعد الاحتفال ويبقيان حتى التسليم.
  /// BrandMark نفسه لا نسخة مرسومة ثانية: قواعد الهوية (الحفر بلون
  /// السطح، النسخة المبسّطة للصغير) تعيش فيه، ونسخُه هنا يعني
  /// نسخَها معه ثم انحرافها عند أول تعديل.
  Widget _brandReveal(double t) {
    final p = Curves.easeOutCubic.transform(_seg(t, _tCeleb + 0.10, _tSettle));
    if (p == 0) return const SizedBox.shrink();
    final tagP = _seg(t, _tCeleb + 0.34, _tSettle + 0.15);

    return IgnorePointer(
      child: Center(
        child: Transform.translate(
          offset: Offset(0, (1 - p) * 46),
          child: Opacity(
            opacity: p,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: 0.82 + p * 0.18,
                  child: const BrandBadge(size: 104),
                ),
                const SizedBox(height: 20),
                const Text(
                  'ملك التوقعات',
                  style: TextStyle(
                    fontFamily: Brand.displayFont,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: Brand.text,
                  ),
                ),
                const SizedBox(height: 8),
                Opacity(
                  opacity: tagP,
                  child: const Text(
                    // شعار المواصفة نفسه (brand.tagline).
                    'أنت ملك التوقعات',
                    style: TextStyle(color: Brand.crown, fontSize: 14.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// خلفية شاشة الدخول — الإطار الأخير من الافتتاح، مجمّداً.
///
/// هذه هي النسخة الأولى في المواصفة: «تشتغل مرة واحدة وتثبت على
/// شاشة تسجيل الدخول». الافتتاح يتلاشى خلال نصف ثانية إلى هذه
/// الصورة — كلاهما مشهد داكن مشوّش، فيُقرأ الانتقال هدوءاً بعد
/// الحركة. وليس تطابقاً بالإطار: الخلفية أوسع تأطيراً وبلا لاعبين،
/// لأن ما يخدم لقطةَ هدفٍ لا يخدم خلفيةَ نموذجٍ يُقرأ ويُكتب فيه.
///
/// ولماذا لا تتكرر الحركة خلف النموذج (النسخة الثانية في المواصفة)؟
/// لأن الشاشة تحمل تسعة عناصر تفاعلية، وفي الحركة وميض أبيض ملء
/// الشاشة عند الهدف يقع كل بضع ثوانٍ بينما المستخدم يكتب كلمة مروره؛
/// ولأن نهاية الأنميشن هي بعينها ترويسة هذه الشاشة (درع + اسم +
/// شعار) فيتكرر الدرع مرتين. الهدوء هنا قرار لا كسل.
///
/// **الكلفة**: المشهد يُرسم ويُشوَّش مرة واحدة داخل RepaintBoundary،
/// والحياة الوحيدة فيه زحف Ken Burns يُطبَّق كتحويل فوق تلك الطبقة
/// المخزّنة — فلا إعادة رسم ولا إعادة تشويش في كل إطار. ومن فعّل
/// تقليل الحركة يحصل على صورة ساكنة تماماً.
class GoalBackdrop extends StatefulWidget {
  const GoalBackdrop({super.key});

  @override
  State<GoalBackdrop> createState() => _GoalBackdropState();
}

class _GoalBackdropState extends State<GoalBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    // بطيء عمداً: الزحف الذي يُلاحَظ يزعج، والذي يُحسّ ولا يُلاحَظ
    // هو ما يجعل الشاشة تبدو حيّة.
    duration: const Duration(seconds: 22),
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return;
    _drift.repeat(reverse: true);
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // t = _tEnd يعطي المشهد المستقرّ وحده: الكرة واللمعان والرشّ
    // والكونفيتي كلها مشروطة بزمنها وقد انتهت، فيبقى الملعب والمرمى
    // والشبكة والجمهور. لا حاجة لعَلَم "خلفية" — المحور الزمني نفسه
    // يحذف العابر.
    // ImageFilter.blur ليست const، فالمشهد يُبنى هنا لا كثابت —
    // ولا فرق في الكلفة: AnimatedBuilder يستلمه عبر child فلا
    // يُعاد بناؤه مع كل إطار من الزحف.
    final scene = ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
      child: const RepaintBoundary(
        child: CustomPaint(
          painter: _ScenePainter(
            t: _tEnd,
            confetti: [],
            actors: false,
            camera: (scale: 1.05, focus: Offset(430, 900)),
            vignetteExtra: 0.05,
          ),
          isComplex: true,
          willChange: false,
        ),
      ),
    );

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _drift,
            builder: (context, child) {
              final p = Curves.easeInOut.transform(_drift.value);
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..scaleByDouble(1.06 + 0.12 * p, 1.06 + 0.12 * p, 1, 1)
                  ..translateByDouble(-16.0 * p, 26.0 * p, 0, 1),
                child: child,
              );
            },
            child: scene,
          ),
          // هالة كشّاف خلف العلامة — تنبض ببطء مع نفس المؤقّت.
          // ذهبية رغم قاعدة "الذهبي للتاج والنقاط فقط": هي تضيء
          // التاج نفسه لا تزيّن عنصراً آخر، وشدّتها بين 6٪ و11٪ —
          // إحساس عمق لا لون. وطبقة تدرّج واحدة في الإطار، فلا
          // يُعاد رسم المشهد من أجلها.
          AnimatedBuilder(
            animation: _drift,
            builder: (context, _) {
              final glow =
                  0.06 + 0.05 * Curves.easeInOut.transform(_drift.value);
              return DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.58),
                    radius: 0.9,
                    colors: [
                      Brand.crown.withValues(alpha: glow),
                      Brand.crown.withValues(alpha: glow * 0.3),
                      const Color(0x00000000),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              );
            },
          ),
          // تدرّج القراءة: الحقول والأزرار مصمتة أصلاً، لكن العنوان
          // والشعار و«تذكرني» والروابط نصوص عارية — وهذا ما يضمن
          // تباينها على أي جزء من الصورة.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x4A0A0A0A),
                  Color(0x8F0A0A0A),
                  Color(0xD60A0A0A),
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── الرسم ───────────────────────────

class _Confetti {
  final double x, delay, vy, sway, size, rot, spin;
  final Color color;
  const _Confetti(
    this.x,
    this.delay,
    this.vy,
    this.sway,
    this.size,
    this.rot,
    this.spin,
    this.color,
  );
}

List<_Confetti> _makeConfetti() {
  // بذرة ثابتة: نريد عشوائية الشكل لا عشوائية النتيجة — نفس
  // الافتتاح في كل مرة، ولقطة الشاشة تُعاد كما هي عند المراجعة.
  final rnd = math.Random(7);
  const colors = [Brand.crown, Brand.text, Brand.crown, Color(0xFFE0B25A)];
  return List.generate(44, (i) {
    return _Confetti(
      rnd.nextDouble() * _stageW,
      rnd.nextDouble() * 0.42,
      620 + rnd.nextDouble() * 520,
      40 + rnd.nextDouble() * 90,
      9 + rnd.nextDouble() * 13,
      rnd.nextDouble() * math.pi,
      (rnd.nextDouble() - 0.5) * 9,
      colors[i % colors.length],
    );
  });
}

class _ScenePainter extends CustomPainter {
  final double t;
  final List<_Confetti> confetti;

  /// هل يُرسم اللاعبون؟ الخلفية الساكنة تطفئهم: الحارس الملقى في
  /// الشبكة يصلح لقطةَ هدفٍ لا خلفيةَ شاشة دخول، ومشوّشاً يصير
  /// كتلة داكنة لا تُفهم. المرمى الخالي أنظف وأقرب لما تفعله
  /// تطبيقات الرياضة المعروفة.
  final bool actors;

  /// تأطير ثابت يتجاوز الكاميرا المشتقّة من الزمن.
  ///
  /// كاميرا المحور الزمني كلها لقطات حركة قريبة (تصل 1.32 عند
  /// الهدف)، وأيّ منها كخلفية ساكنة يُظهر قائماً وطرف شبكة فيُقرأ
  /// خطوطاً لا ملعباً. الخلفية تحتاج لقطة تأسيسية أوسع.
  final ({double scale, Offset focus})? camera;

  /// تجاوز شدّة تعتيم الأطراف. المشتقّة من الزمن (0.42 عند النهاية)
  /// مضبوطة ليُقرأ اسم العلامة فوقها في الافتتاح؛ والخلفية الساكنة
  /// تريد أن تُرى فتمرّر قيمة أخفّ.
  final double? vignetteExtra;

  const _ScenePainter({
    required this.t,
    required this.confetti,
    this.actors = true,
    this.camera,
    this.vignetteExtra,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ملء الشاشة بأسلوب cover: التكوين مصمم على مسرح واحد، والقياس
    // بالأكبر من النسبتين يمنع ظهور فراغ على أي نسبة شاشة.
    final k = math.max(size.width / _stageW, size.height / _stageH);

    canvas.drawRect(Offset.zero & size, Paint()..color = Brand.night);

    canvas.save();
    canvas.translate(
      (size.width - _stageW * k) / 2,
      (size.height - _stageH * k) / 2,
    );
    canvas.scale(k);
    canvas.clipRect(const Rect.fromLTWH(0, 0, _stageW, _stageH));

    _applyCamera(canvas);

    _drawSky(canvas);
    _drawPitch(canvas);
    _drawGoal(canvas);
    if (actors) {
      _drawKeeper(canvas);
      _drawStriker(canvas);
    }
    _drawBall(canvas);
    _drawImpact(canvas);
    _drawConfetti(canvas);
    _drawVignette(canvas);

    canvas.restore(); // الكاميرا
    canvas.restore(); // المسرح
  }

  /// الكاميرا: تقريب متدرّج عبر المشاهد، واهتزاز يتلاشى عند الهدف.
  /// المشاهد تتسلّم بعضها بلا قطع لأن كل مقطع يبدأ من حيث انتهى
  /// سابقه — وهي شرط المواصفة الصريح.
  void _applyCamera(Canvas canvas) {
    double scale;
    Offset focus;

    final fixed = camera;
    if (fixed != null) {
      canvas.save();
      canvas.translate(_stageW / 2, _stageH / 2);
      canvas.scale(fixed.scale);
      canvas.translate(-fixed.focus.dx, -fixed.focus.dy);
      return;
    }

    if (t < _tShot) {
      final p = Curves.easeInOut.transform(_seg(t, 0, _tShot));
      scale = 1.06 + 0.06 * p;
      focus = Offset.lerp(const Offset(780, 1010), const Offset(720, 1000), p)!;
    } else if (t < _tGoal) {
      final p = Curves.easeIn.transform(_seg(t, _tShot, _tGoal));
      scale = 1.12 + 0.20 * p;
      focus = Offset.lerp(const Offset(720, 1000), const Offset(430, 950), p)!;
    } else if (t < _tCeleb) {
      final p = Curves.easeOut.transform(_seg(t, _tGoal, _tCeleb));
      scale = 1.32 - 0.10 * p;
      focus = Offset.lerp(const Offset(430, 950), const Offset(470, 945), p)!;
    } else if (t < _tSettle) {
      final p = Curves.easeInOut.transform(_seg(t, _tCeleb, _tSettle));
      scale = 1.22 - 0.14 * p;
      focus = Offset.lerp(const Offset(470, 945), const Offset(540, 960), p)!;
    } else {
      // ken-burns: زحف بطيء يبقي الصورة حيّة تحت شاشة الدخول.
      final p = _seg(t, _tSettle, _tEnd);
      scale = 1.08 + 0.07 * p;
      focus = Offset.lerp(const Offset(540, 960), const Offset(540, 900), p)!;
    }

    var shake = Offset.zero;
    if (t >= _tGoal) {
      final dt = t - _tGoal;
      final a = 30 * math.exp(-13 * dt);
      shake = Offset(a * math.sin(64 * dt), a * 0.55 * math.cos(78 * dt));
    }

    canvas.save();
    canvas.translate(_stageW / 2 + shake.dx, _stageH / 2 + shake.dy);
    canvas.scale(scale);
    canvas.translate(-focus.dx, -focus.dy);
  }

  void _drawSky(Canvas canvas) {
    final rect = const Rect.fromLTWH(0, 0, _stageW, _ground);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF060606), Color(0xFF0C0C0C), Color(0xFF121412)],
        ).createShader(rect),
    );

    // جمهور مُلمَّح إليه: نقاط باهتة فوق خط الأرض تتموّج قليلاً عند
    // الاحتفال. لا وجوه ولا شعارات — كما تشترط ملاحظات المواصفة.
    final crowdP = _seg(t, _tGoal, _tCeleb);
    final rnd = math.Random(21);
    final dot = Paint();
    for (var i = 0; i < 150; i++) {
      final x = rnd.nextDouble() * _stageW;
      final y = 600 + rnd.nextDouble() * 300;
      final bounce = math.sin(t * 9 + i) * 7 * crowdP;
      dot.color = Brand.text.withValues(alpha: 0.05 + rnd.nextDouble() * 0.07);
      canvas.drawCircle(Offset(x, y + bounce), 5 + rnd.nextDouble() * 4, dot);
    }
  }

  void _drawPitch(Canvas canvas) {
    const rect = Rect.fromLTRB(0, _ground, _stageW, _stageH);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          // أخضر شديد العتمة يكاد يُقرأ أسود — انظر شرح الانحراف
          // أعلى الملف. سطح التطبيق نفسه يبقى Brand.night حرفياً.
          colors: [Color(0xFF101710), Color(0xFF0B110C), Color(0xFF070A07)],
        ).createShader(rect),
    );

    // خطوط الجزّ: هي ما يجعل المستطيل يُقرأ ملعباً، لا اللون.
    final mow = Paint()..color = Brand.text.withValues(alpha: 0.022);
    for (var i = 0; i < 7; i++) {
      canvas.drawRect(
        Rect.fromLTWH(i * 170.0, _ground, 85, _stageH - _ground),
        mow,
      );
    }

    canvas.drawLine(
      const Offset(0, _ground),
      const Offset(_stageW, _ground),
      Paint()
        ..color = Brand.text.withValues(alpha: 0.11)
        ..strokeWidth = 2,
    );

    // قوس منطقة الجزاء أمام المرمى.
    canvas.drawArc(
      Rect.fromCenter(
        center: const Offset(150, _ground + 120),
        width: 700,
        height: 300,
      ),
      -math.pi * 0.42,
      math.pi * 0.84,
      false,
      Paint()
        ..color = Brand.text.withValues(alpha: 0.05)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  void _drawGoal(Canvas canvas) {
    // عمق المرمى نحو اليسار: الإطار الخلفي أصغر ومزاح، والشبكة
    // تُنسج بينهما فيُقرأ المرمى مجسّماً بلا رسم ثلاثي حقيقي.
    final back = Rect.fromLTRB(
      _goalMouth.left + 54,
      _goalMouth.top + 40,
      _goalMouth.right - 96,
      _goalMouth.bottom - 26,
    );

    canvas.drawRect(back, Paint()..color = const Color(0xFF050705));

    final mesh = Paint()
      ..color = Brand.text.withValues(alpha: 0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    // الشبكة: نقاط مُزاحة بانتفاخ يتلاشى بعد الاصطدام. الإزاحة
    // شعاعية من نقطة الارتطام مع تخميد أُسّي — أرخص بكثير من محاكاة
    // نسيج، وتُقرأ بالعين كما تُقرأ الحقيقة في لقطة تدوم نصف ثانية.
    Offset warp(Offset p) {
      if (t < _tGoal) return p;
      final dt = t - _tGoal;
      final amp = 52 * math.exp(-8.5 * dt) * math.cos(22 * dt);
      final d = p - _impact;
      final dist = d.distance;
      if (dist < 0.001) return p + Offset(-amp, 0);
      final falloff = math.exp(-(dist * dist) / (2 * 175 * 175));
      return p + (d / dist) * amp * falloff;
    }

    const step = 34.0;
    for (var x = _goalMouth.left; x <= _goalMouth.right; x += step) {
      final path = Path();
      for (var y = _goalMouth.top; y <= _goalMouth.bottom; y += 20) {
        final p = warp(Offset(x, y));
        if (y == _goalMouth.top) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, mesh);
    }
    for (var y = _goalMouth.top; y <= _goalMouth.bottom; y += step) {
      final path = Path();
      for (var x = _goalMouth.left; x <= _goalMouth.right; x += 20) {
        final p = warp(Offset(x, y));
        if (x == _goalMouth.left) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, mesh);
    }

    // الإطار الأمامي: قائمان وعارضة بيضاء صريحة — هو ما يعرّف
    // الشكل، فيُرسم فوق الشبكة لا تحتها.
    final post = Paint()
      ..color = Brand.text.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(_goalMouth.left, _goalMouth.bottom),
      Offset(_goalMouth.left, _goalMouth.top),
      post,
    );
    canvas.drawLine(
      Offset(_goalMouth.right, _goalMouth.bottom),
      Offset(_goalMouth.right, _goalMouth.top),
      post,
    );
    canvas.drawLine(
      Offset(_goalMouth.left, _goalMouth.top),
      Offset(_goalMouth.right, _goalMouth.top),
      post,
    );
  }

  /// موضع الكرة على المحور الزمني.
  Offset _ballAt(double time) {
    const foot = Offset(880, _ground - _ballR);

    if (time < _tShot) {
      // تمريرة أرضية قادمة من خارج الإطار يميناً.
      final p = Curves.easeOutSine.transform(_seg(time, 0, _tShot));
      return Offset(1220 + (foot.dx - 1220) * p, foot.dy);
    }

    if (time < _tGoal) {
      // تسديدة صاعدة: منحنى بيزييه من القدم إلى الشبكة.
      final p = Curves.easeOutCubic.transform(_seg(time, _tShot, _tGoal));
      const ctrl = Offset(600, 560);
      final a = Offset.lerp(foot, ctrl, p)!;
      final b = Offset.lerp(ctrl, _impact, p)!;
      return Offset.lerp(a, b, p)!;
    }

    // بعد الارتطام: تسقط داخل الشبكة.
    final dt = time - _tGoal;
    return _impact + Offset(-26 * dt, 900 * dt * dt);
  }

  void _drawBall(Canvas canvas) {
    if (t > _tCeleb + 0.35) return; // تختفي مع بداية ظهور العلامة

    final pos = _ballAt(t);
    final fade = 1 - _seg(t, _tCeleb, _tCeleb + 0.35);

    // ذيل الحركة: عيّنات من الماضي القريب بشفافية متناقصة. أرخص
    // وأوضح من blur حقيقي، وهو ما يجعل السرعة محسوسة أصلاً.
    for (var i = 8; i >= 1; i--) {
      final past = t - i * 0.016;
      if (past < 0) continue;
      canvas.drawCircle(
        _ballAt(past),
        _ballR * (1 - i * 0.052),
        Paint()
          ..color = Brand.crown.withValues(alpha: 0.055 * (9 - i) / 8 * fade),
      );
    }

    canvas.drawCircle(
      pos,
      _ballR * 2.4,
      Paint()..color = Brand.crownWash(0.06 * fade),
    );
    canvas.drawCircle(
      pos,
      _ballR,
      Paint()..color = Brand.text.withValues(alpha: fade),
    );

    // نقش كرة القدم: خماسي في الوسط وخمس درزات تخرج من رؤوسه.
    // (رقعتان دائريتان — أول محاولة — جعلتا الكرة تُقرأ كرةَ بولينج
    // بعينين، فالنقش ليس تفصيلاً تجميلياً بل هو ما يجعلها كرة قدم.)
    final spin = t * 13;
    final ink = Paint()..color = Brand.night.withValues(alpha: 0.88 * fade);

    final penta = Path();
    for (var i = 0; i < 5; i++) {
      final a = spin + i * math.pi * 2 / 5 - math.pi / 2;
      final p = pos + Offset(math.cos(a), math.sin(a)) * (_ballR * 0.36);
      i == 0 ? penta.moveTo(p.dx, p.dy) : penta.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(penta..close(), ink);

    final seam = Paint()
      ..color = ink.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _ballR * 0.15
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 5; i++) {
      final a = spin + i * math.pi * 2 / 5 - math.pi / 2;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        pos + dir * (_ballR * 0.36),
        pos + dir * (_ballR * 0.92),
        seam,
      );
    }
  }

  /// المهاجم: ظلٌّ بضربات سميكة مستديرة، وساقه تتأرجح مع التسديدة.
  /// الظل لا الطقم المفصّل: أشكال بسيطة تُقرأ لاعباً في لقطة سريعة،
  /// ومحاولة رسم قميص وشورت وجورب بهذا المقياس تنتج تشويشاً.
  void _drawStriker(Canvas canvas) {
    const hip = Offset(886, _ground - 196);
    final swing = t < _tShot
        ? -0.35 * Curves.easeInOut.transform(_seg(t, _tShot - 0.2, _tShot))
        : 1.15 * Curves.easeOutBack.transform(_seg(t, _tShot, _tShot + 0.22));

    final body = Paint()
      ..color = const Color(0xFF33352F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 34
      ..strokeCap = StrokeCap.round;
    final rim = Paint()
      ..color = Brand.crown.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    // الجذع مائل للأمام (يساراً) مع التسديد.
    final lean = swing * 0.12;
    final shoulder = hip + Offset(-70 * lean - 6, -104);

    canvas.drawLine(hip, shoulder, body);
    canvas.drawLine(hip, shoulder, rim);

    // الرأس
    final head = shoulder + Offset(-8 - 18 * lean, -46);
    canvas.drawCircle(head, 30, Paint()..color = const Color(0xFF33352F));
    canvas.drawCircle(
      head,
      30,
      Paint()
        ..color = Brand.crown.withValues(alpha: 0.50)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );

    // الذراعان للاتزان
    canvas.drawLine(
      shoulder,
      shoulder + Offset(74 * swing.abs() + 30, -46),
      body..strokeWidth = 20,
    );
    canvas.drawLine(
      shoulder,
      shoulder + Offset(-64, 26 - 40 * swing.abs()),
      body..strokeWidth = 20,
    );

    // الساق الثابتة
    body.strokeWidth = 30;
    canvas.drawLine(hip, const Offset(902, _ground), body);

    // الساق الضاربة: تدور حول الورك.
    final kneeA = -0.55 + swing * 1.05;
    final knee = hip + Offset(math.sin(kneeA) * -96, math.cos(kneeA) * 96);
    final footA = kneeA + 0.30 + swing * 0.55;
    final foot = knee + Offset(math.sin(footA) * -92, math.cos(footA) * 92);
    canvas.drawLine(hip, knee, body);
    canvas.drawLine(knee, foot, body);
    canvas.drawLine(knee, foot, rim);

    // غبار عند القدم لحظة الضربة — تنص عليه المواصفة.
    final dustP = _seg(t, _tShot, _tShot + 0.3);
    if (dustP > 0 && dustP < 1) {
      final rnd = math.Random(3);
      for (var i = 0; i < 12; i++) {
        final a = rnd.nextDouble() * math.pi;
        final d = 30 + dustP * (90 + rnd.nextDouble() * 90);
        canvas.drawCircle(
          Offset(890 - math.cos(a) * d, _ground - math.sin(a) * d * 0.45),
          9 * (1 - dustP),
          Paint()..color = Brand.text.withValues(alpha: 0.10 * (1 - dustP)),
        );
      }
    }
  }

  /// الحارس يرتمي متأخراً — الكرة تمرّ فوقه.
  void _drawKeeper(Canvas canvas) {
    final dive = Curves.easeIn.transform(_seg(t, _tShot + 0.10, _tGoal + 0.10));
    // يرتمي منخفضاً والكرة تمرّ فوقه: الحارس المهزوم يجعل الهدف
    // هدفاً. لو تقاطع مساره مع الكرة لبدت اللقطة تصدّياً لا تسجيلاً.
    final center = Offset(500 - 80 * dive, _ground - 155 + 45 * dive);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.95 * dive);

    final body = Paint()
      ..color = const Color(0xFF2A2C27)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 30
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(const Offset(0, 60), const Offset(0, -50), body);
    canvas.drawCircle(
      const Offset(0, -84),
      26,
      Paint()..color = const Color(0xFF2A2C27),
    );
    // ذراعان ممدودتان نحو الكرة
    canvas.drawLine(
      const Offset(0, -46),
      Offset(-52 - 26 * dive, -108),
      body..strokeWidth = 19,
    );
    canvas.drawLine(const Offset(0, -40), Offset(-34, -84), body);
    body.strokeWidth = 27;
    canvas.drawLine(const Offset(0, 56), Offset(44 + 20 * dive, 104), body);
    canvas.drawLine(const Offset(0, 56), Offset(14, 116), body);

    canvas.restore();
  }

  /// لحظة الهدف: وميض، ورشّ شعاعي من نقطة الارتطام.
  void _drawImpact(Canvas canvas) {
    if (t < _tGoal) return;
    final dt = t - _tGoal;

    final flash = math.exp(-9 * dt) * 0.5;
    if (flash > 0.004) {
      canvas.drawRect(
        const Rect.fromLTWH(-_stageW, -_stageH, _stageW * 3, _stageH * 3),
        Paint()..color = Brand.text.withValues(alpha: flash),
      );
    }

    final burst = _seg(t, _tGoal, _tGoal + 0.45);
    if (burst < 1) {
      final rnd = math.Random(11);
      final paint = Paint()
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      for (var i = 0; i < 15; i++) {
        final a = rnd.nextDouble() * math.pi * 2;
        final len = 34 + rnd.nextDouble() * 62;
        final r0 = 24 + burst * (86 + rnd.nextDouble() * 60);
        final dir = Offset(math.cos(a), math.sin(a));
        paint
          ..color = (i.isEven ? Brand.crown : Brand.text).withValues(
            alpha: 0.55 * (1 - burst),
          )
          ..strokeWidth = 5 * (1 - burst) + 1;
        canvas.drawLine(
          _impact + dir * r0,
          _impact + dir * (r0 + len * (1 - burst)),
          paint,
        );
      }
    }
  }

  void _drawConfetti(Canvas canvas) {
    final base = _seg(t, _tCeleb, _tEnd);
    if (base == 0) return;
    final fade = 1 - _seg(t, _tSettle + 0.2, _tEnd);

    for (final c in confetti) {
      final age = (t - _tCeleb - c.delay);
      if (age <= 0) continue;
      final y = -120 + c.vy * age;
      if (y > _stageH) continue;
      final x = c.x + math.sin(age * 3 + c.x) * c.sway;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(c.rot + age * c.spin);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: c.size,
            height: c.size * 1.7,
          ),
          const Radius.circular(2),
        ),
        Paint()..color = c.color.withValues(alpha: 0.85 * fade),
      );
      canvas.restore();
    }
  }

  /// تعتيم الأطراف — يجمع العين على الحدث، ويشتدّ في مشهد التسليم
  /// حتى تقرأ حقول الدخول فوقه.
  void _drawVignette(Canvas canvas) {
    const rect = Rect.fromLTWH(-200, -200, _stageW + 400, _stageH + 400);
    final extra = vignetteExtra ?? _seg(t, _tSettle, _tEnd) * 0.42;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.92,
          colors: [
            Brand.night.withValues(alpha: extra),
            Brand.night.withValues(alpha: 0.12 + extra),
            Brand.night.withValues(alpha: 0.66 + extra * 0.34),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_ScenePainter old) => old.t != t ||
      old.actors != actors ||
      old.camera != camera ||
      old.vignetteExtra != vignetteExtra;
}
