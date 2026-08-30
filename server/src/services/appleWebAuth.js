// appleWebAuth — الدخول بحساب Apple من المتصفح.
//
// ملف مستقل عن appleAuth رغم أن كليهما "دخول بآبل": ذاك يستقبل
// توكناً جاهزاً من التطبيق ويتحقق منه فقط، وهذا يدير رحلة OAuth
// كاملة بمفتاح خاص ورموز حالة وردٍّ يأتي بـ POST. المشترك بينهما
// هو التحقق وحده، وهو يسكن في appleAuth ويُستدعى من هنا.
//
// وتدفّق التحويل لا زر Apple بـ JavaScript، لنفس سبب جوجل تماماً:
// سياسة المحتوى عندنا تمنع السكربت الخارجي (script-src 'self').
//
// ثلاثة فروق عن جوجل، كلٌّ منها يكسر شيئاً لو نُسي:
//
// ١) السرّ ليس نصاً ثابتاً بل JWT نوقّعه نحن بمفتاح p8 (ES256)،
//    وصلاحيته ستة أشهر بحدّ أقصى. آبل لا تعطي "client secret"
//    يُنسخ ويُلصق — تعطي مفتاحاً نصنع به السرّ في كل مرة.
//
// ٢) الرد يأتي بـ POST لا GET (response_mode=form_post)، وهو
//    إلزامي متى طلبنا الاسم أو البريد. وهذا يجرّ الفرق الثالث.
//
// ٣) كوكي الـ state يجب أن يكون SameSite=None; Secure. المتصفح لا
//    يرسل كوكي SameSite=Lax مع طلب POST قادم من نطاق آخر — وهذا
//    بالضبط شكل ردّ آبل. ولو تركناها Lax (كما هي عند جوجل، وهي
//    صحيحة هناك لأن جوجل ترد بـ GET) لوصل الرد بلا كوكي، ولفشل
//    كل دخول بآبل برسالة "انتهت الجلسة" لا علاقة لها بالسبب.
//    وSameSite=None يوجب Secure، فالدخول بآبل لا يعمل على http.
const fs = require('node:fs');
const crypto = require('node:crypto');
const jwt = require('jsonwebtoken');
const appleAuth = require('./appleAuth');

const AUTH_URL = 'https://appleid.apple.com/auth/authorize';
const TOKEN_URL = 'https://appleid.apple.com/auth/token';
const APPLE_AUD = 'https://appleid.apple.com';

const TIMEOUT_MS = 10000;

// السرّ صالح ستة أشهر ونجدّده كل خمسة: لا داعي لتوقيع JWT في كل
// دخول، ولا لملامسة القرص. الهامش شهر كامل فلا يقع تجديد على حافة
// انتهاء.
const SECRET_TTL_MS = 150 * 24 * 60 * 60 * 1000;
let cachedSecret = null;
let cachedSecretAt = 0;

const servicesId = () => process.env.APPLE_SERVICES_ID;
const teamId = () => process.env.APPLE_SIGNIN_TEAM_ID || process.env.APNS_TEAM_ID;
const keyId = () => process.env.APPLE_SIGNIN_KEY_ID;
const keyPath = () => process.env.APPLE_SIGNIN_KEY_PATH;

/** هل الإعداد مكتمل؟ الواجهة تخفي الزر حين لا يكون. */
function isConfigured() {
  // SITE_URL شرطٌ كالبقية: بدونه يصير redirect_uri مساراً نسبياً
  // ("/auth/apple/callback")، فترفضه آبل برسالة invalid_request
  // عامة لا تدلّ على أن الناقص متغيّرُ بيئةٍ عندنا. غيابُ الزر
  // أوضح من زرٍّ يقود إلى خطأ لا يُفسَّر.
  return Boolean(process.env.SITE_URL && servicesId() && teamId() && keyId() && keyPath());
}

/**
 * عنوان الرجوع — من SITE_URL لا من ترويسة الطلب، كما عند جوجل:
 * الترويسة يكتبها العميل، ومن يزوّرها يوجّه رحلة التحقق لنطاقه.
 * ويجب أن يطابق حرفياً ما سُجّل في لوحة آبل وإلا رفضته.
 */
function redirectUri() {
  const base = (process.env.SITE_URL || '').replace(/\/+$/, '');
  return `${base}/auth/apple/callback`;
}

/** رمز state عشوائي — يُحفظ في كوكي ويُقارن عند العودة. */
const newState = () => crypto.randomBytes(16).toString('hex');

/** رابط آبل الذي نحوّل إليه المستخدم. */
function authUrl(state) {
  const params = new URLSearchParams({
    client_id: servicesId(),
    redirect_uri: redirectUri(),
    response_type: 'code',
    scope: 'name email',
    state,
    // إلزامي مع scope: آبل ترفض الطلب بـ invalid_request بدونه.
    response_mode: 'form_post',
  });
  return `${AUTH_URL}?${params}`;
}

/**
 * سرّ العميل: JWT موقّع بمفتاحنا الخاص.
 *
 * قراءة الملف كسولة ومخبّأة: خطأ في المسار يجب أن يظهر عند أول
 * محاولة دخول برسالة واضحة، لا أن يمنع الخادم من الإقلاع أصلاً —
 * الدخول بآبل ميزة، وتعطّلها لا يبرّر إسقاط الموقع كله.
 */
function clientSecret() {
  const now = Date.now();
  if (cachedSecret && now - cachedSecretAt < SECRET_TTL_MS) return cachedSecret;

  const key = fs.readFileSync(keyPath(), 'utf8');
  cachedSecret = jwt.sign({}, key, {
    algorithm: 'ES256',
    keyid: keyId(),
    issuer: teamId(),
    audience: APPLE_AUD,
    // sub هو Services ID لا Bundle ID: هذا سرّ عميل الويب.
    subject: servicesId(),
    expiresIn: '180d',
  });
  cachedSecretAt = now;
  return cachedSecret;
}

/**
 * يبدّل الـ code بتوكنات ويتحقق من id_token.
 * يرجع { appleSub, email, emailVerified } أو يرمي.
 */
async function exchangeCode(code) {
  let res;
  try {
    res = await fetch(TOKEN_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        code,
        client_id: servicesId(),
        client_secret: clientSecret(),
        redirect_uri: redirectUri(),
        grant_type: 'authorization_code',
      }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch (err) {
    throw invalid('تعذّر الوصول إلى Apple');
  }

  if (!res.ok) {
    // نص الرد يحمل السبب الحقيقي (invalid_client حين يكون المفتاح
    // أو Services ID خاطئاً) ويذهب للوق لا للمستخدم.
    const detail = await res.text().catch(() => '');
    const err = invalid('فشل تسجيل الدخول بآبل');
    err.detail = detail.slice(0, 300);
    throw err;
  }

  const { id_token: idToken } = await res.json();
  if (!idToken) throw invalid('رد آبل بلا id_token');

  // جمهور توكن الويب هو Services ID لا Bundle ID — لهذا نمرّره
  // صراحةً بدل الاعتماد على افتراض appleAuth الموجّه للتطبيق.
  return appleAuth.verifyIdentityToken(idToken, { audience: servicesId() });
}

/**
 * الاسم من ردّ آبل — إن وُجد.
 *
 * آبل ترسله مرة واحدة في العمر: في أول تفويض لهذا الحساب لهذا
 * التطبيق، داخل حقل user كنص JSON. من ألغى الوصول ثم عاد يحصل
 * على اسمه ثانية، ومن عدا ذلك لن يصلنا اسمه أبداً مهما دخل.
 * لذلك نحفظه فوراً إن جاء ولا ننتظر فرصة ثانية.
 */
function nameFrom(userField) {
  if (!userField) return null;
  try {
    const { name } = JSON.parse(userField);
    const full = [name?.firstName, name?.lastName].filter(Boolean).join(' ').trim();
    return full || null;
  } catch {
    return null; // نص مشوّه لا يستحق إسقاط تسجيل دخول صحيح
  }
}

function invalid(message) {
  const err = new Error(message);
  err.status = 401;
  err.expose = true;
  return err;
}

module.exports = { isConfigured, authUrl, newState, exchangeCode, redirectUri, nameFrom };
