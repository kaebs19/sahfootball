// authService — منطق المصادقة كاملاً في مكان واحد.
//
// لماذا طبقة service هنا بينما مسارات الكرة تستدعي الـ repo مباشرة؟
// مسارات الكرة "اقرأ وأرجع" — لا منطق. المصادقة فيها منطق حقيقي
// (تشفير، توكنات، أكواد استعادة، قواعد أمنية) يجب ألا يسكن في طبقة
// HTTP: غداً حين نضيف "تسجيل عبر Apple" سيعيد استخدام نفس الدوال.
const crypto = require('crypto');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const userRepo = require('../repositories/userRepo');
const refreshTokenRepo = require('../repositories/refreshTokenRepo');
const redis = require('../config/redis');
const { sendMail } = require('./mailer');
const mailTemplates = require('./mailTemplates');
const appleAuth = require('./appleAuth');
const googleAuth = require('./googleAuth');
const logger = require('../utils/logger');

// bcrypt: 12 جولة (cost factor). كل زيادة تضاعف زمن الحساب —
// 12 توازن جيد اليوم (~200ms): بطيء بما يكفي لإيلام من يجرب ملايين
// كلمات السر على dump مسروق، وسريع بما يكفي لتسجيل دخول عادي.
const BCRYPT_ROUNDS = 12;
const ACCESS_TOKEN_TTL = '15m';
const REFRESH_TOKEN_DAYS = 30;
const RESET_CODE_TTL_SECONDS = 10 * 60; // صلاحية رمز الاستعادة: 10 دقائق
const RESET_MAX_ATTEMPTS = 5;           // محاولات تخمين الرمز قبل إلغائه

// خطأ "متوقع" نميزه عن الأعطال الحقيقية: يحمل رمز حالة HTTP
// ورسالة آمنة للعرض. معالج الأخطاء في app.js يعرف كيف يتعامل معه.
class AuthError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
    this.expose = true;
  }
}

// ---------------------------------------------------------------
// أدوات داخلية
// ---------------------------------------------------------------

function normalizeEmail(email) {
  return String(email || '').trim().toLowerCase();
}

function validateEmail(email) {
  // فحص شكلي بسيط. الفحص الحقيقي الوحيد للبريد هو إرسال رسالة له —
  // regex معقد يرفض عناوين صحيحة أكثر مما يمنع خاطئة.
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new AuthError(400, 'صيغة البريد الإلكتروني غير صحيحة');
  }
}

function validatePassword(password) {
  if (typeof password !== 'string' || password.length < 8) {
    throw new AuthError(400, 'كلمة السر يجب أن تكون 8 أحرف على الأقل');
  }
  if (password.length > 72) {
    // حد bcrypt الفعلي: يتجاهل ما بعد 72 بايتاً بصمت — نرفض صراحة
    // بدل قبول كلمة سر يُحتسب منها جزء فقط.
    throw new AuthError(400, 'كلمة السر أطول من المسموح');
  }
}

// sha256 للتوكنات وأكواد الاستعادة (وليس bcrypt): هذه قيم عشوائية
// طويلة أصلاً لا تُخمَّن بالقواميس، فلا نحتاج بطء bcrypt المتعمد —
// نحتاج فقط ألا تُخزن خاماً.
function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

// الحساب الموقوف لا يدخل ولا يجدّد جلسته.
//
// نستدعيها *بعد* التحقق من الهوية دائماً (كلمة السر أو توكن Apple
// أو توكن تجديد صالح) وليس قبله: لو رددنا "هذا الحساب موقوف" لمن
// أدخل بريداً بكلمة سر خاطئة لأصبح المسار أداة استكشاف — يجرب
// بريدات ويعرف أيها مسجل عندنا من اختلاف الرسالة. نفس مبدأ الرسالة
// الموحدة في login.
//
// 403 وليس 401: البيانات صحيحة والهوية مثبتة، لكن الحساب ممنوع —
// وهو نفس الرمز الذي يرده requireAuth حتى يتعامل معه العميل بمنطق
// واحد أينما ظهر.
async function assertNotSuspended(userId) {
  const status = await userRepo.findSuspension(userId);
  if (!status?.suspended_at) return;
  throw new AuthError(403, status.suspended_reason
    ? `تم إيقاف حسابك: ${status.suspended_reason}`
    : 'تم إيقاف حسابك، تواصل مع الإدارة');
}

// إصدار زوج التوكنات لمستخدم.
async function issueTokens(userId) {
  const accessToken = jwt.sign(
    { sub: userId },              // sub = subject: صاحب التوكن (اصطلاح JWT قياسي)
    process.env.JWT_SECRET,
    { expiresIn: ACCESS_TOKEN_TTL }
  );

  // الـ refresh token ليس JWT — مجرد 64 بايتاً عشوائياً. لا يحتاج
  // حمل بيانات لأننا نبحث عنه في القاعدة على أي حال، والعشوائي
  // الخام أبسط وقابل للإبطال الفوري.
  const refreshToken = crypto.randomBytes(64).toString('hex');
  const expiresAt = new Date(Date.now() + REFRESH_TOKEN_DAYS * 24 * 3600 * 1000);
  await refreshTokenRepo.create({
    userId,
    tokenHash: sha256(refreshToken),
    expiresAt,
  });

  return { accessToken, refreshToken };
}

// ---------------------------------------------------------------
// العمليات العامة
// ---------------------------------------------------------------

async function register({ email, password, displayName }) {
  email = normalizeEmail(email);
  validateEmail(email);
  validatePassword(password);

  const existing = await userRepo.findByEmail(email);
  if (existing) {
    throw new AuthError(409, 'هذا البريد مسجل مسبقاً');
  }

  const passwordHash = await bcrypt.hash(password, BCRYPT_ROUNDS);
  const user = await userRepo.create({ email, passwordHash, displayName });
  const tokens = await issueTokens(user.id);
  return { user, ...tokens };
}

async function login({ email, password }) {
  email = normalizeEmail(email);

  const user = await userRepo.findByEmailWithHash(email);

  // رسالة واحدة موحدة للحالتين (بريد غير موجود / كلمة سر خاطئة):
  // التمييز بينهما يسمح لمهاجم بمعرفة أي البريدات مسجلة عندنا.
  const invalidError = new AuthError(401, 'بيانات الدخول غير صحيحة');
  // حساب Apple فقط (بلا كلمة سر): نرد بنفس الرسالة العامة —
  // رسالة مخصصة "هذا الحساب عبر Apple" كانت ستكشف لمن يجرب بريد
  // غيره أن الحساب موجود ومسجل بأي طريقة. تطبيق iOS يعرض للمستخدم
  // زر Apple بجانب النموذج على أي حال.
  if (user && !user.password_hash) {
    await bcrypt.compare(password || '', '$2b$12$invalidinvalidinvalidinvaluGJDDLKvVHnUnb3zMFtDbZQU4qEjcy');
    throw invalidError;
  }
  if (!user) {
    // نحرق زمن bcrypt حتى مع بريد غير موجود، وإلا كشف زمنُ الرد
    // الفرقَ: رد فوري = بريد غير مسجل، رد بطيء = مسجل.
    await bcrypt.compare(password || '', '$2b$12$invalidinvalidinvalidinvaluGJDDLKvVHnUnb3zMFtDbZQU4qEjcy');
    throw invalidError;
  }

  const ok = await bcrypt.compare(password || '', user.password_hash);
  if (!ok) throw invalidError;

  await assertNotSuspended(user.id);

  delete user.password_hash; // لا يغادر هذه الدالة أبداً
  const tokens = await issueTokens(user.id);
  return { user, ...tokens };
}

// تدوير التوكن: نبطل القديم ونصدر زوجاً جديداً في كل تجديد.
// الفائدة: التوكن المسروق يصلح لاستعمال واحد فقط، وأي استعمال
// لتوكن مبطل مؤشر اختراق واضح في السجلات.
async function refresh(refreshToken) {
  if (!refreshToken) throw new AuthError(400, 'refreshToken مطلوب');

  const session = await refreshTokenRepo.findValid(sha256(refreshToken));
  if (!session) throw new AuthError(401, 'الجلسة منتهية، سجل الدخول من جديد');

  // قبل الإبطال والتدوير: هل الحساب موقوف؟ الأدمن يبطل توكنات
  // التجديد لحظة الإيقاف، لكن الفحص هنا هو الضمانة الحقيقية —
  // توكن نجا لأي سبب (سباق زمني، إيقاف مباشر في القاعدة) لا يجب أن
  // يشتري جلسة جديدة. نفحص قبل revoke حتى لا نحرق توكن مستخدم
  // سيُرفع عنه الإيقاف بعد دقيقة.
  await assertNotSuspended(session.user_id);

  await refreshTokenRepo.revoke(session.id);
  const tokens = await issueTokens(session.user_id);
  const user = await userRepo.findById(session.user_id);
  return { user, ...tokens };
}

async function logout(refreshToken) {
  if (!refreshToken) return; // خروج بلا توكن = لا شيء نبطله، ليس خطأ
  const session = await refreshTokenRepo.findValid(sha256(refreshToken));
  if (session) await refreshTokenRepo.revoke(session.id);
}

async function changePassword(userId, { currentPassword, newPassword }) {
  validatePassword(newPassword);

  const user = await userRepo.findById(userId);
  const withHash = await userRepo.findByEmailWithHash(user.email);

  // حساب دخل بجوجل أو Apple: لا كلمة حالية ليتحقق منها أحد.
  //
  // كان هذا يرمي خطأً، فيبقى صاحب الحساب بلا طريقة لإضافة كلمة سر
  // إطلاقاً — ولو فقد وصوله لحساب جوجل فقد حسابه عندنا معه.
  //
  // نسمح بالتعيين بلا كلمة حالية: الجلسة نفسها إثبات هوية، والمستخدم
  // مسجّل دخول بالفعل. لا نطلب ما لا وجود له.
  if (withHash.password_hash) {
    const ok = await bcrypt.compare(currentPassword || '', withHash.password_hash);
    if (!ok) throw new AuthError(401, 'كلمة السر الحالية غير صحيحة');
  }

  const passwordHash = await bcrypt.hash(newPassword, BCRYPT_ROUNDS);
  await userRepo.updatePassword(userId, passwordHash);

  // نطرد كل الأجهزة الأخرى. التطبيق الحالي سيحصل على زوج توكنات
  // جديد من الرد فلا ينقطع.
  await refreshTokenRepo.revokeAllForUser(userId);
  const tokens = await issueTokens(userId);
  return tokens;
}

// تغيير البريد الإلكتروني للحساب المسجّل دخوله.
//
// لماذا نطلب كلمة السر الحالية وهو مسجّل دخول أصلاً؟
// لأن البريد ليس حقلاً عادياً في الملف الشخصي — هو قناة استعادة
// الحساب: من يملكه يطلب /forgot-password ويستلم الرمز ويعيّن كلمة سر
// جديدة. جلسة مفتوحة على جهاز غير مراقَب (هاتف منسي، متصفح أدمن
// مفتوح) تكفي حينها للاستيلاء على الحساب كاملاً بلا معرفة أي سر.
// كلمة السر الحالية تعيد إثبات أن من يجلس أمام الجهاز هو المالك،
// تماماً كما في changePassword.
async function changeEmail(userId, { newEmail, currentPassword }) {
  const email = normalizeEmail(newEmail);
  validateEmail(email);

  const current = await userRepo.findById(userId);
  if (!current) throw new AuthError(401, 'الحساب لم يعد موجوداً');

  const withHash = await userRepo.findByEmailWithHash(current.email);

  // حساب Apple فقط: لا كلمة سر نتحقق منها، فلا طريقة لإثبات
  // الملكية هنا. الرسالة صريحة — المستخدم مسجّل دخول، لا شيء نخفيه.
  // وبريده مربوط بهوية Apple على أي حال، وتغييره من عندنا يفكّ
  // المطابقة بلا فائدة له.
  if (!withHash.password_hash) {
    throw new AuthError(400, 'هذا الحساب مسجل عبر Apple ولا يمكن تغيير بريده من هنا');
  }

  const ok = await bcrypt.compare(currentPassword || '', withHash.password_hash);
  if (!ok) throw new AuthError(401, 'كلمة السر الحالية غير صحيحة');

  if (email === current.email) {
    throw new AuthError(400, 'هذا هو بريدك الحالي بالفعل');
  }
  // الفحص المسبق لأجل الرسالة العربية فقط؛ قيد UNIQUE في القاعدة هو
  // الحارس الحقيقي ضد السباق بين الفحص والتحديث.
  if (await userRepo.findByEmail(email)) {
    throw new AuthError(409, 'هذا البريد مسجل مسبقاً لحساب آخر');
  }

  const user = await userRepo.updateEmail(userId, email);

  // نطرد كل الجلسات الأخرى ونصدر زوجاً جديداً لهذا الجهاز — نفس
  // سلوك changePassword وللسبب نفسه بالضبط:
  //
  // البريد الجديد صار قناة الاستعادة، فمن يمسك جلسة أخرى على هذا
  // الحساب لم يعد قادراً على إثبات ملكيته له. والحالة التي نخشاها
  // معكوسة أيضاً: لو كان المغيِّر مهاجماً استولى على جلسة، فإخراج
  // الجلسات الأخرى يقطع طريق المالك الحقيقي — لكنه بالمقابل يجعل
  // الاختراق مرئياً فوراً (خروج مفاجئ) بدل بقائه صامتاً، والمالك
  // يستعيد حسابه بكلمة سره التي لم تتغير. الصمت أخطر من الإزعاج.
  //
  // الجهاز الحالي لا ينقطع: يأخذ التوكنات الجديدة من هذا الرد.
  await refreshTokenRepo.revokeAllForUser(userId);
  const tokens = await issueTokens(userId);
  return { user, ...tokens };
}

// تسجيل الدخول عبر Apple — يخدم الحالتين (أول مرة أو عودة).
//
// displayName يأتي من التطبيق وليس من التوكن: Apple تعطي الاسم
// لتطبيق iOS مرة واحدة فقط في أول تفويض ولا تضعه في الـ token
// أبداً، لذلك يجب أن يمرره التطبيق معه في أول طلب وإلا ضاع.
/**
 * الدخول بحساب جوجل — بعد أن تحقّقنا من التوكن في googleAuth.
 *
 * نفس منطق آبل بثلاث حالات، مع فرق واحد جوهري: نشترط أن يكون
 * البريد موثّقاً عند جوجل قبل الربط بحساب قائم. جوجل تسمح بحسابات
 * ببريد غير موثّق (نطاقات Workspace خاصة)، ومن يملك حساباً كهذا
 * ببريد يدّعيه كان سيستولي على حساب موجود عندنا بضغطة.
 *
 * آبل لا تحتاج هذا الشرط لأنها لا تُصدر توكناً لبريد لم تتحقق منه.
 */
async function loginWithGoogle(profile) {
  const { googleSub, email, emailVerified, name } = profile;

  // الحالة 1: نعرف هذا الـ google_sub — مستخدم عائد.
  let user = await userRepo.findByGoogleSub(googleSub);

  // الحالة 2: أول دخول بجوجل وبريده مسجّل عندنا — نربط الهويتين
  // بدل إنشاء حساب مكرر، بشرط أن جوجل تحققت من البريد.
  if (!user && email && emailVerified) {
    const existing = await userRepo.findByEmail(email);
    if (existing) {
      await userRepo.linkGoogleSub(existing.id, googleSub);
      user = existing;
    }
  }

  // الحالة 3: مستخدم جديد.
  if (!user) {
    if (!email) throw new AuthError(401, 'حساب جوجل بلا بريد — جرّب طريقة أخرى');
    if (!emailVerified) {
      throw new AuthError(401, 'بريد حساب جوجل غير موثّق — وثّقه ثم أعد المحاولة');
    }
    user = await userRepo.createWithGoogle({
      email, googleSub, displayName: name,
    });
  }

  // بعد إثبات جوجل للهوية: الحساب الموقوف لا يلتف على الإيقاف
  // بتبديل طريقة الدخول.
  await assertNotSuspended(user.id);
  const tokens = await issueTokens(user.id);
  return { user, ...tokens };
}

async function loginWithApple({ identityToken, displayName }) {
  if (!identityToken) throw new AuthError(400, 'identityToken مطلوب');

  const { appleSub, email } = await appleAuth.verifyIdentityToken(identityToken);

  // الحالة 1: نعرف هذا الـ apple_sub — مستخدم عائد، دخول مباشر.
  let user = await userRepo.findByAppleSub(appleSub);

  // الحالة 2: أول دخول Apple لكن بريده مسجل عندنا بكلمة سر —
  // نربط الهويتين بدل إنشاء حساب مكرر. الربط آمن لأن Apple تحقق
  // من ملكية البريد قبلنا: من يحمل توكن Apple صالحاً لبريد ما
  // فهو مالكه فعلاً. (بعدها يدخل بالطريقتين لنفس الحساب.)
  if (!user && email) {
    const existing = await userRepo.findByEmail(email);
    if (existing) {
      await userRepo.linkAppleSub(existing.id, appleSub);
      user = existing;
    }
  }

  // الحالة 3: مستخدم جديد كلياً.
  if (!user) {
    if (!email) {
      // نظرياً نادر جداً (Apple تضع البريد في التوكن)، لكن بدون
      // بريد لا نستطيع إنشاء الحساب — عمود email إلزامي عندنا.
      throw new AuthError(401, 'توكن Apple لا يحتوي بريداً، أعد المحاولة');
    }
    user = await userRepo.createWithApple({ email, appleSub, displayName });
  }

  // بعد إثبات Apple للهوية: الحساب الموقوف لا يلتف على الإيقاف
  // بتبديل طريقة الدخول. (حساب أُنشئ للتو لا يمكن أن يكون موقوفاً،
  // لكن الفحص هنا يغطي المسارات الثلاثة أعلاه بسطر واحد.)
  await assertNotSuspended(user.id);

  const tokens = await issueTokens(user.id);
  return { user, ...tokens };
}

// طلب استعادة كلمة السر — الخطوة 1.
async function forgotPassword(email) {
  email = normalizeEmail(email);

  const user = await userRepo.findByEmail(email);
  // بريد غير مسجل: نرجع بصمت وكأن كل شيء تم. الرد الموحد يمنع
  // استخدام هذا المسار لاكتشاف البريدات المسجلة (نفس مبدأ login).
  if (!user) {
    logger.info(`[auth] password reset requested for unknown email`);
    return;
  }

  // رمز 6 أرقام مع صفر بادئ محتمل (000042 صالح).
  // crypto.randomInt وليس Math.random: الثاني قابل للتنبؤ ولا
  // يصلح لأي قيمة أمنية.
  const code = crypto.randomInt(0, 1000000).toString().padStart(6, '0');

  // الرمز في Redis لا القاعدة: بيانات قصيرة العمر بامتياز،
  // وانتهاء الصلاحية التلقائي (TTL) يغنينا عن تنظيف يدوي.
  // نخزن hash الرمز + عدّاد محاولات، بصلاحية 10 دقائق.
  const key = `auth:reset:${user.id}`;
  await redis.set(key, JSON.stringify({ codeHash: sha256(code), attempts: 0 }),
    'EX', RESET_CODE_TTL_SECONDS);

  // الرمز محفوظ فعلاً في Redis، فلو فشل الإرسال (مزوّد معطّل، حد
  // يومي) لا نُبقي المستخدم أمام نجاح كاذب ينتظر بعده بريداً لن يصل:
  // نمسح الرمز ونترك الخطأ يصعد ليرد السيرفر بفشل واضح. (نعم، هذا
  // يفرّق بين بريد مسجّل وغيره حين يكون المزوّد معطّلاً — لكن ذلك
  // عطل معلن أصلاً، وإخفاؤه يعني ترك المستخدم ينتظر إلى الأبد.)
  try {
    await sendMail({
      to: email,
      ...mailTemplates.resetCode({ code, ttlMinutes: RESET_CODE_TTL_SECONDS / 60 }),
    });
  } catch (err) {
    await redis.del(key);
    logger.error('[auth] فشل إرسال رمز الاستعادة:', err.message);
    throw err;
  }
}

// استعادة كلمة السر — الخطوة 2: التحقق من الرمز وتعيين كلمة جديدة.
async function resetPassword({ email, code, newPassword }) {
  email = normalizeEmail(email);
  validatePassword(newPassword);

  const genericError = new AuthError(401, 'الرمز غير صحيح أو منتهي الصلاحية');

  const user = await userRepo.findByEmail(email);
  if (!user) throw genericError;

  const key = `auth:reset:${user.id}`;
  const raw = await redis.get(key);
  if (!raw) throw genericError; // لا رمز مطلوباً أو انتهت العشر دقائق

  const entry = JSON.parse(raw);

  // حد المحاولات: 6 أرقام = مليون احتمال فقط، وبدون هذا الحد
  // يمكن تجربتها كلها آلياً خلال الدقائق العشر.
  if (entry.attempts >= RESET_MAX_ATTEMPTS) {
    await redis.del(key);
    throw genericError;
  }

  if (sha256(String(code)) !== entry.codeHash) {
    entry.attempts += 1;
    // KEEPTTL: حدّث القيمة دون تصفير مؤقت العشر دقائق.
    await redis.set(key, JSON.stringify(entry), 'KEEPTTL');
    throw genericError;
  }

  await redis.del(key); // الرمز يُستهلك مرة واحدة
  const passwordHash = await bcrypt.hash(newPassword, BCRYPT_ROUNDS);
  await userRepo.updatePassword(user.id, passwordHash);
  await refreshTokenRepo.revokeAllForUser(user.id);

  // نسجل دخوله مباشرة — أنهى للتو إثبات ملكية البريد،
  // إجباره على تسجيل دخول إضافي بيروقراطية بلا فائدة أمنية.
  const tokens = await issueTokens(user.id);
  return { user, ...tokens };
}


// حذف المستخدم حسابَه بنفسه — لا تراجع.
//
// لماذا مسار منفصل عن حذف الأدمن رغم أنهما ينتهيان لنفس الدالة؟
// لأن الحارس مختلف: الأدمن يُحرَس بدوره، والمستخدم يُحرَس بكلمة
// سره. جلسة مفتوحة على هاتف منسي تكفي لمحو حساب كامل بلا هذا
// الفحص — وهو محو نهائي لا استعادة بعده، أخطر من تغيير البريد
// الذي نطلب له الكلمة أصلاً.
//
// حساب Apple لا كلمة له: إعادة إثبات الهوية عنده تكون بتوكن Apple
// جديد، وهو ما يرسله التطبيق في appleIdentityToken.
async function deleteAccount(userId, { password, appleIdentityToken, confirmEmail }) {
  const user = await userRepo.findById(userId);
  if (!user) throw new AuthError(401, 'الحساب لم يعد موجوداً');

  const withHash = await userRepo.findByEmailWithHash(user.email);

  // تأكيد إضافي قبل فعل لا رجعة فيه. الجلسة وحدها لا تكفي: جهاز
  // مفتوح تركه صاحبه لحظة يكفي لمحو حسابه. لكن شكل التأكيد يتبع ما
  // يملكه الحساب فعلاً — وطلبُ ما لا وجود له يجعل الحذف مستحيلاً.
  if (withHash?.password_hash) {
    const ok = await bcrypt.compare(password || '', withHash.password_hash);
    if (!ok) throw new AuthError(401, 'كلمة السر غير صحيحة');
  } else if (withHash?.apple_sub) {
    // حساب Apple: نتحقق أن التوكن الجديد يخص نفس الحساب — توكن
    // صالح لشخص آخر لا يأذن بحذف هذا الحساب.
    if (!appleIdentityToken) {
      throw new AuthError(400, 'أعد تسجيل الدخول عبر Apple لتأكيد الحذف');
    }
    const claims = await appleAuth.verifyIdentityToken(appleIdentityToken);
    if (!claims?.sub || claims.sub !== withHash.apple_sub) {
      throw new AuthError(401, 'تأكيد Apple لا يخص هذا الحساب');
    }
  } else {
    // حساب جوجل (أو أي مزوّد بلا كلمة سر): لا كلمة نتحقق منها ولا
    // توكن نطلبه في المتصفح. كان هذا الفرع يطلب توكن Apple فيصير
    // الحساب غير قابل للحذف إطلاقاً — وهو خرق لحق المستخدم في محو
    // بياناته، ومخالف لشرط App Store الذي بُني عليه هذا المسار.
    //
    // البديل: كتابة البريد كاملاً. لا يمنع صاحب الجلسة، ويمنع
    // الضغطة العابرة — وهو الخطر الحقيقي هنا.
    const typed = String(confirmEmail || '').trim().toLowerCase();
    if (typed !== String(user.email).toLowerCase()) {
      throw new AuthError(400, 'اكتب بريد حسابك كاملاً لتأكيد الحذف');
    }
  }

  // إبطال الجلسات قبل الحذف: الحذف يجرّها معه بالـ CASCADE، لكن لو
  // فشل بعد ذلك لأي سبب لا نريد جلسات حية على حساب طلب صاحبه محوه.
  await refreshTokenRepo.revokeAllForUser(userId);

  const result = await userRepo.removeWithGroupHandover(userId);
  if (!result.ok) {
    if (result.reason === 'last_admin') {
      throw new AuthError(400, 'أنت آخر أدمن — عيّن أدمن آخر قبل حذف حسابك');
    }
    throw new AuthError(404, 'الحساب لم يعد موجوداً');
  }

  return result;
}

/**
 * ما الذي يملكه هذا الحساب؟ تستعمله الواجهة لتعرض النموذج الصحيح:
 * "تعيين كلمة مرور" لمن لا يملكها، و"تغييرها" لمن يملكها، وتأكيد
 * الحذف بالبريد لمن لا كلمة له.
 */
async function credentials(userId) {
  const user = await userRepo.findById(userId);
  if (!user) return null;
  const withHash = await userRepo.findByEmailWithHash(user.email);
  return {
    email: user.email,
    hasPassword: Boolean(withHash?.password_hash),
    hasApple: Boolean(withHash?.apple_sub),
    hasGoogle: Boolean(withHash?.google_sub),
  };
}

module.exports = {
  register, login, loginWithApple, loginWithGoogle, refresh, logout,
  credentials,
  changePassword, changeEmail, forgotPassword, resetPassword,
  deleteAccount,
  AuthError,
};
