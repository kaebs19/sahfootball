// الإعلانات — بانر مثبّت وإعلان مدمج، من AdMob.
//
// ثلاث قواعد تحكم هذا الملف كله، وكلها مكتوبة هنا مرة واحدة لأن
// تركها لكل شاشة يعني أن أول شاشة تُنسى تكسرها:
//
// 1) **لا إعلان لمشترك أبداً.** هذا ما يُدفع مقابله، وإعلانٌ واحد
//    يظهر لمن دفع كي لا يراه يُلغي الاشتراك في نفس الجلسة.
//
// 2) **لا فراغ ولا قفزة.** الإعلان يصل بعد ثانية أو لا يصل أصلاً
//    (شبكة، جهاز بلا إعلانات، وحدة معطّلة). فما دام لم يصل لا نحجز
//    له مساحة فارغة، وحين يفشل نضع دعوتنا للاشتراك مكانه — مساحة
//    نملكها بدل ثقب أسود وسط القائمة.
//
// 3) **الإعلان يُتلَف مع الويدجت.** كل إعلان محمَّل يحجز ذاكرة
//    أصلية (native) لا يحرّرها جامع القمامة في Dart؛ نسيان dispose
//    يسرّبها إعلاناً بعد إعلان حتى يختنق التطبيق في قائمة تُمرَّر.
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';

import '../brand.dart';
import '../models/premium.dart';
import '../state/premium.dart';
import 'premium_widgets.dart';

/// تهيئة حزمة الإعلانات مرة واحدة عند الإقلاع.
///
/// لا تُنتظر (بلا await) في main: التهيئة تكلّم خوادم جوجل، وانتظارها
/// يؤخّر أول إطار على شبكة بطيئة — والإعلان يستطيع الانتظار،
/// والشاشة لا تستطيع.
Future<void> initAds() => MobileAds.instance.initialize().then((_) {});

/// بانر مثبّت — يُوضع فوق شريط التنقّل السفلي.
///
/// «تكيّفي مثبّت» (anchored adaptive) لا مقاس ثابت: جوجل تختار
/// ارتفاعاً يناسب عرض الجهاز، فيظهر البانر بحجم مقروء على الشاشات
/// الكبيرة بدل شريط صغير ضائع في عرضها.
class BannerAdSlot extends StatefulWidget {
  const BannerAdSlot({super.key});

  @override
  State<BannerAdSlot> createState() => _BannerAdSlotState();
}

class _BannerAdSlotState extends State<BannerAdSlot> {
  BannerAd? _ad;
  bool _loaded = false;

  /// الوحدة التي حُمِّل بها الإعلان الحالي — نعيد التحميل إن تبدّلت
  /// (تغيير إعداد من اللوحة، أو انتهاء اشتراك في منتصف الاستعمال).
  String? _unit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync(context.watch<Premium>().ads);
  }

  void _sync(AdConfig cfg) {
    final unit = cfg.show ? cfg.banner : null;
    if (unit == _unit) return;
    _unit = unit;
    _dispose();
    if (unit != null) _load(unit);
  }

  Future<void> _load(String unit) async {
    // العرض المتاح يُقاس من الشاشة لا من الويدجت: الحساب يجري قبل
    // أن يكون للبانر مكان في الشجرة أصلاً.
    final width = MediaQuery.sizeOf(context).width.truncate();
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSizeWithOrientation(
        Orientation.portrait, width);
    if (size == null || !mounted || _unit != unit) return;

    final ad = BannerAd(
      adUnitId: unit,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (!mounted) return;
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          // الفشل حالة عادية لا عطل: جهاز بلا إعلانات متاحة، أو
          // شبكة، أو نفاد المخزون. نتخلّص منه ونصمت — ومحاولة
          // إعادة التحميل في حلقة تستنزف البطارية وحصة الطلبات.
          ad.dispose();
          if (!mounted) return;
          setState(() {
            _ad = null;
            _loaded = false;
          });
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  void _dispose() {
    _ad?.dispose();
    _ad = null;
    _loaded = false;
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    // لا مساحة محجوزة قبل الوصول: شريطٌ فارغ يظهر ثم يمتلئ يقفز
    // بالمحتوى تحت إصبع المستخدم.
    if (ad == null || !_loaded) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      height: ad.size.height.toDouble(),
      alignment: Alignment.center,
      // خط فاصل فوقه: الهوية تفصل الأسطح بالحدود لا بالظلال، والبانر
      // محتوى غريب عن التطبيق فيجب أن يُقرأ منفصلاً لا جزءاً منه.
      decoration: const BoxDecoration(
        color: Brand.night,
        border: Border(top: BorderSide(color: Brand.borderSoft)),
      ),
      child: AdWidget(ad: ad),
    );
  }
}

/// إعلان مدمج داخل قائمة — بطاقةٌ بين البطاقات.
///
/// القالب الجاهز (NativeTemplateStyle) لا تخطيط أصلي مكتوب بيدنا:
/// الثاني يعني ملف Swift وملف Kotlin ومصنعاً مسجّلاً في كل منهما،
/// وثلاث نسخ من نفس التصميم تتباعد. والقالب يقبل ألوان الهوية
/// وخطوطها فيخرج مدمجاً في الشاشة لا لصيقاً بها.
///
/// والقالب **الصغير** بمقاس بطاقة المباراة تماماً، لا المتوسط ذو
/// الصورة الكبيرة: القائمة لها إيقاع — بطاقة بعد بطاقة بنفس
/// الارتفاع ونفس الهامش — وكتلةٌ بضعف الارتفاع تكسر ذلك الإيقاع
/// فتُقرأ اقتحاماً لا عنصراً في القائمة. والمكسب مزدوج: إعلانٌ
/// يشبه ما حوله يُنقر أكثر من إعلان يصرخ بغربته.
class NativeAdSlot extends StatefulWidget {
  /// نصّ الدعوة الذي يحلّ محلّ الإعلان إن لم يصل.
  final String fallbackReason;

  const NativeAdSlot({
    super.key,
    this.fallbackReason = 'تصفّح بلا إعلانات.',
  });

  @override
  State<NativeAdSlot> createState() => _NativeAdSlotState();
}

class _NativeAdSlotState extends State<NativeAdSlot> {
  NativeAd? _ad;
  bool _loaded = false;
  String? _unit;

  /// ارتفاع الإعلان. ثابتٌ لأن AdWidget يحتاج حدوداً معلومة داخل
  /// قائمة تُمرَّر — لا ارتفاعاً ذاتياً يقيسه من محتواه.
  ///
  /// والرقم هو ارتفاع بطاقة المباراة (FixtureCard) نفسه، فيجلس
  /// الإعلان في القائمة بمقاس جيرانه لا أطول ولا أقصر.
  ///
  /// ولا يُنقَص عنه: القالب الصغير له حدّ أدنى يرسم تحته لا شيء —
  /// جُرّب 116 فاختفى الإعلان كلياً بلا خطأ في السجل، لأن ويدجت
  /// الخطأ في نسخة الإصدار ترسم فراغاً صامتاً. ولو تغيّر ارتفاع
  /// البطاقة يوماً وجب تغيير هذا معه: الرقمان يصفان شيئاً واحداً هو
  /// إيقاع القائمة.
  static const _height = 176.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync(context.watch<Premium>().ads);
  }

  void _sync(AdConfig cfg) {
    final unit = cfg.show ? cfg.native : null;
    if (unit == _unit) return;
    _unit = unit;
    _disposeAd();
    if (unit != null) _load(unit);
  }

  void _load(String unit) {
    final ad = NativeAd(
      adUnitId: unit,
      request: const AdRequest(),
      // ألوان الهوية داخل قالب جوجل: السطح الداكن، والنصّ الفاتح،
      // والزرّ الأبيض ذو النصّ الأسود كما في كل أزرار التطبيق.
      // والذهبي غائب عمداً — قاعدة الهوية تحصره في التاج والنقاط
      // والرتب، وإعلانٌ يلبسه يبدو جزءاً من اللعبة وهو ليس منها.
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.small,
        mainBackgroundColor: Brand.surface,
        cornerRadius: Brand.radiusCard,
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: Brand.text,
          backgroundColor: Brand.surface,
          size: 14,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: Brand.textMuted,
          backgroundColor: Brand.surface,
          size: 12,
        ),
        tertiaryTextStyle: NativeTemplateTextStyle(
          textColor: Brand.textFaint,
          backgroundColor: Brand.surface,
          size: 11,
        ),
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Brand.onAccent,
          backgroundColor: Brand.text,
          size: 13,
        ),
      ),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (!mounted) return;
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (!mounted) return;
          setState(() {
            _ad = null;
            _loaded = false;
          });
        },
      ),
    );
    _ad = ad;
    ad.load();
  }

  void _disposeAd() {
    _ad?.dispose();
    _ad = null;
    _loaded = false;
  }

  @override
  void dispose() {
    _disposeAd();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!context.watch<Premium>().showAds) return const SizedBox.shrink();

    final ad = _ad;
    // لم يصل إعلان — نضع دعوتنا نحن مكانه. المساحة مساحتنا في
    // الحالتين، والثقب الأسود وسط قائمة أسوأ من إعلان.
    if (ad == null || !_loaded) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: CrownUpsell(reason: widget.fallbackReason),
      );
    }
    // بلا خلفية نرسمها نحن خلف الإعلان: العرض الأصلي (platform view)
    // يُركَّب في طبقة خاصة، وأي لون مصمت نضعه في نفس الصندوق يحجبه
    // فيختفي الإعلان كلياً — جُرّب ووقع. القالب نفسه يرسم سطحه
    // ونصف قطره (mainBackgroundColor و cornerRadius أعلاه)، فيخرج
    // بمظهر البطاقة بلا طبقة ثانية تنازعه.
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Brand.radiusCard),
        child: SizedBox(height: _height, child: AdWidget(ad: ad)),
      ),
    );
  }
}
