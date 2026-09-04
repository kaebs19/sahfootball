// premiumService — التاج الذهبي: من يملكه، وماذا يعطيه.
//
// كل امتياز في اللعبة يُسأل عنه من هنا، لا من شرط `premium_until >
// now()` مكتوب في كل مسار. السبب أن الامتيازات ستتبدّل (تجربة
// مجانية، منحة للمؤثّرين، عرض موسمي)، وشرطٌ منسوخ في عشرة ملفات
// يصير عشر قواعد متباعدة عند أول تبديل — وواحدة منها ستُنسى، فيدفع
// لاعبٌ ثمناً لا يحصل على مقابله.
//
// الامتيازات الأربعة، ولكلٍّ سببه في التصميم:
//   • بلا إعلانات        — الأوضح والأصدق: ما يُدفع مقابله يُرى فوراً.
//   • تعديل التوقّع      — قبل الصافرة فقط. بعدها لا أحد يعدّل، مهما دفع.
//   • مضاعِف ×5          — يُشترى، ويأتي منه ثلاثة شهرياً مع الاشتراك.
//   • درع السلسلة        — خطأ واحد لا يكسر السلسلة.
//
// والحدّ الذي لا يُتجاوز: **لا امتياز يمسّ نزاهة المنافسة**. لا
// تعديل بعد انطلاق المباراة، ولا رؤية توقّعات الآخرين قبل أوانها،
// ولا نقاط تُشترى. المضاعِف والدرع أدوات تُنفق قبل معرفة النتيجة —
// من اشتراهما راهن بهما ولم يشترِ نتيجة. لو بيع يوماً ما يُطبَّق
// بعد ظهور النتيجة، ماتت اللوحة كلها ومعها سبب وجود التطبيق.
const settingsRepo = require('../repositories/settingsRepo');
const purchaseRepo = require('../repositories/purchaseRepo');
const userRepo = require('../repositories/userRepo');

/** الإعدادات الاحتياطية — نسخة مطابقة لما تزرعه الهجرة 027. */
const DEFAULT_PREMIUM = {
  enabled: true,
  crown: {
    product_id: 'com.sahfootball.app.crown.monthly',
    price: 19,
    currency: 'SAR',
    days: 30,
    monthly_boosters: 3,
  },
  multiplier_pack: {
    product_id: 'com.sahfootball.app.multiplier5.pack',
    price: 15,
    currency: 'SAR',
    factor: 5,
    size: 5,
  },
  shield_pack: {
    product_id: 'com.sahfootball.app.shield.pack',
    price: 9,
    currency: 'SAR',
    size: 1,
  },
  free_edits: 0,
  shield: { every: 5, max: 1, premium_start: 1 },
  // الإعلانات: التفعيل ووحداتها.
  //
  // معرّفات الوحدات هنا لا في التطبيق لسببين: تغييرها لا يحتاج نشراً
  // ومراجعة متجر، وإطفاء وحدة تعطّلت يصير قراراً لحظياً. أما معرّف
  // التطبيق (GADApplicationIdentifier) فيبقى في Info.plist و
  // AndroidManifest لأن حزمة الإعلانات تقرؤه عند الإقلاع قبل أن
  // يصل أي ردّ من خادمنا.
  //
  // والوحدات هنا هي وحدات الحساب الحقيقية. و`test` مفتاح أمان لا
  // زينة: حين يكون true تُستبدل كلها بوحدات جوجل التجريبية مهما
  // كُتب هنا (راجع adUnits أدناه) — لأن الضغط على إعلان حقيقي في
  // تطبيقك أثناء التجربة مخالفةٌ يُغلق بها حساب AdMob، وهي أسهل
  // غلطة تقع في التطوير. فالتجربة بمفتاح، والإنتاج بمفتاح.
  ads: {
    enabled: true,
    test: false,
    ios: {
      banner: 'ca-app-pub-8219247197168750/9677590138',
      native: 'ca-app-pub-8219247197168750/7337482772',
    },
    android: {
      banner: 'ca-app-pub-8219247197168750/3398237769',
      native: 'ca-app-pub-8219247197168750/3292145185',
    },
  },
};

/** وحدات جوجل التجريبية — معلنة للجميع، تعرض إعلاناً بلا أرباح. */
const TEST_AD_UNITS = {
  ios: {
    banner: 'ca-app-pub-3940256099942544/2934735716',
    native: 'ca-app-pub-3940256099942544/3986624511',
  },
  android: {
    banner: 'ca-app-pub-3940256099942544/6300978111',
    native: 'ca-app-pub-3940256099942544/2247696110',
  },
};

/**
 * الوحدات المعمول بها: التجريبية حين يكون `test` مرفوعاً، وإلا
 * الحقيقية.
 *
 * التبديل في السيرفر لا في التطبيق: جهاز التجربة يصير آمناً بسطر
 * SQL واحد، ولا يحتاج نسخة ثانية من التطبيق ولا متغيّر بناء يُنسى
 * مرفوعاً في نسخة الإصدار.
 */
function adUnits(cfg) {
  const src = cfg.ads?.test ? TEST_AD_UNITS : cfg.ads;
  return {
    ios: src?.ios ?? TEST_AD_UNITS.ios,
    android: src?.android ?? TEST_AD_UNITS.android,
  };
}

class PremiumError extends Error {
  constructor(status, message, code = null) {
    super(message);
    this.status = status;
    this.expose = true;
    this.code = code;
  }
}

/** الإعدادات المعمول بها، مدموجة فوق الاحتياطية. */
async function config() {
  const saved = await settingsRepo.get('premium').catch(() => null);
  return { ...DEFAULT_PREMIUM, ...(saved || {}) };
}

/** هل هذا التاريخ ما زال سارياً؟ null أو ماضٍ = لا. */
const active = (until) => Boolean(until && new Date(until) > new Date());

/**
 * امتيازات لاعب واحد — الرد الذي يبني عليه التطبيق كل شاشاته.
 *
 * الشكل مقصود أن يكون "ما يستطيعه" لا "ما اشتراه": العميل يسأل
 * `can_edit` لا `premium && !expired && edits < n`. أي منطق يُترك
 * للعميل يُنسخ في نسختين (iOS وأندرويد) ويتباعد.
 */
async function forUser(userId) {
  const [cfg, user] = await Promise.all([config(), userRepo.findById(userId)]);
  if (!user) throw new PremiumError(404, 'الحساب غير موجود');

  const premium = cfg.enabled && active(user.premium_until);
  const [packs, shields] = await Promise.all([
    purchaseRepo.multiplierBalance(userId, cfg.multiplier_pack.factor),
    purchaseRepo.shieldDates(userId),
  ]);

  return {
    premium,
    premium_until: premium ? user.premium_until : null,
    // «هل تُعرض؟» و«أي وحدة؟» في كائن واحد: الشاشة تحتاجهما معاً،
    // وطلبٌ ثانٍ لمعرّفات الوحدات كان سيؤخّر الإعلان عن أول إطار.
    //
    // والوحدات تُرسل للمشترك أيضاً بقيمة show=false لا تُحذف: لو
    // انتهى اشتراكه أثناء الاستعمال لا نحتاج رحلة ثانية.
    ads: {
      show: Boolean(cfg.ads?.enabled) && !premium,
      test: Boolean(cfg.ads?.test),
      ...adUnits(cfg),
    },
    edits: {
      free: cfg.free_edits,
      // null = بلا حدّ. رقمٌ كبير كان سيُعرض في الواجهة يوماً.
      max: premium ? null : cfg.free_edits,
    },
    multiplier5: {
      factor: cfg.multiplier_pack.factor,
      ...packs,
    },
    // إعدادات الدرع وعدد ما اشتُري منه. أما كم بقي فعلاً فيأتي من
    // حساب السلسلة وحده (profileStats): الدرع يُنفق داخل ذلك المرور
    // الزمني، ورقمٌ ثانٍ يُحسب هنا بطريقة أخرى كان سيخالفه يوماً.
    shield: { ...shieldOptions(cfg, premium), purchased: shields.length },
    crown: cfg.crown,
    pack: cfg.multiplier_pack,
    shield_pack: cfg.shield_pack,
  };
}

/**
 * خيارات الدرع لهذا اللاعب — تُمرَّر إلى computeStreaks.
 *
 * تُقرأ من مكان واحد لأن الوسام والملف الشخصي يحسبان السلسلة
 * بنفس الدالة، ولو اختلف الدرع بينهما لظهر "أطول سلسلة 6" ووسام
 * "سلسلة خمسة" مطفأ بجانبه. (نفس التحذير المكتوب في badgeService.)
 */
function shieldOptions(cfg, premium) {
  const s = cfg.shield || DEFAULT_PREMIUM.shield;
  return {
    every: s.every,
    max: premium ? (s.max || 0) + (s.premium_start || 0) : s.max || 0,
    // درع المشترك: يبدأ به قبل أن يستحقّ شيئاً — هذا هو معنى
    // "حماية مرة واحدة" التي يشتريها.
    start: premium ? s.premium_start || 0 : 0,
  };
}

/**
 * خيارات الدرع كاملةً بمعرّف اللاعب — لحساب السلسلة.
 *
 * تضمّ تواريخ الدروع المشتراة، وهي ما يميّزها عن الخيارات المختصرة
 * في forUser: الحساب يحتاج "متى اشتُري" ليُدخله في وقته، والعرض لا
 * يحتاج إلا عددها.
 */
async function shieldFor(userId) {
  const [cfg, user, purchased] = await Promise.all([
    config(), userRepo.findById(userId), purchaseRepo.shieldDates(userId),
  ]);
  const premium = Boolean(cfg.enabled && active(user?.premium_until));
  return { ...shieldOptions(cfg, premium), purchased };
}

/**
 * تسجيل شراء ومنح ما يترتّب عليه.
 *
 * التمديد من الأبعد بين (الآن) و(نهاية اشتراكه الحالي): من جدّد
 * قبل انتهاء شهره لا يخسر أيامه الباقية. وهذا ليس كرماً — المتاجر
 * تجدّد تلقائياً قبل الانتهاء بيوم أو يومين، فالحساب من "الآن"
 * كان سيسرق يومين من كل مشترك كل شهر.
 *
 * ومعزّزات الاشتراك تُسجَّل صفّاً مستقلاً بمعرّف مشتقّ من معرّف
 * الاشتراك: وصولُ الإيصال مرتين لا يمنحها مرتين، لأن الثاني
 * يصطدم بقيد UNIQUE ويُهمَل بصمت.
 */
async function grant({ userId, kind, quantity = 1, platform = 'manual', externalId = null }) {
  if (!['crown', 'multiplier', 'shield'].includes(kind)) {
    throw new PremiumError(400, 'نوع الشراء غير معروف');
  }
  const cfg = await config();

  const row = await purchaseRepo.record({ userId, kind, quantity, platform, externalId });
  // مسجّل سلفاً — إيصال مكرّر. نرجع الحالة الراهنة بلا منح ثانٍ.
  if (!row) return { already: true, entitlements: await forUser(userId) };

  if (kind === 'crown') {
    const days = (cfg.crown.days || 30) * quantity;
    await userRepo.extendPremium(userId, days);

    const boosters = cfg.crown.monthly_boosters || 0;
    if (boosters > 0) {
      await purchaseRepo.record({
        userId,
        kind: 'multiplier',
        quantity: boosters * quantity,
        platform,
        externalId: externalId ? `${externalId}:boosters` : null,
      });
    }
  }

  return { already: false, entitlements: await forUser(userId) };
}

/** ما يُعرض في صفحة الشراء — عام بلا تسجيل دخول. */
async function products() {
  const cfg = await config();
  return {
    enabled: Boolean(cfg.enabled),
    crown: cfg.crown,
    multiplier_pack: cfg.multiplier_pack,
    shield_pack: cfg.shield_pack,
    // ما يعطيه التاج، نصّاً واحداً يقرأه التطبيق والموقع معاً —
    // وقائمتان تتباعدان عند أول امتياز يُضاف.
    perks: [
      { key: 'no_ads', title: 'بلا إعلانات', body: 'شاشات نظيفة، ولا شيء يقطع عليك المباراة.' },
      { key: 'edit', title: 'تعديل التوقّع', body: 'غيّر توقّعك ما دامت الصافرة لم تُطلق.' },
      {
        key: 'boosters',
        title: `${cfg.crown.monthly_boosters} معزّزات شهرياً`,
        body: `مضاعِف ×${cfg.multiplier_pack.factor} يصلك كل شهر مع اشتراكك.`,
      },
      {
        key: 'shield',
        title: 'درع السلسلة',
        body: `خطأ واحد لا يكسر سلسلتك. يُكتسب كل ${cfg.shield.every} توقّعات صحيحة، ومع التاج يبدأ معك درعٌ جاهز.`,
      },
    ],
  };
}

module.exports = {
  config, forUser, grant, products, shieldFor, shieldOptions, active,
  DEFAULT_PREMIUM, PremiumError,
};
