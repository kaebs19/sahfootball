// التاج الذهبي — الاشتراك وما يعطيه.
//
// الشكل هنا يعكس ردّ السيرفر حرفياً، وهو ردّ "ما تستطيعه" لا "ما
// اشتريته": الشاشة تسأل `canEdit` لا `premium && !expired && …`.
// أي منطق يُترك للعميل يُنسخ في نسختين (iOS وأندرويد) ويتباعد،
// وامتيازٌ يُحسب في مكانين يُمنح في مكان ويُمنع في آخر.

/// درع السلسلة: كم درعاً بحوزته، وكم يفصله عن التالي.
class ShieldState {
  final int stock;
  final int max;

  /// كم إصابة تفصله عن درع جديد. null = بلغ الحدّ الأقصى.
  final int? nextIn;

  const ShieldState({this.stock = 0, this.max = 0, this.nextIn});

  bool get active => stock > 0;
  bool get available => max > 0;

  factory ShieldState.fromJson(Map<String, dynamic> j) => ShieldState(
        stock: (j['stock'] as num?)?.toInt() ?? 0,
        max: (j['max'] as num?)?.toInt() ?? 0,
        nextIn: (j['next_in'] as num?)?.toInt(),
      );
}

/// رصيد المضاعِف المشترى ×5.
class BoostBalance {
  final int factor;
  final int bought;
  final int used;
  final int left;

  const BoostBalance({
    this.factor = 5,
    this.bought = 0,
    this.used = 0,
    this.left = 0,
  });

  factory BoostBalance.fromJson(Map<String, dynamic> j) => BoostBalance(
        factor: (j['factor'] as num?)?.toInt() ?? 5,
        bought: (j['bought'] as num?)?.toInt() ?? 0,
        used: (j['used'] as num?)?.toInt() ?? 0,
        left: (j['left'] as num?)?.toInt() ?? 0,
      );
}

class Entitlements {
  final bool premium;
  final DateTime? premiumUntil;

  /// هل تُعرض الإعلانات لهذا اللاعب؟ (المشترك: لا.)
  final bool ads;

  /// null = تعديل بلا حدّ. 0 = لا تعديل إلا بالتاج.
  final int? editsMax;

  final BoostBalance boost;
  final ShieldState shield;

  const Entitlements({
    this.premium = false,
    this.premiumUntil,
    this.ads = false,
    this.editsMax = 0,
    this.boost = const BoostBalance(),
    this.shield = const ShieldState(),
  });

  /// الحالة قبل وصول أي ردّ: لا تاج ولا إعلانات.
  ///
  /// الإعلانات مطفأة في الافتراضي عمداً: وميضُ إعلان يظهر ثم يختفي
  /// حين يصل الردّ ويقول "هذا مشترك" أسوأ من إعلان متأخر بثانية.
  static const unknown = Entitlements();

  bool get canEdit => editsMax == null || editsMax! > 0;

  factory Entitlements.fromJson(Map<String, dynamic> j) => Entitlements(
        premium: j['premium'] == true,
        premiumUntil: j['premium_until'] != null
            ? DateTime.tryParse(j['premium_until'] as String)?.toLocal()
            : null,
        ads: j['ads'] == true,
        editsMax: (j['edits']?['max'] as num?)?.toInt(),
        boost: BoostBalance.fromJson(
            (j['multiplier5'] as Map<String, dynamic>?) ?? const {}),
        shield: ShieldState.fromJson(
            (j['shield'] as Map<String, dynamic>?) ?? const {}),
      );
}

/// ميزة واحدة في صفحة الشراء — نصّها من السيرفر لا من التطبيق.
///
/// السبب أن قائمة المزايا تتغيّر مع العروض، ونصٌّ مكتوب في التطبيق
/// يحتاج نشراً جديداً ومراجعة متجر لتصحيح كلمة — بينما ما يظهر
/// للمشتري يجب أن يكون قابلاً للتصحيح اليوم.
class Perk {
  final String key;
  final String title;
  final String body;

  const Perk({required this.key, required this.title, required this.body});

  factory Perk.fromJson(Map<String, dynamic> j) => Perk(
        key: (j['key'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        body: (j['body'] ?? '') as String,
      );
}

/// منتج قابل للشراء.
class StoreProduct {
  final String productId;
  final num price;
  final String currency;

  /// حجم الحزمة (للمضاعِفات) أو أيام الاشتراك.
  final int? size;
  final int? factor;

  const StoreProduct({
    required this.productId,
    required this.price,
    required this.currency,
    this.size,
    this.factor,
  });

  /// السعر كما يُعرض قبل وصول سعر المتجر الحقيقي.
  ///
  /// آبل تشترط عرض سعرها هي بعملة المشتري، فهذا نصّ احتياطي لا
  /// أكثر — وحين تُوصَل المشتريات داخل التطبيق يُستبدل بسعر المتجر.
  String get label => '$price ${currency == 'SAR' ? 'ر.س' : currency}';

  factory StoreProduct.fromJson(Map<String, dynamic> j) => StoreProduct(
        productId: (j['product_id'] ?? '') as String,
        price: (j['price'] as num?) ?? 0,
        currency: (j['currency'] ?? 'SAR') as String,
        size: (j['size'] as num?)?.toInt(),
        factor: (j['factor'] as num?)?.toInt(),
      );
}

class PremiumOffer {
  final bool enabled;
  final StoreProduct crown;
  final StoreProduct pack;
  final List<Perk> perks;

  const PremiumOffer({
    required this.enabled,
    required this.crown,
    required this.pack,
    required this.perks,
  });

  factory PremiumOffer.fromJson(Map<String, dynamic> j) => PremiumOffer(
        enabled: j['enabled'] == true,
        crown: StoreProduct.fromJson(j['crown'] as Map<String, dynamic>),
        pack:
            StoreProduct.fromJson(j['multiplier_pack'] as Map<String, dynamic>),
        perks: (j['perks'] as List? ?? [])
            .map((e) => Perk.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
