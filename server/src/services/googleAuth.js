// googleAuth — طبقة عزل للدخول بحساب جوجل من المتصفح.
//
// لماذا تدفّق OAuth بالتحويل لا زر جوجل بـ JavaScript؟
// زر Google Identity Services يحتاج سكربتاً من نطاق جوجل، وسياسة
// المحتوى عندنا تمنع السكربت الخارجي (script-src 'self'). ولو
// فتحناها لجوجل لفتحناها لكل ما تحمّله جوجل بدورها.
//
// وتدفّق التحويل أمتن أصلاً في موقع مخدوم من الخادم: لا سكربت،
// ولا وميض، ويعمل مع من يعطّل JavaScript. الثمن رحلتان بدل واحدة،
// وهما رحلتان لا يشعر بهما المستخدم.
//
// خطوات التدفّق:
//   1. نحوّل المستخدم إلى جوجل ومعه state عشوائي محفوظ في كوكي.
//   2. جوجل تعيده إلينا بـ code و state.
//   3. نطابق الـ state (حماية CSRF)، ثم نبدّل الـ code بتوكنات
//      من خادم إلى خادم — بمفتاحنا السري، فلا يستطيع أحد انتحاله.
//   4. نتحقق من توقيع id_token ومن أنه صادر لنا نحن.
const crypto = require('node:crypto');
const jwt = require('jsonwebtoken');
const jwksClient = require('jwks-rsa');

const AUTH_URL = 'https://accounts.google.com/o/oauth2/v2/auth';
const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const JWKS_URL = 'https://www.googleapis.com/oauth2/v3/certs';
// جوجل تصدر التوكنات بأحد هذين المُصدرين — كلاهما صحيح.
const ISSUERS = ['https://accounts.google.com', 'accounts.google.com'];

const TIMEOUT_MS = 10000;

const client = jwksClient({
  jwksUri: JWKS_URL,
  cache: true,
  cacheMaxAge: 10 * 60 * 1000,
});

const clientId = () => process.env.GOOGLE_CLIENT_ID;
const clientSecret = () => process.env.GOOGLE_CLIENT_SECRET;

/** هل الإعداد مكتمل؟ الواجهة تخفي الزر حين لا يكون. */
const isConfigured = () => Boolean(clientId() && clientSecret());

/**
 * عنوان الرجوع. يُبنى من SITE_URL لا من ترويسة الطلب: الترويسة
 * يكتبها العميل، ومن يزوّرها يوجّه رحلة التحقق إلى نطاقه.
 * ويجب أن يطابق حرفياً ما سُجّل في Google Cloud وإلا رفضت جوجل.
 */
function redirectUri() {
  const base = (process.env.SITE_URL || '').replace(/\/+$/, '');
  return `${base}/auth/google/callback`;
}

/** رابط جوجل الذي نحوّل إليه المستخدم. */
function authUrl(state) {
  const params = new URLSearchParams({
    client_id: clientId(),
    redirect_uri: redirectUri(),
    response_type: 'code',
    // openid يعطينا id_token، وemail وprofile يعطيانه البريد والاسم.
    // لا نطلب أكثر: كل صلاحية زائدة تظهر للمستخدم في شاشة الموافقة
    // وتجعله يتردد، ولا نحتاجها.
    scope: 'openid email profile',
    state,
    // select_account: من دخل بحساب خاطئ يستطيع تبديله. بدونها
    // تختار جوجل الحساب النشط بصمت ويعلق المستخدم فيه.
    prompt: 'select_account',
  });
  return `${AUTH_URL}?${params}`;
}

/** رمز state عشوائي — يُحفظ في كوكي ويُقارن عند العودة. */
const newState = () => crypto.randomBytes(16).toString('hex');

/**
 * يبدّل الـ code بتوكنات، ثم يتحقق من id_token.
 * يرجع { googleSub, email, emailVerified, name } أو يرمي.
 */
async function exchangeCode(code) {
  let res;
  try {
    res = await fetch(TOKEN_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        code,
        client_id: clientId(),
        client_secret: clientSecret(),
        redirect_uri: redirectUri(),
        grant_type: 'authorization_code',
      }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch (err) {
    throw invalid('تعذّر الوصول إلى جوجل');
  }

  if (!res.ok) {
    // نص الرد يحمل السبب الحقيقي (redirect_uri_mismatch مثلاً)،
    // ولا يُعرض للمستخدم — يذهب إلى اللوق.
    const detail = await res.text().catch(() => '');
    const err = invalid('فشل تسجيل الدخول بجوجل');
    err.detail = detail.slice(0, 300);
    throw err;
  }

  const { id_token: idToken } = await res.json();
  if (!idToken) throw invalid('رد جوجل بلا id_token');

  return verifyIdToken(idToken);
}

/**
 * جماهير (aud) التوكنات التي نقبلها من التطبيق.
 *
 * لجوجل أكثر من عميل عندنا لا واحد: عميل الويب (هو نفسه serverClientId
 * في التطبيق، وأندرويد يُصدر التوكن باسمه)، وعميل iOS الذي تُصدر
 * مكتبة GIDSignIn توكنها باسمه أحياناً. كلها عملاؤنا في نفس مشروع
 * Google Cloud، وتوثيق جوجل نفسه يقول: تحقق أن aud أحد معرّفات
 * عملاء تطبيقك — لا معرّف واحد بعينه.
 */
function appAudiences() {
  return [clientId(), process.env.GOOGLE_IOS_CLIENT_ID].filter(Boolean);
}

/**
 * التحقق من id_token.
 *
 * نتحقق رغم أن التوكن وصلنا من خادم جوجل مباشرة عبر TLS: الفحص
 * رخيص، وaudience تحديداً حاسم — بدونه أي توكن جوجل صالح من أي
 * تطبيق آخر يفتح حساباتنا.
 *
 * audience قابل للتمرير لنفس سبب appleAuth: رحلة الويب توكنها
 * باسم عميل الويب حصراً، ورحلة التطبيق تقبل قائمة عملائنا.
 */
async function verifyIdToken(idToken, { audience } = {}) {
  const decoded = jwt.decode(idToken, { complete: true });
  if (!decoded?.header?.kid) throw invalid('id_token غير قابل للفك');

  const key = await client.getSigningKey(decoded.header.kid);

  let payload;
  try {
    payload = jwt.verify(idToken, key.getPublicKey(), {
      algorithms: ['RS256'], // مثبّتة صراحة — قبول غيرها ثغرة معروفة
      issuer: ISSUERS,
      audience: audience || clientId(),
    });
  } catch (err) {
    throw invalid('فشل التحقق من توكن جوجل');
  }

  return {
    googleSub: payload.sub,
    email: payload.email ? String(payload.email).toLowerCase() : null,
    // جوجل تسمح بحسابات ببريد غير موثّق (نطاقات Workspace خاصة).
    // نرفض الربط ببريد غير موثّق — وإلا استطاع من يملك حساب جوجل
    // ببريد يدّعيه أن يستولي على حساب قائم عندنا.
    emailVerified: payload.email_verified === true,
    name: payload.name || null,
  };
}

function invalid(message) {
  const err = new Error(message);
  err.status = 401;
  err.expose = true;
  return err;
}

module.exports = {
  isConfigured, authUrl, newState, exchangeCode, redirectUri,
  verifyIdToken, appAudiences,
};
