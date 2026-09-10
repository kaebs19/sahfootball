// صفحة الشراء — التاج الذهبي.
//
// ترتيبها يجيب أسئلة المشتري بالترتيب الذي يسألها به: ما هذا؟ ثم
// ماذا أكسب؟ ثم بكم؟ ثم زرّ واحد. والسعر قبل الزرّ لا بعده — سعرٌ
// يظهر بعد الضغط يجعل الضغطة فخّاً.
//
// وما لا تفعله هذه الشاشة أهم مما تفعله: لا تعد بنقاط ولا بمراكز.
// التاج يشتري راحةً وأدوات تُنفق قبل معرفة النتيجة، ولو باع مركزاً
// في اللوحة لانتهت قيمة اللوحة — وهي المنتج كله.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../format.dart';
import '../models/premium.dart';
import '../services/store_bridge.dart';
import '../state/premium.dart';
import '../state/session.dart';
import '../widgets/brand_widgets.dart';
import 'contact_screen.dart';
import 'page_screen.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  PremiumOffer? _offer;
  String? _error;
  String? _busyProduct;
  StreamSubscription<StoreOutcome>? _outcomes;

  @override
  void initState() {
    super.initState();
    _load();
    // نتائج المتجر تصل عبر مجرى لا كقيمة راجعة: ورقة الدفع نافذة
    // نظام قد تُغلق وتُفتح، والمعاملة قد تكتمل بعد ثوانٍ أو أيام
    // (موافقة وليّ الأمر). الشاشة تترجم النتيجة إلى جملة وحسب.
    _outcomes = context.read<StoreBridge>().outcomes.listen(_onOutcome);
  }

  @override
  void dispose() {
    _outcomes?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final offer = await context.read<ApiClient>().premiumOffer();
      if (!mounted) return;
      setState(() => _offer = offer);
      // أسعار المتجر بعملة المشتري — آبل تشترط عرضها هي لا أرقامنا.
      await context.read<StoreBridge>().loadProducts({
        offer.crown.productId,
        if (offer.pack != null) offer.pack!.productId,
        if (offer.shieldPack != null) offer.shieldPack!.productId,
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// المنصّة كما يفهمها السيرفر — وهي التي تحدّد أي متجر يُسأل عن
  /// الإيصال.
  String get _platform => Platform.isIOS ? 'apple' : 'google';

  void _onOutcome(StoreOutcome outcome) {
    if (!mounted) return;
    final premium = context.read<Premium>().isPremium;
    final text = switch (outcome) {
      StoreOutcome.granted => premium ? 'أهلاً بك في التاج الذهبي' : 'تمّ الشراء',
      StoreOutcome.restoredNothing => 'لا مشتريات على هذا الحساب',
      StoreOutcome.cancelled => null,
      StoreOutcome.pending => 'بانتظار الموافقة على الشراء',
      StoreOutcome.failed =>
        context.read<StoreBridge>().lastError ?? 'تعذّر إتمام الشراء',
    };
    setState(() => _busyProduct = null);
    if (text != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  /// الشراء.
  ///
  /// على iOS يذهب إلى StoreKit عبر [StoreBridge]: المتجر يقبض ويُصدر
  /// معاملة موقّعة، والجسر يسلّمها إلى السيرفر الذي يتحقّق ويمنح.
  /// على أندرويد يبقى المسار القديم حتى يُربط Play Billing، والسيرفر
  /// يردّ عليه برسالة صريحة تُعرض كما هي.
  Future<void> _buy(StoreProduct product, {required bool consumable}) async {
    final store = context.read<StoreBridge>();
    setState(() => _busyProduct = product.productId);
    if (store.available) {
      await store.buy(product.productId, consumable: consumable);
      return; // النتيجة تصل عبر _onOutcome
    }
    final api = context.read<ApiClient>();
    final premium = context.read<Premium>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ent = await api.verifyPurchase(
        platform: _platform,
        productId: product.productId,
      );
      premium.adopt(ent);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(ent.premium ? 'أهلاً بك في التاج الذهبي' : 'تمّ الشراء'),
      ));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busyProduct = null);
    }
  }

  Future<void> _restore() async {
    final store = context.read<StoreBridge>();
    if (store.supported) {
      await store.restore(); // النتيجة تصل عبر _onOutcome
      return;
    }
    final api = context.read<ApiClient>();
    final premium = context.read<Premium>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ent = await api.restorePurchases(platform: _platform);
      premium.adopt(ent);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(ent.premium ? 'استُعيد اشتراكك' : 'لا اشتراك على هذا الحساب'),
      ));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// سعر المنتج كما يعرضه المتجر إن وُجد، وإلا سعرنا الاحتياطي.
  String _price(StoreProduct p) =>
      context.watch<StoreBridge>().products[p.productId]?.price ?? p.label;

  @override
  Widget build(BuildContext context) {
    final ent = context.watch<Premium>().value;
    final signedIn =
        context.watch<Session>().status == SessionStatus.loggedIn;
    final offer = _offer;

    return Scaffold(
      appBar: AppBar(title: const Text('التاج الذهبي')),
      body: _error != null
          ? BrandEmpty(icon: Icons.wifi_off, message: _error!, onRetry: _load)
          : offer == null
              ? const Center(
                  child: CircularProgressIndicator(color: Brand.crown))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
                  children: [
                    _Hero(entitlements: ent),
                    const SizedBox(height: 22),
                    for (final perk in offer.perks) ...[
                      _PerkRow(perk: perk),
                      const SizedBox(height: 14),
                    ],
                    const SizedBox(height: 8),
                    if (!offer.enabled)
                      // الصفحة معروضة والشراء لم يُفتح بعد: نقول ذلك
                      // بالسعر لا بجملة «متوقّف» توحي بعطل. اللاعب يعرف ما
                      // سيأتي وبكم، ولا زرّ يضغطه فيفشل.
                      BrandCard(
                        child: Column(
                          children: [
                            const Icon(Icons.hourglass_top,
                                color: Brand.crown, size: 26),
                            const SizedBox(height: 8),
                            const Text(
                              'قريباً',
                              style: TextStyle(
                                fontFamily: Brand.displayFont,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Brand.text,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'الاشتراك الشهري ${_price(offer.crown)} — يُفتح '
                              'مع التحديث القادم.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Brand.textMuted, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    else if (!signedIn)
                      // الضيف يقرأ العرض كاملاً ثم يُدعى للتسجيل: إخفاء
                      // العرض عنه يحرمنا أقوى سبب لإنشاء حساب.
                      FilledButton(
                        onPressed: () =>
                            context.read<Session>().leaveGuest(),
                        child: const Text('سجّل الدخول للاشتراك'),
                      )
                    else if (ent.premium)
                      _ActiveCard(entitlements: ent)
                    else ...[
                      FilledButton(
                        onPressed: _busyProduct != null
                            ? null
                            : () => _buy(offer.crown, consumable: false),
                        child: _busyProduct == offer.crown.productId
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : Text('اشترك · ${_price(offer.crown)} شهرياً'),
                      ),
                      const SizedBox(height: 10),
                      // السعر نفسه الذي على الزرّ: سعر المتجر إن وُجد.
                      // إفصاحٌ بسعر يخالف الزرّ سببُ رفض عند آبل.
                      _RenewalTerms(price: _price(offer.crown)),
                    ],
                    // مشتريات لمرة واحدة، لمن لا يريد اشتراكاً شهرياً:
                    // الأداة تُشترى وتُنفق وتنتهي، ولا تلتزم بشيء.
                    //
                    // والقسم كله يغيب حين يحذفها السيرفر من العرض: عنوانٌ
                    // فوق فراغ أسوأ من لا شيء.
                    if (offer.pack != null || offer.shieldPack != null) ...[
                      const SizedBox(height: 26),
                      const BrandSectionLabel('أو اشترِ أدوات لمرة واحدة'),
                    ],
                    if (offer.pack != null) ...[
                      const SizedBox(height: 10),
                      _PackCard(
                        icon: Icons.bolt,
                        title: '${offer.pack!.size} مضاعِفات '
                            '×${offer.pack!.factor}',
                        note: 'رصيدك الآن ${ent.boost.left} · تُنفق في أي دوري',
                        price: _price(offer.pack!),
                        busy: _busyProduct == offer.pack!.productId,
                        onBuy: signedIn && offer.enabled
                            ? () => _buy(offer.pack!, consumable: true)
                            : null,
                      ),
                    ],
                    if (offer.shieldPack != null) ...[
                      const SizedBox(height: 10),
                      _PackCard(
                        icon: Icons.shield_outlined,
                        title: offer.shieldPack!.size == 1
                            ? 'درع سلسلة واحد'
                            : '${offer.shieldPack!.size} دروع سلسلة',
                        note: 'يحمي أول خطأ بعد شرائه · اشتريت '
                            '${ent.shield.purchased}',
                        price: _price(offer.shieldPack!),
                        busy: _busyProduct == offer.shieldPack!.productId,
                        onBuy: signedIn && offer.enabled
                            ? () => _buy(offer.shieldPack!, consumable: true)
                            : null,
                      ),
                    ],
                    if (signedIn) ...[
                      const SizedBox(height: 18),
                      Center(
                        child: TextButton(
                          onPressed: _restore,
                          child: const Text('استعادة المشتريات'),
                        ),
                      ),
                    ],
                    // الروابط في آخر الشاشة لا في الإعدادات وحدها:
                    // آبل تشترط أن يجد المشتري سياسة الخصوصية وشروط
                    // الاستخدام في نفس الشاشة التي يدفع فيها، لا بعد
                    // بحثٍ في قائمة أخرى (بند 3.1.2).
                    const SizedBox(height: 14),
                    const _LegalLinks(),
                  ],
                ),
    );
  }
}

/// شروط التجديد التلقائي — نصٌّ تشترطه المتاجر حرفاً بحرف.
///
/// آبل (بند 3.1.2) تطلب أن يقرأ المشتري قبل الدفع: اسم الخدمة، ومدّة
/// الاشتراك، وسعره، وأنه يتجدّد تلقائياً ما لم يُلغَ قبل انتهاء المدّة
/// بأربع وعشرين ساعة، وأن الخصم يقع على حسابه في المتجر، وأين يُلغيه.
/// نقصُ بندٍ واحد منها سببُ رفض متكرّر — ولهذا النصّ هنا لا في صفحة
/// بعيدة يصلها من يبحث.
///
/// والصياغة تتبدّل بالمنصّة: من يقرأ على آيفون يُقال له «حساب Apple»
/// لأنه هناك يلغي فعلاً، ومن على أندرويد «Google Play».
class _RenewalTerms extends StatelessWidget {
  /// السعر كما يُعرض على زرّ الاشتراك — من المتجر حين يتوفّر.
  final String price;
  const _RenewalTerms({required this.price});

  @override
  Widget build(BuildContext context) {
    final store = Platform.isIOS ? 'Apple' : 'Google Play';
    final path = Platform.isIOS
        ? 'إعدادات جهازك ← اسمك ← الاشتراكات'
        : 'تطبيق Google Play ← الاشتراكات';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Brand.fill,
        borderRadius: BorderRadius.circular(Brand.radiusSmall),
      ),
      child: Text(
        'التاج الذهبي اشتراك شهري بـ$price يتجدّد تلقائياً.\n'
        'يُخصم المبلغ من حساب $store عند تأكيد الشراء، ثم يُجدَّد خلال '
        'الأربع والعشرين ساعة السابقة لنهاية كل شهر ما لم تُلغِ التجديد '
        'قبل ذلك بأربع وعشرين ساعة على الأقل.\n'
        'تُدير اشتراكك وتُلغي التجديد من $path.',
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: Brand.textFaint, fontSize: 11.5, height: 1.7),
      ),
    );
  }
}

/// سياسة الخصوصية وشروط الاستخدام والتواصل — في شاشة الدفع نفسها.
///
/// الصفحتان تُفتحان داخل التطبيق من نفس مسار الإعدادات (site_pages على
/// السيرفر)، فنصّ واحد يُصحَّح في مكان واحد ويظهر في البابين.
class _LegalLinks extends StatelessWidget {
  const _LegalLinks();

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        _LegalLink(
          label: 'سياسة الخصوصية',
          onTap: () => _open(
            context,
            const PageScreen(
                slug: 'privacy', fallbackTitle: 'سياسة الخصوصية'),
          ),
        ),
        const Text('·', style: TextStyle(color: Brand.textFaint)),
        _LegalLink(
          label: 'شروط الاستخدام',
          onTap: () => _open(
            context,
            const PageScreen(slug: 'terms', fallbackTitle: 'شروط الاستخدام'),
          ),
        ),
        const Text('·', style: TextStyle(color: Brand.textFaint)),
        _LegalLink(
          label: 'اتصل بنا',
          onTap: () => _open(context, const ContactScreen()),
        ),
      ],
    );
  }
}

class _LegalLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _LegalLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        // زرّ نصّي مضغوط: ثلاثة أزرار بالحشو الافتراضي تفيض عن السطر
        // في العربية، والمطلوب سطرٌ واحد هادئ لا صفّ أزرار.
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: Brand.textMuted,
      ),
      child: Text(label, style: const TextStyle(fontSize: 11.5)),
    );
  }
}

/// الترويسة: التاج، وحالته الآن.
class _Hero extends StatelessWidget {
  final Entitlements entitlements;
  const _Hero({required this.entitlements});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Brand.crownWash(0.14),
            border: Border.all(color: Brand.crownWash(0.4), width: 2),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.workspace_premium,
              size: 44, color: Brand.crown),
        ),
        const SizedBox(height: 14),
        const Text(
          'التاج الذهبي',
          style: TextStyle(
            fontFamily: Brand.displayFont,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Brand.text,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          entitlements.premium
              ? 'اشتراكك فعّال'
              : 'معزّزات شهرية · بلا إعلانات',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: entitlements.premium ? Brand.crown : Brand.textMuted,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _PerkRow extends StatelessWidget {
  final Perk perk;
  const _PerkRow({required this.perk});

  static const _icons = {
    'no_ads': Icons.block,
    'edit': Icons.edit_outlined,
    'boosters': Icons.bolt,
    'shield': Icons.shield_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(_icons[perk.key] ?? Icons.check_circle_outline,
            size: 20, color: Brand.crown),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                perk.title,
                style: const TextStyle(
                  color: Brand.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                perk.body,
                style: const TextStyle(
                    color: Brand.textMuted, fontSize: 12.5, height: 1.7),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// حالة المشترك: إلى متى، وكم معزّزاً بقي له.
class _ActiveCard extends StatelessWidget {
  final Entitlements entitlements;
  const _ActiveCard({required this.entitlements});

  @override
  Widget build(BuildContext context) {
    final until = entitlements.premiumUntil;
    return BrandCard(
      royal: true,
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, size: 20, color: Brand.correct),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  until == null
                      ? 'اشتراكك فعّال'
                      : 'فعّال حتى ${Fmt.date(intl.DateFormat('d MMM y', 'ar'), until)}',
                  style: const TextStyle(color: Brand.text, fontSize: 13.5),
                ),
              ),
            ],
          ),
          const Divider(color: Brand.borderSoft, height: 22),
          Row(
            children: [
              const Icon(Icons.bolt, size: 18, color: Brand.crown),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'رصيدك من مضاعِف ×${entitlements.boost.factor}: '
                  '${entitlements.boost.left}',
                  style: const TextStyle(
                    color: Brand.textMuted,
                    fontSize: 12.5,
                    fontFeatures: Brand.tabular,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// بطاقة منتج يُشترى مرة واحدة — نصّها من المستدعي لأن المنتجات
/// تختلف (مضاعِفات، درع) والشكل واحد.
class _PackCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String note;
  final String price;
  final bool busy;
  final VoidCallback? onBuy;

  const _PackCard({
    required this.icon,
    required this.title,
    required this.note,
    required this.price,
    required this.busy,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    return BrandCard(
      child: Row(
        children: [
          Icon(icon, size: 24, color: Brand.crown),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Brand.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  note,
                  style: const TextStyle(
                    color: Brand.textFaint,
                    fontSize: 11.5,
                    fontFeatures: Brand.tabular,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 34,
            child: OutlinedButton(
              onPressed: busy ? null : onBuy,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(price),
            ),
          ),
        ],
      ),
    );
  }
}
