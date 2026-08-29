// routes/pages — الموقع العام كصفحات HTML.
//
// هذا الراوتر يخدم البشر بالمتصفح، بعكس بقية المسارات التي تخدم
// التطبيق والـ لوحة بـ JSON. لذلك يعيش على الجذر (/, /privacy…)
// لا تحت /api، والروابط تبقى قصيرة صالحة للنشر:
// malikaltawaquat.com/privacy لا .../api/site/pages/privacy.
//
// كل محتواه من قاعدة البيانات (site_pages و app_settings)، فتعديل
// كلمة من لوحة التحكم يظهر في الطلب التالي بلا إعادة بناء ولا نشر.
const crypto = require('node:crypto');
const express = require('express');
const siteRepo = require('../repositories/siteRepo');
const siteFixtureRepo = require('../repositories/siteFixtureRepo');
const leagueRepo = require('../repositories/leagueRepo');
const standingsService = require('../services/standingsService');
const matchDetailService = require('../services/matchDetailService');
const siteSettings = require('../services/siteSettings');
const renderer = require('../services/siteRenderer');
const authService = require('../services/authService');
const webSession = require('../services/webSession');
const userRepo = require('../repositories/userRepo');
const predictionRepo = require('../repositories/predictionRepo');
const logger = require('../utils/logger');

const router = express.Router();

// النموذج في صفحة "اتصل بنا" يرسل بترميز النماذج التقليدي، لا JSON.
// express.json() المركّب في app.js لا يفكّه، فنضيف المفكّك هنا
// ومحصوراً بهذا الراوتر — لا داعي لأن تفهم مسارات الـ API صيغة
// نماذج المتصفح.
router.use(express.urlencoded({ extended: false }));

// الصفحات التي لها مسار عام. أي slug آخر في القاعدة يبقى غير
// منشور — قائمة بيضاء صريحة كي لا يصبح إدخال صف في الجدول نشراً
// لصفحة على الموقع بلا قصد.
const PUBLIC_SLUGS = new Set(['privacy', 'terms', 'about', 'contact']);

// siteSettings.get لا settingsRepo.get('site') مباشرة: الأولى تدمج
// القيم الافتراضية فوق المخزَّن، فحقل يُضاف للإعدادات لاحقاً لا يصل
// القالب كـ undefined ويطبع "undefined" في صفحة يراها الزوار.
async function loadSettings() {
  // فشل قراءة الإعدادات يجب ألا يُسقط الموقع: نرجع كائناً فارغاً
  // فيعرض المُصيّر القيم الافتراضية ويخفي ما لم يُضبط.
  try {
    return (await siteSettings.get()) ?? {};
  } catch (err) {
    logger.error('[pages] settings load failed:', err.message);
    return {};
  }
}

// الصفحة الرئيسية
// الصفحة الرئيسية = مباريات اليوم.
//
// كل البيانات من قاعدتنا لا من المزوّد: المزامن يملؤها دورياً،
// فزائر الموقع مهما كثر لا يكلّف طلباً خارجياً واحداً. صفحة عامة
// تنادي مزوّداً محدود الحصة تسقط عند أول انتشار.
router.get('/', async (req, res) => {
  // تحقق من الشكل لا مجرد الوجود: القيمة تدخل الاستعلام، ونص
  // عشوائي يجب أن يعود لليوم لا أن يرمي.
  const asked = String(req.query.date || '');
  const day = /^\d{4}-\d{2}-\d{2}$/.test(asked) ? asked : renderer.riyadhToday();
  const league = /^\d+$/.test(String(req.query.league || '')) ? Number(req.query.league) : null;

  const [settings, all, days, leagues] = await Promise.all([
    loadSettings(),
    siteFixtureRepo.byDate(day),
    siteFixtureRepo.daysAround(renderer.riyadhToday()),
    leagueRepo.findEnabled(),
  ]);

  // الترشيح في الذاكرة لا في SQL: الصفوف عشرات لا آلاف، والاستعلام
  // نفسه يخدم "الكل" و"دوري واحد" فلا يتفرّع.
  const fixtures = league ? all.filter((f) => f.league_id === league) : all;

  res.type('html').send(
    renderer.renderMatches(settings, { day, fixtures, days, leagues, league })
  );
});
// صفحة اتصل بنا — قبل /:slug لأن لها معالجاً خاصاً (نموذج + POST)
router.get('/contact', async (req, res) => {
  const [settings, page] = await Promise.all([
    loadSettings(),
    siteRepo.getPage('contact'),
  ]);
  res.type('html').send(
    renderer.renderContact(page, settings, { sent: req.query.sent === '1' })
  );
});

// استقبال رسالة تواصل.
//
// بعد النجاح نحوّل بـ 303 بدل عرض الصفحة مباشرة (نمط
// POST/Redirect/GET): بدونه يبقى الطلب من نوع POST في سجل
// المتصفح، فتحديث الصفحة يعيد إرسال الرسالة نفسها ويكرّرها في
// صندوق الإدارة.
router.post('/contact', async (req, res) => {
  const { name, email, subject, message } = req.body || {};
  const values = {
    name: String(name || '').trim(),
    email: String(email || '').trim(),
    subject: String(subject || '').trim(),
    message: String(message || '').trim(),
  };

  const settings = await loadSettings();
  const page = await siteRepo.getPage('contact');

  const fail = (error) =>
    res.status(400).type('html').send(
      renderer.renderContact(page, settings, { error, values })
    );

  if (values.message.length < 10) {
    return fail('اكتب رسالة لا تقل عن عشرة أحرف.');
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(values.email)) {
    return fail('أدخل بريداً إلكترونياً صحيحاً كي نتمكن من الرد عليك.');
  }

  try {
    await siteRepo.createMessage({
      ...values,
      ip: req.ip,
    });
  } catch (err) {
    logger.error('[pages] contact save failed:', err.message);
    return res
      .status(503)
      .type('html')
      .send(renderer.renderContact(page, settings, {
        error: 'تعذّر إرسال رسالتك الآن. جرّب بعد قليل أو راسلنا بالبريد مباشرة.',
        values,
      }));
  }

  res.redirect(303, '/contact?sent=1');
});

// ─────────────────────── المباريات ───────────────────────
//
// كل البيانات من قاعدتنا لا من المزوّد: المزامن يملؤها دورياً،
// فزائر الموقع مهما كثر لا يكلّف طلباً خارجياً واحداً. هذا شرط لا
// تحسين — صفحة عامة تنادي مزوّداً محدود الحصة تسقط عند أول انتشار.
// /matches كان العنوان قبل أن تصير الرئيسية هي المباريات.
// تحويل دائم لا حذف: الروابط المنشورة والمحفوظة يجب ألا تكسر.
router.get('/matches', (req, res) => {
  const qs = new URLSearchParams(req.query).toString();
  res.redirect(301, qs ? `/?${qs}` : '/');
});

// ─────────────────────── الترتيب ───────────────────────
//
// الترتيب لا يُخزَّن عندنا (بيانات مشتقة — انظر standingsMapper)،
// فهو النداء الوحيد في الموقع الذي قد يمس المزوّد. كاش الخدمة
// يمتصه: زوار الدوري الواحد في نفس الساعة يقرؤون نسخة واحدة.
router.get('/standings', async (req, res) => {
  const leagues = await leagueRepo.findEnabled();
  const asked = String(req.query.league || '');
  const league = /^\d+$/.test(asked) && leagues.some((l) => String(l.id) === asked)
    ? Number(asked)
    : leagues[0]?.id;

  const settings = await loadSettings();
  const current = leagues.find((l) => l.id === league);

  let rows = [];
  let error = null;
  try {
    rows = await standingsService.getStandings({
      leagueId: league, season: current?.season,
    });
  } catch (err) {
    // نفاد الحصة أو عطل عند المزوّد: الصفحة تبقى وتقول السبب،
    // ولا تتحول إلى خطأ 500 يخفي أن البقية تعمل.
    logger.error('[pages] standings failed:', err.message);
    error = 'تعذّر جلب الترتيب الآن. حاول بعد قليل.';
  }

  res.type('html').send(
    renderer.renderStandings(settings, { leagues, league, rows, error })
  );
});
// ─────────────────── استعادة كلمة المرور ───────────────────
//
// نفس منطق /api/auth/forgot-password تماماً، بواجهة HTML بدل JSON.
// المنطق كله في authService: الصفحة هنا نموذج ورسائل، ولا تعرف
// شيئاً عن الرموز ولا Redis ولا التجزئة.

router.get('/forgot', async (req, res) => {
  res.type('html').send(renderer.renderForgot(await loadSettings()));
});

router.post('/forgot', async (req, res) => {
  const email = String(req.body?.email || '').trim();
  const settings = await loadSettings();

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return res.status(400).type('html').send(
      renderer.renderForgot(settings, {
        error: 'أدخل بريداً إلكترونياً صحيحاً.',
        values: { email },
      })
    );
  }

  try {
    await authService.forgotPassword(email);
  } catch (err) {
    // فشل المزوّد (حد يومي، انقطاع). authService يمسح الرمز حين
    // يفشل الإرسال، فلا يبقى المستخدم ينتظر بريداً لن يصل.
    logger.error('[pages] forgot-password failed:', err.message);
    return res.status(503).type('html').send(
      renderer.renderForgot(settings, {
        error: 'تعذّر إرسال الرمز الآن. جرّب بعد قليل.',
        values: { email },
      })
    );
  }

  // تحويل 303 (POST/Redirect/GET): تحديث الصفحة بعده لا يعيد
  // إرسال رمز جديد. ونمرر البريد في الرابط لملء الحقل التالي —
  // بريد صاحب الطلب نفسه ولا سر فيه بالنسبة له، والرمز وحده هو
  // السر ولا يمر هنا أبداً.
  res.redirect(303, `/reset?sent=1&email=${encodeURIComponent(email)}`);
});

router.get('/reset', async (req, res) => {
  res.type('html').send(
    renderer.renderReset(await loadSettings(), {
      sent: req.query.sent === '1',
      values: { email: String(req.query.email || '') },
    })
  );
});

router.post('/reset', async (req, res) => {
  const email = String(req.body?.email || '').trim();
  const code = String(req.body?.code || '').trim();
  const password = String(req.body?.password || '');
  const settings = await loadSettings();

  const fail = (error, status = 400) =>
    res.status(status).type('html').send(
      renderer.renderReset(settings, { error, values: { email } })
    );

  if (!email || !/^[0-9]{6}$/.test(code)) {
    return fail('تحقق من البريد ومن الرمز — الرمز ستة أرقام.');
  }
  if (password.length < 8) {
    return fail('كلمة المرور يجب ألا تقل عن ثمانية أحرف.');
  }

  // الخدمة ترمي AuthError برسالة موحّدة عمداً ("الرمز غير صحيح أو
  // منتهي الصلاحية") ولا تفرّق بين رمز خاطئ ورمز منتهٍ وبريد غير
  // مسجّل — لأن التفريق يحوّل هذه الصفحة إلى أداة تكشف أي البريدات
  // لها حساب. نعرض رسالتها كما هي ولا نضيف تفصيلاً من عندنا.
  //
  // ولا نستعمل التوكنات التي ترجعها (تسجّل الدخول تلقائياً): لا
  // جلسة على الموقع، والوجهة هي التطبيق. إصدارها هنا بلا ضرر —
  // تنتهي صلاحيتها بلا استعمال.
  try {
    await authService.resetPassword({ email, code, newPassword: password });
  } catch (err) {
    if (err.status && err.expose) return fail(err.message, err.status);
    logger.error('[pages] reset-password failed:', err.message);
    return fail('تعذّر تغيير كلمة المرور الآن. جرّب بعد قليل.', 503);
  }

  res.type('html').send(renderer.renderResetDone(settings));
});

// ──────────────── الحساب على الويب ────────────────
//
// نطاق مقصود وضيق: الموقع يجيب عن "ماذا في حسابي وكيف أتحكم به".
// التوقّع والمنافسة تجربة التطبيق، ونسخة ويب منها تعني واجهتين
// تتباعدان مع كل تعديل.

// الكوكي يحمل علم Secure في الإنتاج فقط، وإلا لم تعمل الجلسة على
// http://localhost أثناء التطوير. req.secure يقرأ X-Forwarded-Proto
// وهو صحيح هنا لأن TRUST_PROXY مضبوط ونginx يمرره.
const isSecure = (req) => req.secure || req.protocol === 'https';

/** يمنع تنفيذ فعل يبدأه موقع آخر نيابة عن المستخدم. */
function checkCsrf(session, req) {
  const sent = String(req.body?._csrf || '');
  // مقارنة بزمن ثابت: المقارنة العادية تتوقف عند أول حرف مختلف،
  // وفارق التوقيت يسرّب الرمز حرفاً حرفاً لمن يقيسه بدقة.
  const a = Buffer.from(sent);
  const b = Buffer.from(String(session?.csrf || ''));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

/** يجلب الجلسة أو يحوّل لصفحة الدخول. */
async function requireSession(req, res) {
  const session = await webSession.read(req);
  if (!session) {
    res.redirect(303, '/login');
    return null;
  }
  return session;
}

router.get('/login', async (req, res) => {
  // من هو مسجّل أصلاً لا يرى نموذج دخول.
  if (await webSession.read(req)) return res.redirect(303, '/account');
  res.type('html').send(renderer.renderLogin(await loadSettings()));
});

router.post('/login', async (req, res) => {
  const email = String(req.body?.email || '').trim();
  const password = String(req.body?.password || '');
  const settings = await loadSettings();

  try {
    // نستدعي نفس authService.login الذي يستدعيه التطبيق: هو الذي
    // يعرف فحص الحساب الموقوف ورسالته، وتكرار المنطق هنا يخلق
    // بابين بقواعد مختلفة.
    const { user } = await authService.login({ email, password });
    await webSession.create(res, user.id, { secure: isSecure(req) });
    return res.redirect(303, '/account');
  } catch (err) {
    if (err.status && err.expose) {
      return res.status(err.status).type('html').send(
        renderer.renderLogin(settings, { error: err.message, values: { email } })
      );
    }
    logger.error('[pages] web login failed:', err.message);
    return res.status(503).type('html').send(
      renderer.renderLogin(settings, {
        error: 'تعذّر تسجيل الدخول الآن. جرّب بعد قليل.',
        values: { email },
      })
    );
  }
});

router.get('/register', async (req, res) => {
  if (await webSession.read(req)) return res.redirect(303, '/account');
  res.type('html').send(renderer.renderRegister(await loadSettings()));
});

router.post('/register', async (req, res) => {
  const name = String(req.body?.name || '').trim();
  const email = String(req.body?.email || '').trim();
  const password = String(req.body?.password || '');
  const settings = await loadSettings();
  const values = { name, email };

  try {
    const { user } = await authService.register({
      email, password, displayName: name,
    });
    await webSession.create(res, user.id, { secure: isSecure(req) });
    return res.redirect(303, '/account');
  } catch (err) {
    if (err.status && err.expose) {
      return res.status(err.status).type('html').send(
        renderer.renderRegister(settings, { error: err.message, values })
      );
    }
    logger.error('[pages] web register failed:', err.message);
    return res.status(503).type('html').send(
      renderer.renderRegister(settings, {
        error: 'تعذّر إنشاء الحساب الآن. جرّب بعد قليل.', values,
      })
    );
  }
});

/** يبني صفحة الحساب — يستعملها العرض وكل فعل ينتهي إليها. */
async function showAccount(req, res, session, extra = {}) {
  const [settings, user, stats] = await Promise.all([
    loadSettings(),
    userRepo.findById(session.userId),
    predictionRepo.profileStats(session.userId).catch(() => null),
  ]);

  // الحساب حُذف بينما الجلسة حية (من التطبيق مثلاً).
  if (!user) {
    await webSession.destroy(req, res);
    return res.redirect(303, '/login');
  }

  res.type('html').send(
    renderer.renderAccount(settings, { user, stats, csrf: session.csrf, ...extra })
  );
}

router.get('/account', async (req, res) => {
  const session = await requireSession(req, res);
  if (!session) return;
  await showAccount(req, res, session);
});

router.post('/account/password', async (req, res) => {
  const session = await requireSession(req, res);
  if (!session) return;
  if (!checkCsrf(session, req)) return res.status(403).send('طلب غير صالح');

  try {
    await authService.changePassword(session.userId, {
      currentPassword: String(req.body?.current || ''),
      newPassword: String(req.body?.next || ''),
    });
  } catch (err) {
    const error = err.status && err.expose ? err.message : 'تعذّر تغيير كلمة المرور.';
    return await showAccount(req, res, session, { error });
  }

  // كلمة السر تغيّرت: كل جلسة أخرى (جهاز آخر، أو من سرقها) يجب أن
  // تسقط. ثم ننشئ جلسة جديدة لصاحب الطلب كي لا يُخرج نفسه.
  await webSession.destroyAllForUser(session.userId);
  const csrf = await webSession.create(res, session.userId, { secure: isSecure(req) });
  await showAccount(req, res, { userId: session.userId, csrf },
    { notice: 'تغيّرت كلمة المرور. أُنهيت الجلسات الأخرى.' });
});

router.post('/account/delete', async (req, res) => {
  const session = await requireSession(req, res);
  if (!session) return;
  if (!checkCsrf(session, req)) return res.status(403).send('طلب غير صالح');

  try {
    await authService.deleteAccount(session.userId, {
      password: String(req.body?.password || ''),
    });
  } catch (err) {
    const error = err.status && err.expose ? err.message : 'تعذّر حذف الحساب.';
    return await showAccount(req, res, session, { error });
  }

  await webSession.destroyAllForUser(session.userId);
  await webSession.destroy(req, res);
  res.redirect(303, '/');
});

router.post('/logout', async (req, res) => {
  const session = await webSession.read(req);
  // فحص CSRF على الخروج أيضاً: إخراج المستخدم من موقع آخر مضايقة
  // لا سرقة، لكنها ما زالت فعلاً لم يطلبه.
  if (session && !checkCsrf(session, req)) return res.status(403).send('طلب غير صالح');
  await webSession.destroy(req, res);
  res.redirect(303, '/');
});

// ─────────────────── صفحة المباراة ───────────────────
//
// ثلاثة نداءات للمزوّد لكل مباراة تُفتح (أحداث، إحصاءات، تشكيلات)،
// وهي النداءات الوحيدة في الموقع مع الترتيب. الكاش هو ما يجعلها
// آمنة: مباراة يفتحها مئة زائر في دقيقة تُجلب مرة.
router.get('/match/:id', async (req, res, next) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id) || id <= 0) return next();

  const fixture = await siteFixtureRepo.findById(id);
  if (!fixture) return next(); // 404 بهوية الموقع

  const [settings, detail] = await Promise.all([
    loadSettings(),
    matchDetailService.get(fixture),
  ]);

  res.type('html').send(renderer.renderMatch(settings, { fixture, detail }));
});

// ─────────────────── الهدافون ───────────────────
router.get('/scorers', async (req, res) => {
  const leagues = await leagueRepo.findEnabled();
  const asked = String(req.query.league || '');
  const league = /^\d+$/.test(asked) && leagues.some((l) => String(l.id) === asked)
    ? Number(asked)
    : leagues[0]?.id;

  const settings = await loadSettings();
  const current = leagues.find((l) => l.id === league);

  let scorers = [];
  let error = null;
  try {
    scorers = await matchDetailService.topScorers({
      leagueId: league, season: current?.season,
    });
  } catch (err) {
    logger.error('[pages] scorers failed:', err.message);
    error = 'تعذّر جلب قائمة الهدافين الآن. حاول بعد قليل.';
  }

  res.type('html').send(renderer.renderScorers(settings, { leagues, league, scorers, error }));
});

// بقية الصفحات المنشورة
router.get('/:slug', async (req, res, next) => {
  const { slug } = req.params;
  if (!PUBLIC_SLUGS.has(slug)) return next();

  const [settings, page] = await Promise.all([loadSettings(), siteRepo.getPage(slug)]);
  if (!page) return next();

  res.type('html').send(renderer.renderPage(page, settings));
});

module.exports = router;
