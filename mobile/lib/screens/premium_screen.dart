// صفحة الشراء — التاج الذهبي.
//
// ترتيبها يجيب أسئلة المشتري بالترتيب الذي يسألها به: ما هذا؟ ثم
// ماذا أكسب؟ ثم بكم؟ ثم زرّ واحد. والسعر قبل الزرّ لا بعده — سعرٌ
// يظهر بعد الضغط يجعل الضغطة فخّاً.
//
// وما لا تفعله هذه الشاشة أهم مما تفعله: لا تعد بنقاط ولا بمراكز.
// التاج يشتري راحةً وأدوات تُنفق قبل معرفة النتيجة، ولو باع مركزاً
// في اللوحة لانتهت قيمة اللوحة — وهي المنتج كله.
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../format.dart';
import '../models/premium.dart';
import '../state/premium.dart';
import '../state/session.dart';
import '../widgets/brand_widgets.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  PremiumOffer? _offer;
  String? _error;
  String? _busyProduct;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final offer = await context.read<ApiClient>().premiumOffer();
      if (mounted) setState(() => _offer = offer);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// المنصّة كما يفهمها السيرفر — وهي التي تحدّد أي متجر يُسأل عن
  /// الإيصال.
  String get _platform => Platform.isIOS ? 'apple' : 'google';

  /// الشراء.
  ///
  /// اليوم يذهب مباشرة إلى السيرفر بلا إيصال: المشتريات داخل
  /// التطبيق تحتاج منتجات في App Store Connect ومفاتيح تحقّق، وحتى
  /// تُنشأ يردّ السيرفر برسالة صريحة تُعرض كما هي. وحين تُوصَل
  /// (`in_app_purchase`) يُستدعى المتجر هنا ويُمرَّر إيصاله إلى نفس
  /// النداء — ولا يتغيّر شيء آخر في هذه الشاشة.
  Future<void> _buy(StoreProduct product) async {
    final api = context.read<ApiClient>();
    final premium = context.read<Premium>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyProduct = product.productId);
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
                      const BrandCard(
                        child: Text(
                          'الاشتراك متوقّف مؤقتاً.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Brand.textMuted),
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
                            : () => _buy(offer.crown),
                        child: _busyProduct == offer.crown.productId
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : Text('اشترك · ${offer.crown.label} شهرياً'),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'يتجدّد شهرياً، ويُلغى متى شئت من إعدادات المتجر.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Brand.textFaint, fontSize: 11.5),
                      ),
                    ],
                    const SizedBox(height: 26),
                    // مشتريات لمرة واحدة، لمن لا يريد اشتراكاً شهرياً:
                    // الأداة تُشترى وتُنفق وتنتهي، ولا تلتزم بشيء.
                    const BrandSectionLabel('أو اشترِ أدوات لمرة واحدة'),
                    const SizedBox(height: 10),
                    _PackCard(
                      icon: Icons.bolt,
                      title: '${offer.pack.size} مضاعِفات ×${offer.pack.factor}',
                      note: 'رصيدك الآن ${ent.boost.left} · تُنفق في أي دوري',
                      price: offer.pack.label,
                      busy: _busyProduct == offer.pack.productId,
                      onBuy: signedIn && offer.enabled
                          ? () => _buy(offer.pack)
                          : null,
                    ),
                    if (offer.shieldPack != null) ...[
                      const SizedBox(height: 10),
                      _PackCard(
                        icon: Icons.shield_outlined,
                        title: offer.shieldPack!.size == 1
                            ? 'درع سلسلة واحد'
                            : '${offer.shieldPack!.size} دروع سلسلة',
                        note: 'يحمي أول خطأ بعد شرائه · اشتريت '
                            '${ent.shield.purchased}',
                        price: offer.shieldPack!.label,
                        busy: _busyProduct == offer.shieldPack!.productId,
                        onBuy: signedIn && offer.enabled
                            ? () => _buy(offer.shieldPack!)
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
                  ],
                ),
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
