// siteSettings — إعدادات الموقع العام (اسمه، وصفه، بريده، روابطه).
//
// تُخزَّن في app_settings تحت المفتاح 'site' عبر settingsRepo —
// نفس مسار إعدادات النقاط، فلا جدول جديد ولا هجرة لكل حقل يُضاف.
//
// ── اصطلاح الفراغ: نص فارغ '' وليس null ──────────────────────────
// كل حقل موجود دائماً في الرد، والقيمة الفارغة تعني "غير مُعدّ".
// لماذا نثبّت واحداً بدل قبول الاثنين؟ لأن الموقع يقرر بها ماذا
// يخفي: شرط بسيط مثل if (social.x) يعمل مع الاثنين، لكن حقلاً
// يظهر أحياناً null وأحياناً '' وأحياناً يغيب كلياً يفرض على كل
// من يستهلك الـ API (الموقع، اللوحة، التطبيق) كتابة نفس الفحص
// الدفاعي الثلاثي. والنص الفارغ تحديداً لأن مصدر هذه القيم مربعات
// نص في اللوحة، ومربع نص أُفرغ يرسل '' لا null.
const settingsRepo = require('../repositories/settingsRepo');

// الشبكات المدعومة. القائمة مغلقة عمداً: الموقع يعرف أيقونة كل
// واحدة منها، فمفتاح غريب هنا لا شيء يرسمه.
const SOCIAL_KEYS = ['x', 'instagram', 'tiktok', 'youtube', 'snapchat', 'linkedin'];

// القيم الافتراضية — تُستعمل حين لا يوجد صف 'site' بعد (قاعدة
// جديدة، أو قبل أول حفظ من اللوحة). الموقع يجب أن يعرض شيئاً
// معقولاً قبل أن يلمس الأدمن الإعدادات أصلاً.
const DEFAULT_SITE_SETTINGS = {
  siteName: 'ملك التوقعات',
  tagline: 'توقّع بذكاء. اجمع التاج. اجلس على العرش.',
  description:
    'لعبة توقّعات كرة قدم عربية: توقّع نتائج المباريات، اجمع النقاط، ونافس أصدقاءك في قروب خاص أو في لوحة الصدارة العامة.',
  contactEmail: '',
  supportEmail: '',
  social: Object.fromEntries(SOCIAL_KEYS.map((k) => [k, ''])),
  appStoreUrl: '',
  googlePlayUrl: '',
};

// أطوال قصوى تحرس القاعدة والواجهة معاً: وصف بطول كتاب يكسر
// وسوم <meta> في رأس الصفحة قبل أن يكسر أي شيء آخر.
const MAX = { siteName: 60, tagline: 160, description: 600, url: 500, email: 160 };

// فحص شكل البريد فقط — لا وجوده. التحقق الحقيقي الوحيد من بريد
// هو إرسال رسالة إليه، وهذا ليس مكانه.
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

function isHttpUrl(value) {
  try {
    const parsed = new URL(value);
    // http/https فقط: هذه القيم تخرج إلى href في الموقع، فتنطبق
    // عليها نفس حجة safeMarkdown — javascript: في رابط "متجر
    // التطبيق" شيفرة تعمل بضغطة زائر.
    return parsed.protocol === 'http:' || parsed.protocol === 'https:';
  } catch {
    return false;
  }
}

// نص مُنظَّف: نقبل غير النص كأنه فارغ بدل رفضه، لأن الحقول
// النصية اختيارية أصلاً ولا فائدة من إفشال الحفظ كله بسببها.
function str(value) {
  return typeof value === 'string' ? value.trim() : '';
}

// القراءة: ندمج المخزَّن فوق الافتراضي. الدمج (لا الإرجاع كما هو)
// يضمن أن حقلاً أُضيف اليوم إلى الشكل يظهر بقيمته الافتراضية في
// صفوف حُفظت قبل إضافته — بدلاً من undefined يكسر الموقع.
async function get() {
  const stored = (await settingsRepo.get('site')) ?? {};
  return {
    ...DEFAULT_SITE_SETTINGS,
    ...stored,
    social: { ...DEFAULT_SITE_SETTINGS.social, ...(stored.social ?? {}) },
  };
}

// التحقق والبناء. ترجع { error } أو { value }.
//
// المبدأ نفسه المتبع في settings/scoring و leagues: نبني الكائن
// المخزَّن حقلاً حقلاً من قائمة معروفة، فلا يتسرب أي مفتاح إضافي
// من جسم الطلب إلى JSONB. القائمة السوداء ("امنع هذه المفاتيح")
// تفشل صامتة مع أول مفتاح لم يخطر ببال كاتبها.
//
// الحقل الغائب من الطلب يبقى على قيمته الحالية (current): محرّر
// اللوحة قد يرسل قسماً واحداً من النموذج، والأصل ألا يمسح إرسال
// جزئي بقية الإعدادات.
function build(input, current) {
  const body = input && typeof input === 'object' ? input : {};
  const pick = (key) => (body[key] === undefined ? current[key] : str(body[key]));

  const siteName = pick('siteName');
  if (!siteName) {
    return { error: 'اسم الموقع مطلوب' };
  }
  if (siteName.length > MAX.siteName) {
    return { error: `اسم الموقع أطول من ${MAX.siteName} حرفاً` };
  }

  const tagline = pick('tagline');
  if (tagline.length > MAX.tagline) {
    return { error: `الشعار أطول من ${MAX.tagline} حرفاً` };
  }

  const description = pick('description');
  if (description.length > MAX.description) {
    return { error: `الوصف أطول من ${MAX.description} حرفاً` };
  }

  const emails = {};
  for (const [key, label] of [['contactEmail', 'بريد التواصل'], ['supportEmail', 'بريد الدعم']]) {
    const value = pick(key);
    // الفراغ مسموح ويعني "غير مُعدّ" — الشرط يفحص المكتوب فقط.
    if (value && (!EMAIL_RE.test(value) || value.length > MAX.email)) {
      return { error: `${label} غير صالح` };
    }
    emails[key] = value;
  }

  const urls = {};
  for (const [key, label] of [['appStoreUrl', 'رابط App Store'], ['googlePlayUrl', 'رابط Google Play']]) {
    const value = pick(key);
    if (value && (!isHttpUrl(value) || value.length > MAX.url)) {
      return { error: `${label} يجب أن يكون رابطاً يبدأ بـ http أو https` };
    }
    urls[key] = value;
  }

  // الشبكات: نمر على المفاتيح الستة المعروفة لا على مفاتيح الطلب —
  // وهذا ما يُسقط أي شبكة غير مدعومة يرسلها أحد.
  const incomingSocial =
    body.social && typeof body.social === 'object' ? body.social : {};
  const social = {};
  for (const key of SOCIAL_KEYS) {
    const value =
      incomingSocial[key] === undefined ? current.social[key] : str(incomingSocial[key]);
    if (value && (!isHttpUrl(value) || value.length > MAX.url)) {
      return { error: `رابط ${key} يجب أن يكون رابطاً يبدأ بـ http أو https` };
    }
    social[key] = value;
  }

  return {
    value: {
      siteName,
      tagline,
      description,
      contactEmail: emails.contactEmail,
      supportEmail: emails.supportEmail,
      social,
      appStoreUrl: urls.appStoreUrl,
      googlePlayUrl: urls.googlePlayUrl,
    },
  };
}

// الحفظ: يقرأ الحالي أولاً ليتمكن build من إبقاء ما لم يُرسل.
async function update(input) {
  const current = await get();
  const result = build(input, current);
  if (result.error) return result;

  await settingsRepo.set('site', result.value);
  return { value: result.value };
}

module.exports = { get, update, DEFAULT_SITE_SETTINGS, SOCIAL_KEYS };
