// appleAuth — طبقة عزل للتحقق من توكنات Apple.
// كل ما يخص "كيف نتأكد أن هذا التوكن من Apple فعلاً" يسكن هنا.
//
// كيف يعمل التحقق؟
// الـ identityToken هو JWT موقّع بمفتاح Apple الخاص (RS256).
// Apple تنشر مفاتيحها العامة على رابط ثابت (JWKS = JSON Web Key Set)
// وتضع في ترويسة كل توكن حقل kid (key id) يحدد أي مفتاح وقّعه.
// نحن: نقرأ kid ← نجلب المفتاح العام المطابق ← نتحقق من التوقيع
// ومن أن المُصدر Apple والجمهور تطبيقُنا تحديداً.
const jwt = require('jsonwebtoken');
const jwksClient = require('jwks-rsa');

// قابلة للتجاوز عبر البيئة لغرض الاختبار الآلي فقط
// (نشغّل "Apple مزيفة" محلية بمفاتيحنا) — في الإنتاج تبقى الافتراضية.
const APPLE_ISSUER = process.env.APPLE_ISSUER || 'https://appleid.apple.com';
const APPLE_JWKS_URL = process.env.APPLE_JWKS_URL || 'https://appleid.apple.com/auth/keys';

// jwks-rsa تجلب المفاتيح وتخبئها في الذاكرة (10 دقائق) — لا نضرب
// سيرفرات Apple في كل تسجيل دخول، وتتحمل تدوير Apple لمفاتيحها.
const client = jwksClient({
  jwksUri: APPLE_JWKS_URL,
  cache: true,
  cacheMaxAge: 10 * 60 * 1000,
});

/**
 * يتحقق ويرجع { appleSub, email, emailVerified } أو يرمي خطأً.
 *
 * audience قابل للتمرير لأن لنا عميلين عند آبل لا واحداً: التطبيق
 * (Bundle ID) والموقع (Services ID)، ولكلٍّ توكن بجمهوره. والافتراض
 * هو التطبيق فيبقى نداؤه كما كان بلا وسيط.
 */
async function verifyIdentityToken(identityToken, { audience } = {}) {
  // فك بلا تحقق أولاً — فقط لقراءة kid من الترويسة لنعرف أي مفتاح نطلب.
  const decoded = jwt.decode(identityToken, { complete: true });
  if (!decoded?.header?.kid) {
    throw invalid('identity token غير قابل للفك');
  }

  const key = await client.getSigningKey(decoded.header.kid);

  let payload;
  try {
    // jwt.verify هنا يفحص أربعة أشياء دفعة واحدة:
    // التوقيع صحيح، لم تنته الصلاحية (exp)، المُصدر Apple (iss)،
    // والتوكن صادر لتطبيقنا نحن (aud = Bundle ID). فحص aud حاسم:
    // بدونه أي توكن Apple صالح من أي تطبيق آخر يدخل حساباتنا.
    payload = jwt.verify(identityToken, key.getPublicKey(), {
      algorithms: ['RS256'], // نثبّتها صراحة — قبول خوارزميات أخرى ثغرة معروفة
      issuer: APPLE_ISSUER,
      audience: audience || process.env.APPLE_BUNDLE_ID,
    });
  } catch (err) {
    throw invalid('فشل التحقق من توكن Apple');
  }

  return {
    appleSub: payload.sub, // المعرّف الدائم — مفتاح الربط
    // قد يكون بريد "إخفاء بريدي" (xxxx@privaterelay.appleid.com) —
    // بريد حقيقي يعمل، نتعامل معه كأي بريد.
    email: payload.email ? String(payload.email).toLowerCase() : null,
    // آبل ترسلها منطقيةً أحياناً ونصاً "true" أحياناً — وقراءتها
    // بلا تطبيع تجعل النص "false" صادقاً في JavaScript.
    emailVerified: payload.email_verified === true || payload.email_verified === 'true',
  };
}

function invalid(message) {
  const err = new Error(message);
  err.status = 401;
  err.expose = true;
  return err;
}

module.exports = { verifyIdentityToken };
