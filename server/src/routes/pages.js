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
const predictionService = require('../services/predictionService');
const googleAuth = require('../services/googleAuth');
const appleWebAuth = require('../services/appleWebAuth');
const siteSettings = require('../services/siteSettings');
const renderer = require('../services/siteRenderer');
const authService = require('../services/authService');
const webSession = require('../services/webSession');
const userRepo = require('../repositories/userRepo');
const teamRepo = require('../repositories/teamRepo');
const championService = require('../services/championService');
const championRepo = require('../repositories/championRepo');
const fixtureRepo = require('../repositories/fixtureRepo');
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

/**
 * سياق أي صفحة: إعدادات الموقع + هل الزائر مسجّل.
 *
 * الترويسة تعرض "حسابي" أو "دخول/حساب جديد"، وهذا يحتاج معرفة
 * الجلسة في كل صفحة لا في صفحات الحساب وحدها. تمريرها داخل نفس
 * كائن الإعدادات بدل وسيط ثانٍ لكل دالة عرض: الكائن أصلاً هو
 * "سياق الصفحة" المشترك، وإضافة وسيط ثالث لتسع دوالّ عرض تعني
 * تعديل تسعة توقيعات لأجل حقل واحد.
 *
 * وفشل قراءة الجلسة لا يُسقط الصفحة: تُعرض كزائر غير مسجّل.
 */
/** يقرأ كوكي الثيم من الترويسة الخام. */
function readTheme(req) {
  const header = req.headers.cookie || '';
  const m = /(?:^|;\s*)sah_theme=([^;]+)/.exec(header);
  return m && decodeURIComponent(m[1]) === 'light' ? 'light' : 'dark';
}

async function pageContext(req) {
  const [settings, session] = await Promise.all([
    loadSettings(),
    webSession.read(req).catch(() => null),
  ]);
  return {
    ...settings,
    viewer: session ? { id: session.userId } : null,
    // الثيم من كوكي: يُقرأ قبل بناء HTML فتصل الصفحة بلونها الصحيح
    // من أول بايت. القيمة الوحيدة المقبولة 'light'؛ ما عداها داكن
    // (الافتراضي، وهوية العلامة).
    theme: readTheme(req),
    // الزر يظهر فقط حين يكتمل الإعداد: زر يقود إلى خطأ أسوأ من
    // غيابه.
    google: googleAuth.isConfigured(),
    apple: appleWebAuth.isConfigured(),
    // المسار الحالي — يعود إليه زر التبديل.
    canonicalPath: req.originalUrl || '/',
  };
}

// الصفحة الرئيسية
/**
 * بيانات اللوحة الجانبية. لا ترمي أبداً: عطل عند المزوّد يخفي
 * اللوحة ولا يمنع عرض المباريات — وهي المحتوى الأساسي.
 *
 * النداءان مخزّنان مؤقتاً (ساعة للترتيب وست ساعات للهدافين)، فزوار
 * الساعة الواحدة يقرؤون نسخة واحدة مهما كثروا.
 */
async function buildSide(league) {
  if (!league) return null;

  // الترتيب وحده: الهدافون خرجوا من اللوحة (لهم صفحتهم في /scorers)،
  // فصار نداء واحد لكل دوري بدل اثنين — نصف التكلفة على الحصة.
  const standings = await standingsService
    .getStandings({ leagueId: league.id, season: league.season })
    .catch(() => []);

  return { league: league.id, standings };
}

/**
 * لوحة لكل دوري ظاهر في الصفحة، لا لوحة واحدة.
 *
 * القارئ الذي ينزل إلى الدوري الإيطالي يريد ترتيب الإيطالي بجانبه،
 * لا ترتيب دوري روشن الذي بقي ملتصقاً بأعلى الصفحة.
 *
 * التكلفة نداء واحد لكل دوري، مخزّن ساعة. ستة دوريات في يوم مزدحم
 * = ستة نداءات في الساعة على الأكثر، أي ~144 يومياً من حصة 7500.
 * وكلها على التوازي فزمنها زمن أبطأها.
 *
 * ويقتصر على الدوريات التي لها مباريات اليوم: بناء لوحة لدوري لا
 * يظهر أصلاً إنفاق حصة على ما لا يُرى.
 */
async function buildSides(leagues, fixtures) {
  const shown = new Set(fixtures.map((f) => f.league_id));
  const wanted = leagues.filter((l) => shown.has(l.id));

  const panels = await Promise.all(wanted.map((l) => buildSide(l)));

  return Object.fromEntries(
    panels.filter(Boolean).map((p) => [p.league, p])
  );
}

// تبديل الثيم: يضبط الكوكي ويعود من حيث جاء.
//
// GET لا POST: هو تفضيل عرض لا فعل يغيّر بيانات، ورابط بسيط يعمل
// بلا JS وبلا رمز CSRF. وأسوأ ما يفعله من ينتحله أن يبدّل لون
// صفحة الزائر.
router.get('/theme', (req, res) => {
  const to = req.query.to === 'light' ? 'light' : 'dark';

  // سنة كاملة: التفضيل لا ينتهي. وSameSite=Lax يكفي — لا شيء
  // حسّاس هنا. وبلا HttpOnly عمداً: لا ضرر، وقد نحتاج قراءته من
  // سكربت لاحقاً.
  res.setHeader('Set-Cookie',
    `sah_theme=${to}; Path=/; Max-Age=${365 * 24 * 3600}; SameSite=Lax` +
    (req.secure ? '; Secure' : ''));

  // الوجهة من داخل موقعنا فقط: قيمة تبدأ بـ // أو http تعني تحويلاً
  // مفتوحاً يستعمله المخادع ليجعل رابطنا يقود لموقعه.
  const next = String(req.query.next || '/');
  const safe = /^\/(?!\/)/.test(next) ? next : '/';
  res.redirect(303, safe);
});

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
    pageContext(req),
    siteFixtureRepo.byDate(day),
    siteFixtureRepo.daysAround(renderer.riyadhToday()),
    leagueRepo.findEnabled(),
  ]);

  // الترشيح في الذاكرة لا في SQL: الصفوف عشرات لا آلاف، والاستعلام
  // نفسه يخدم "الكل" و"دوري واحد" فلا يتفرّع.
  const fixtures = league ? all.filter((f) => f.league_id === league) : all;

  const [sides, mine] = await Promise.all([
    buildSides(leagues, fixtures),
    // توقعات هذا الزائر لمباريات اليوم، في استعلام واحد. زائر غير
    // مسجّل لا يكلّف شيئاً.
    settings.viewer
      ? predictionRepo
          .findByUserAndFixtures(settings.viewer.id, fixtures.map((f) => f.id))
          .then((rows) => Object.fromEntries(rows.map((r) => [r.fixture_id, r])))
          .catch(() => ({}))
      : Promise.resolve({}),
  ]);

  res.type('html').send(
    renderer.renderMatches(settings, { day, fixtures, days, leagues, league, sides, mine })
  );
});
// صفحة اتصل بنا — قبل /:slug لأن لها معالجاً خاصاً (نموذج + POST)
router.get('/contact', async (req, res) => {
  const [settings, page] = await Promise.all([
    pageContext(req),
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

  const settings = await pageContext(req);
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

// ─────────────────── العرش ───────────────────
router.get('/throne', async (req, res) => {
  const all = await leagueRepo.findEnabled();
  // الشرائح دوريات اللعبة وحدها: دوريٌّ لا يُتوقَّع فيه لا نقاط
  // له، فشريحته تعد بقائمة فارغة دائماً.
  const leagues = all.filter((l) => l.in_app);

  const asked = String(req.query.league || '');
  const league = /^\d+$/.test(asked) && leagues.some((l) => String(l.id) === asked)
    ? Number(asked)
    : null; // بلا دوري = العرش العام

  const settings = await pageContext(req);
  const [rows, me] = await Promise.all([
    predictionRepo.leaderboard(20, league).catch(() => []),
    settings.viewer
      ? predictionRepo.rankOf(settings.viewer.id, league).catch(() => null)
      : null,
  ]);

  // لا نكرّره تحت القائمة إن كان فيها: صفّان لشخص واحد في شاشة
  // واحدة يُقرآن لاعبَين.
  const inList = me && rows.some((r) => r.user_id === settings.viewer?.id);

  res.type('html').send(
    renderer.renderThrone(settings, {
      leagues, league, rows,
      me: inList ? null : (me ? { ...me, user_id: settings.viewer.id } : null),
    })
  );
});

router.get('/standings', async (req, res) => {
  const leagues = await leagueRepo.findEnabled();
  const asked = String(req.query.league || '');
  const league = /^\d+$/.test(asked) && leagues.some((l) => String(l.id) === asked)
    ? Number(asked)
    : leagues[0]?.id;

  const settings = await pageContext(req);
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

  // البطاقة واللوحة إضافتان على صفحة قائمة: فشل أيٍّ منهما يُخفيها
  // ولا يمنع الجدول — وهو ما جاء الزائر لأجله.
  const session = settings.viewer ? await webSession.read(req).catch(() => null) : null;
  const [champion, kings] = await Promise.all([
    current?.in_app && session
      ? championCard(session.userId, current).catch(() => null)
      : null,
    current?.in_app
      ? predictionRepo.leaderboard(10, current.id).catch(() => [])
      : [],
  ]);

  res.type('html').send(
    renderer.renderStandings(settings, {
      leagues, league, rows, error,
      champion, kings, csrf: session?.csrf || '',
      canBet: Boolean(current?.in_app),
    })
  );
});
// ─────────────────── استعادة كلمة المرور ───────────────────
//
// نفس منطق /api/auth/forgot-password تماماً، بواجهة HTML بدل JSON.
// المنطق كله في authService: الصفحة هنا نموذج ورسائل، ولا تعرف
// شيئاً عن الرموز ولا Redis ولا التجزئة.

router.get('/forgot', async (req, res) => {
  res.type('html').send(renderer.renderForgot(await pageContext(req)));
});

router.post('/forgot', async (req, res) => {
  const email = String(req.body?.email || '').trim();
  const settings = await pageContext(req);

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
    renderer.renderReset(await pageContext(req), {
      sent: req.query.sent === '1',
      values: { email: String(req.query.email || '') },
    })
  );
});

router.post('/reset', async (req, res) => {
  const email = String(req.body?.email || '').trim();
  const code = String(req.body?.code || '').trim();
  const password = String(req.body?.password || '');
  const settings = await pageContext(req);

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

// ─────────────────── الدخول بجوجل ───────────────────
//
// تدفّق OAuth بالتحويل لا زر JavaScript: سياسة المحتوى عندنا تمنع
// السكربت الخارجي، والتحويل يعمل بلا JS أصلاً. التفاصيل في
// services/googleAuth.

const OAUTH_STATE_COOKIE = 'sah_oauth';
// كوكي منفصل لآبل: من فتح رحلتي دخول في لسانين لا تمحو إحداهما
// حالة الأخرى، والخصائص مختلفة أصلاً (SameSite).
const APPLE_STATE_COOKIE = 'sah_oauth_apple';

router.get('/auth/google', (req, res) => {
  if (!googleAuth.isConfigured()) return res.redirect(303, '/login');

  // state عشوائي في كوكي قصير العمر، يُقارن عند العودة.
  //
  // بدونه يستطيع مهاجم أن يبدأ التدفّق بحسابه هو ثم يدفع الضحية
  // إلى رابط العودة، فتجد نفسها داخلة بحساب المهاجم وتكتب فيه
  // بياناتها. الهجمة معروفة (CSRF على تسجيل الدخول) وحمايتها
  // هذا السطر.
  const state = googleAuth.newState();
  res.setHeader('Set-Cookie',
    `${OAUTH_STATE_COOKIE}=${state}; Path=/auth/google; HttpOnly; SameSite=Lax; Max-Age=600` +
    (isSecure(req) ? '; Secure' : ''));

  res.redirect(302, googleAuth.authUrl(state));
});

router.get('/auth/google/callback', async (req, res) => {
  const settings = await pageContext(req);
  const fail = (error) => res.status(401).type('html').send(
    renderer.renderLogin(settings, { error })
  );

  // كوكي الـ state يُستعمل مرة واحدة.
  const clearState = () => res.setHeader('Set-Cookie',
    `${OAUTH_STATE_COOKIE}=; Path=/auth/google; HttpOnly; SameSite=Lax; Max-Age=0`);

  // المستخدم ضغط "إلغاء" في شاشة جوجل: ليس خطأً، نعيده بهدوء.
  if (req.query.error) {
    clearState();
    return res.redirect(303, '/login');
  }

  const expected = /(?:^|;\s*)sah_oauth=([^;]+)/.exec(req.headers.cookie || '')?.[1];
  const got = String(req.query.state || '');
  const code = String(req.query.code || '');

  if (!code || !expected || got !== expected) {
    clearState();
    return fail('انتهت جلسة الدخول بجوجل. حاول مرة أخرى.');
  }

  let profile;
  try {
    profile = await googleAuth.exchangeCode(code);
  } catch (err) {
    // detail يحمل رد جوجل الحقيقي (redirect_uri_mismatch مثلاً)
    // ويذهب للوق لا للمستخدم.
    logger.error('[pages] google exchange failed:', err.message, err.detail || '');
    clearState();
    return fail(err.expose ? err.message : 'تعذّر الدخول بجوجل الآن.');
  }

  try {
    const { user } = await authService.loginWithGoogle(profile);
    // create يكتب Set-Cookie للجلسة. كوكي الـ state مقيّد بمسار
    // /auth/google وينتهي بعد عشر دقائق، فتركه مقبول.
    await webSession.create(res, user.id, { secure: isSecure(req) });
    return res.redirect(303, afterAuth(user));
  } catch (err) {
    clearState();
    if (err.status && err.expose) return fail(err.message);
    logger.error('[pages] google login failed:', err.message);
    return fail('تعذّر الدخول بجوجل الآن.');
  }
});

// ─────────────────── الدخول بحساب آبل ───────────────────
//
// المسار الأول تحويل، والثاني يستقبل POST من آبل. راجع
// services/appleWebAuth للفروق الثلاثة عن جوجل.
router.get('/auth/apple', (req, res) => {
  if (!appleWebAuth.isConfigured()) return res.redirect(303, '/login');

  const state = appleWebAuth.newState();
  // SameSite=None إلزامية هنا: ردّ آبل POST من نطاق آخر، والمتصفح
  // لا يرسل كوكي Lax معه. وNone توجب Secure، فنُبقي Lax محلياً على
  // http كي تبقى التنمية ممكنة — والإنتاج https دائماً.
  const cross = isSecure(req) ? 'SameSite=None; Secure' : 'SameSite=Lax';
  res.setHeader('Set-Cookie',
    `${APPLE_STATE_COOKIE}=${state}; Path=/auth/apple; HttpOnly; ${cross}; Max-Age=600`);

  res.redirect(302, appleWebAuth.authUrl(state));
});

router.post('/auth/apple/callback', async (req, res) => {
  const settings = await pageContext(req);
  const fail = (error) => res.status(401).type('html').send(
    renderer.renderLogin(settings, { error })
  );

  const cross = isSecure(req) ? 'SameSite=None; Secure' : 'SameSite=Lax';
  const clearState = () => res.setHeader('Set-Cookie',
    `${APPLE_STATE_COOKIE}=; Path=/auth/apple; HttpOnly; ${cross}; Max-Age=0`);

  // ضغط "إلغاء" في شاشة آبل: ليس خطأً، نعيده بهدوء.
  if (req.body?.error) {
    clearState();
    return res.redirect(303, '/login');
  }

  const expected = new RegExp(`(?:^|;\\s*)${APPLE_STATE_COOKIE}=([^;]+)`)
    .exec(req.headers.cookie || '')?.[1];
  const got = String(req.body?.state || '');
  const code = String(req.body?.code || '');

  if (!code || !expected || got !== expected) {
    clearState();
    return fail('انتهت جلسة الدخول بآبل. حاول مرة أخرى.');
  }

  let profile;
  try {
    profile = await appleWebAuth.exchangeCode(code);
  } catch (err) {
    logger.error('[pages] apple exchange failed:', err.message, err.detail || '');
    clearState();
    return fail(err.expose ? err.message : 'تعذّر الدخول بآبل الآن.');
  }

  try {
    const { user } = await authService.loginWithAppleProfile({
      ...profile,
      // الاسم يصل مرة واحدة في العمر — عند أول تفويض فقط. إن جاء
      // الآن فهذه فرصتنا الوحيدة، وإلا بقي الحساب بلا اسم للأبد.
      displayName: appleWebAuth.nameFrom(req.body?.user),
    });
    await webSession.create(res, user.id, { secure: isSecure(req) });
    return res.redirect(303, afterAuth(user));
  } catch (err) {
    clearState();
    if (err.status && err.expose) return fail(err.message);
    logger.error('[pages] apple login failed:', err.message);
    return fail('تعذّر الدخول بآبل الآن.');
  }
});


// ──────────────── الحساب على الويب ────────────────
//
// نطاق مقصود وضيق: الموقع يجيب عن "ماذا في حسابي وكيف أتحكم به".
// التوقّع والمنافسة تجربة التطبيق، ونسخة ويب منها تعني واجهتين
// تتباعدان مع كل تعديل.

// الكوكي يحمل علم Secure في الإنتاج فقط، وإلا لم تعمل الجلسة على
// http://localhost أثناء التطوير. req.secure يقرأ X-Forwarded-Proto
// وهو صحيح هنا لأن TRUST_PROXY مضبوط ونginx يمرره.

/**
 * إلى أين بعد إثبات الهوية؟
 *
 * من لم يُهيَّأ بعد يذهب إلى /welcome لا /account: لحظة ما بعد
 * التسجيل هي أعلى استعداد يمرّ به المستخدم — جاء لتوّه ولديه نية.
 * وصفحةُ حسابٍ فارغة في تلك اللحظة تطفئ النية بلا مقابل.
 *
 * والفحص هنا لا في كل باب على حدة: الأبواب أربعة (تسجيل، دخول،
 * جوجل، آبل)، ووضع الشرط في كلٍّ منها يعني أن أول باب جديد يُنسى.
 */
function afterAuth(user) {
  return user?.onboarded_at ? '/account' : '/welcome';
}

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
  res.type('html').send(renderer.renderLogin(await pageContext(req)));
});

router.post('/login', async (req, res) => {
  const email = String(req.body?.email || '').trim();
  const password = String(req.body?.password || '');
  const settings = await pageContext(req);

  try {
    // نستدعي نفس authService.login الذي يستدعيه التطبيق: هو الذي
    // يعرف فحص الحساب الموقوف ورسالته، وتكرار المنطق هنا يخلق
    // بابين بقواعد مختلفة.
    const { user } = await authService.login({ email, password });
    await webSession.create(res, user.id, { secure: isSecure(req) });
    return res.redirect(303, afterAuth(user));
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
  res.type('html').send(renderer.renderRegister(await pageContext(req)));
});

router.post('/register', async (req, res) => {
  const name = String(req.body?.name || '').trim();
  const email = String(req.body?.email || '').trim();
  const password = String(req.body?.password || '');
  const settings = await pageContext(req);
  const values = { name, email };

  try {
    const { user } = await authService.register({
      email, password, displayName: name,
    });
    await webSession.create(res, user.id, { secure: isSecure(req) });
    return res.redirect(303, afterAuth(user));
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


// ─────────────────── التهيئة: ثلاث خطوات ───────────────────
//
// دورياتك ← فريقك ← البطل. وكلٌّ ضغطة واحدة، والتخطّي مفتوح في
// كلٍّ منها. راجع renderWelcome لسبب هذا الترتيب.

/**
 * بطاقة رهانٍ واحدة: الدوري، أنديته، سعره اليوم، ورهان صاحبها.
 *
 * الوحدة هنا بطاقة لا قائمة لأن لها موضعين: صفحة الترتيب تعرض
 * بطاقة دوريها وحده، و"حسابي" يعرض بطاقة لكل متابَع. ولو كانت
 * الدالة تُرجع القائمة دائماً لبنت صفحةُ الترتيب ستّ بطاقات
 * لتعرض واحدة.
 */
async function championCard(userId, league) {
  const [teams, mine] = await Promise.all([
    teamRepo.findPlayable(),
    championRepo.findMine(userId),
  ]);
  return {
    league: { id: league.id, name: league.name },
    teams: teams.filter((t) => t.league_id === league.id),
    quote: await championService.quote(league.id, league.season),
    mine: mine.find((m) => m.league_id === league.id && m.season === league.season) || null,
  };
}

/** بطاقات كل ما يتابعه — لصفحة "حسابي" والتهيئة. */
async function championCards(userId) {
  const followed = await championRepo.followedIds(userId);
  if (!followed.length) return [];

  const leagues = await leagueRepo.findEnabled();
  const cards = [];
  for (const id of followed) {
    const league = leagues.find((l) => l.id === id);
    if (!league) continue; // دوري أُخرج من اللعبة بعد متابعته
    cards.push(await championCard(userId, league));
  }
  return cards;
}

router.get('/welcome', async (req, res) => {
  const session = await webSession.read(req);
  if (!session) return res.redirect(303, '/login');

  const [settings, user] = await Promise.all([
    pageContext(req),
    userRepo.findById(session.userId),
  ]);
  // من هُيِّئ لا يُعاد إليها ولو فتح الرابط بنفسه — والحارس هنا
  // لا في afterAuth وحدها: الرابط قابل للحفظ في المفضلة.
  if (!user || user.onboarded_at) return res.redirect(303, '/account');

  // الخطوة مشتقّة من الحالة لا محفوظة في الجلسة: من أغلق المتصفح
  // بين خطوتين يعود إلى حيث وقف، ومن رجع للخلف لا يرى شاشة تدّعي
  // تقدّماً لم يحدث. الحقيقة في القاعدة لا في عدّاد.
  const followed = await championRepo.followedIds(session.userId);
  const step = !followed.length ? 'leagues'
    : !user.favorite_team_id ? 'team'
    : 'champion';

  const view = { step, csrf: session.csrf, name: user.display_name };
  if (step === 'leagues') {
    const leagues = await leagueRepo.findEnabled();
    view.leagues = leagues
      .filter((l) => l.in_app)
      .map((l) => ({ id: l.id, name: l.name, followed: false }));
  } else if (step === 'team') {
    const teams = await teamRepo.findPlayable();
    view.teams = teams.filter((t) => followed.includes(t.league_id));
  } else {
    view.picks = await championCards(session.userId);
  }

  res.type('html').send(renderer.renderWelcome(settings, view));
});

router.post('/welcome/leagues', async (req, res) => {
  const session = await webSession.read(req);
  if (!session) return res.redirect(303, '/login');
  if (!checkCsrf(session, req)) return res.status(403).send('طلب غير صالح');

  // مربّع اختيار واحد يصل نصاً، وعدّة تصل مصفوفة.
  const raw = req.body?.league;
  const asked = (Array.isArray(raw) ? raw : raw ? [raw] : []).map(Number);

  // نصفّيها بقائمة الدوريات الداخلة في اللعبة فعلاً: القيم تأتي
  // من المتصفح، ومن يصنع طلباً بيده يستطيع كتابة أي رقم. والمفتاح
  // الأجنبي يمنع المعرّف الخيالي، ولا يمنع متابعة دوري يُعرض ولا
  // يُلعب — فتظهر له بطاقة بطلٍ لا مباريات تحتها.
  const playable = (await leagueRepo.findEnabled()).filter((l) => l.in_app).map((l) => l.id);
  const ids = [...new Set(asked.filter((id) => playable.includes(id)))];

  // بلا اختيار لا نتقدّم: الخطوتان التاليتان مبنيّتان على هذه،
  // والمرور بلا دوري يعطي شبكة أندية فارغة. ومن لا يريد الاختيار
  // له "تخطَّ".
  if (!ids.length) return res.redirect(303, '/welcome');

  await championRepo.setFollowed(session.userId, ids);
  res.redirect(303, '/welcome');
});

router.post('/welcome/team', async (req, res) => {
  const session = await webSession.read(req);
  if (!session) return res.redirect(303, '/login');
  if (!checkCsrf(session, req)) return res.status(403).send('طلب غير صالح');

  const teamId = Number(req.body?.team);
  if (!Number.isInteger(teamId)) return res.redirect(303, '/welcome');

  await userRepo.updateProfile(session.userId, { favoriteTeamId: teamId });
  res.redirect(303, '/welcome');
});

// التخطّي فعلٌ لا رأي: يُوسم كالإنهاء فلا تعترضه الشاشة ثانية.
// ومن غيّر رأيه يجد كل شيء في "حسابي".
//
// وإلى مباراة فريقه القادمة إن اختاره: التهيئة التي تنتهي بشاشة
// تهنئة تنتهي بلا شيء — المستخدم يعرف اللعبة ولم يلعبها.
router.get('/welcome/skip', async (req, res) => {
  const session = await webSession.read(req);
  if (!session) return res.redirect(303, '/login');

  await userRepo.markOnboarded(session.userId);

  const user = await userRepo.findById(session.userId).catch(() => null);
  if (!user?.favorite_team_id) return res.redirect(303, '/');

  const next = await fixtureRepo.nextForTeam(user.favorite_team_id).catch(() => null);
  res.redirect(303, next ? `/match/${next.id}?first=1` : '/');
});

// ─────────────────── رهان البطل ───────────────────
//
// نفس المسار من التهيئة ومن "حسابي": البطاقة واحدة فالباب واحد.
router.post('/champion', async (req, res) => {
  const session = await webSession.read(req);
  if (!session) return res.redirect(303, '/login');
  if (!checkCsrf(session, req)) return res.status(403).send('طلب غير صالح');

  // العودة إلى حيث جاء: البطاقة في ثلاثة مواضع الآن (التهيئة،
  // حسابي، ترتيب الدوري)، وإرجاعُ الجميع إلى "حسابي" يقتلع من
  // كان يقرأ جدول الدوري من صفحته.
  //
  // ونقرأ المسار من referer لا نثق به وجهةً: نطابقه بقائمة
  // مغلقة عندنا، فترويسة مزوّرة لا تحوّل أحداً إلى موقع آخر.
  const from = String(req.get('referer') || '');
  const back = from.includes('/welcome') ? '/welcome'
    : from.includes('/standings') ? `/standings?league=${Number(req.body?.league) || ''}#champion`
    : '/account#champion';
  const leagueId = Number(req.body?.league);
  const teamId = Number(req.body?.team);
  if (!Number.isInteger(leagueId) || !Number.isInteger(teamId)) {
    return res.redirect(303, back);
  }

  const league = (await leagueRepo.findEnabled()).find((l) => l.id === leagueId && l.in_app);
  if (!league) return res.redirect(303, back);

  try {
    await championService.pick({
      userId: session.userId, leagueId, season: league.season, teamId,
    });
  } catch (err) {
    logger.error('[pages] champion pick failed:', err.message);
  }
  res.redirect(303, back);
});


// تعديل الدوريات من "حسابي" — نفس مستودع التهيئة، فالقائمة واحدة.
router.post('/account/leagues', async (req, res) => {
  const session = await webSession.read(req);
  if (!session) return res.redirect(303, '/login');
  if (!checkCsrf(session, req)) return res.status(403).send('طلب غير صالح');

  const raw = req.body?.league;
  const asked = (Array.isArray(raw) ? raw : raw ? [raw] : []).map(Number);
  const playable = (await leagueRepo.findEnabled()).filter((l) => l.in_app).map((l) => l.id);
  const ids = [...new Set(asked.filter((id) => playable.includes(id)))];

  // إلغاء المتابعة كلها مسموح هنا بخلاف التهيئة: هناك كانت
  // الخطوتان التاليتان مبنيّتين عليها، وهنا قرارٌ كاملٌ لصاحبه —
  // من لا يريد تذكيراً من أي دوري له أن يقول ذلك.
  await championRepo.setFollowed(session.userId, ids);

  // ورهانات الأبطال لا تُمسّ: من ألغى متابعة دوري راهن فيه لم
  // يسحب رهانه، وحذفه عقوبةٌ لم يطلبها. تختفي بطاقته من الصفحة
  // ويبقى الرهان قائماً إن عاد.
  res.redirect(303, '/account#champion');
});

/** الدوريات القابلة للمتابعة، ومعها ما يتابعه فعلاً. */
async function followableLeagues(userId) {
  const [leagues, followed] = await Promise.all([
    leagueRepo.findEnabled(),
    championRepo.followedIds(userId),
  ]);
  return leagues
    .filter((l) => l.in_app)
    .map((l) => ({ id: l.id, name: l.name, followed: followed.includes(l.id) }));
}

/** يبني صفحة الحساب — يستعملها العرض وكل فعل ينتهي إليها. */
async function showAccount(req, res, session, extra = {}) {
  const [settings, user, stats, creds, points, history, champions, leagues] = await Promise.all([
    pageContext(req),
    userRepo.findById(session.userId),
    predictionRepo.profileStats(session.userId).catch(() => null),
    authService.credentials(session.userId).catch(() => null),
    predictionService.points().catch(() => null),
    // آخر عشرين: السجل الكامل قد يبلغ مئات الصفوف في نهاية الموسم،
    // ومن يريد أقدم منها يريد تصفّحاً لا صفحة أطول.
    predictionRepo.findMine(session.userId).then((r) => r.slice(0, 20)).catch(() => []),
    // بطاقات البطل تحتاج سعراً حيّاً لكل دوري، وفشلها لا يُسقط
    // الصفحة: من فتح حسابه ليغيّر كلمة سره لا يُحرم منها لأن
    // استعلام رهانٍ تعثّر.
    championCards(session.userId).catch(() => []),
    followableLeagues(session.userId).catch(() => []),
  ]);

  // الحساب حُذف بينما الجلسة حية (من التطبيق مثلاً).
  if (!user) {
    await webSession.destroy(req, res);
    return res.redirect(303, '/login');
  }

  res.type('html').send(
    renderer.renderAccount(settings, {
      user, stats, creds, points, history, champions, leagues, csrf: session.csrf, ...extra,
    })
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
    { notice: 'حُفظت كلمة المرور. أُنهيت الجلسات الأخرى.' });
});

router.post('/account/delete', async (req, res) => {
  const session = await requireSession(req, res);
  if (!session) return;
  if (!checkCsrf(session, req)) return res.status(403).send('طلب غير صالح');

  try {
    await authService.deleteAccount(session.userId, {
      password: String(req.body?.password || ''),
      confirmEmail: String(req.body?.confirmEmail || ''),
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

// تسجيل توقّع من الموقع.
//
// نفس predictionService الذي يستدعيه التطبيق — بابان بنفس القواعد
// لا بقاعدتين تنحرفان. والقاعدة الحاسمة (لا توقّع بعد الانطلاق)
// تُفحص هناك لا هنا، فلا يمكن أن ينساها باب.
router.post('/predict', async (req, res) => {
  const session = await webSession.read(req);
  if (!session) return res.redirect(303, '/login');
  if (!checkCsrf(session, req)) return res.status(403).send('طلب غير صالح');

  const fixtureId = Number(req.body?.fixture);
  const back = (suffix) => res.redirect(303, `/match/${fixtureId}${suffix}`);

  // زر "من سيفوز؟" يرسل pick بلا أرقام. الأرقام المكتوبة تسبقه
  // حين توجد: من عدّل النتيجة يقصدها، والاتجاه مشتقّ منها أصلاً.
  // الحقل الفارغ ليس صفراً.
  //
  // Number('') يساوي 0 وNumber.isInteger(0) صحيح، فكان الضغط على
  // "سجّل التوقّع" بحقلين فارغين يحفظ 0-0 بصمت — تعادلاً لم يقصده
  // أحد. نفحص النص الخام لا الرقم الناتج عنه.
  const raw = {
    home: String(req.body?.home ?? '').trim(),
    away: String(req.body?.away ?? '').trim(),
  };
  // فارغ واحد مع رقم = الفارغ صفر (من رفع رقماً لفريق يقصد أن
  // الآخر لم يسجّل). فارغان معاً = لا توقّع.
  const anyTyped = raw.home !== '' || raw.away !== '';
  const typed = {
    home: raw.home === '' ? 0 : Number(raw.home),
    away: raw.away === '' ? 0 : Number(raw.away),
  };
  const hasTyped = anyTyped
    && Number.isInteger(typed.home) && Number.isInteger(typed.away);
  const preset = predictionService.DEFAULT_SCORELINE[String(req.body?.pick || '')];

  // المضاعِف: مربّع اختيار، ومربّع الاختيار غير المؤشَّر لا يُرسل
  // شيئاً — فلا يمكن التفريق بين "ألغيتُه" و"لا أعرفه". لهذا يسبقه
  // حقل مخفي بقيمة 1، فيصل الاسم دائماً: مفرداً عند الإلغاء،
  // ومصفوفة ['1','2'] عند التأشير. الأخير هو المقصود.
  const multRaw = Array.isArray(req.body?.mult)
    ? req.body.mult[req.body.mult.length - 1]
    : req.body?.mult;
  const multiplier = multRaw === undefined ? null : Number(multRaw);

  const score = hasTyped ? typed : preset;
  if (!score) {
    return back('?err=' + encodeURIComponent('اختر الفائز أو اكتب النتيجة.'));
  }

  let saved;
  try {
    saved = await predictionService.submit({
      userId: session.userId,
      fixtureId,
      home: score.home,
      away: score.away,
      multiplier,
    });
  } catch (err) {
    if (err.status && err.expose) {
      return back(`?err=${encodeURIComponent(err.message)}`);
    }
    logger.error('[pages] predict failed:', err.message);
    return back('?err=' + encodeURIComponent('تعذّر حفظ التوقّع الآن.'));
  }

  // تحويل بعد النجاح: تحديث الصفحة لا يعيد الإرسال.
  back(saved?.multiplierDenied
    ? `?saved=1&warn=${encodeURIComponent(saved.multiplierDenied)}`
    : '?saved=1');
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
    pageContext(req),
    matchDetailService.get(fixture),
  ]);

  const predict = await buildPredict(req, settings, fixture);

  res.type('html').send(renderer.renderMatch(settings, { fixture, detail, predict }));
});

/**
 * سياق بطاقة التوقّع في صفحة المباراة.
 *
 * ترجع null للمباريات التي لا تدخل اللعبة (predictable = false):
 * الموقع يعرض ثماني بطولات واللعبة على دوري روشن وحده، وبطاقة
 * توقّع على مباراة إسبانية تَعِد بما سيرفضه السيرفر.
 */
async function buildPredict(req, settings, fixture) {
  if (!fixture.predictable) return null;

  const session = settings.viewer ? await webSession.read(req).catch(() => null) : null;

  const mine = settings.viewer
    ? (await predictionRepo
        .findByUserAndFixtures(settings.viewer.id, [fixture.id])
        .catch(() => []))[0] || null
    : null;

  return {
    open: predictionService.isOpen(fixture),
    viewer: Boolean(settings.viewer),
    csrf: session?.csrf || '',
    mine,
    // الاتجاه مشتقّ من التوقّع المحفوظ لا مخزّن معه: قيمة واحدة
    // في القاعدة (النتيجة) لا تتناقض مع نفسها.
    pick: predictionService.outcomeOf(mine),
    // النقاط من الإعدادات لا أرقاماً مكتوبة في النص: الأدمن يعدّلها
    // من اللوحة، ووعدٌ بخمس نقاط بينما النظام يمنح ثلاثاً هو أسوأ
    // ما يمكن أن يقرأه لاعب.
    points: await predictionService.points(),
    // حالة المضاعِف تُقرأ فقط لمن يستطيع التوقّع فعلاً: استعلام عدّ
    // إضافي على كل زائر لصفحة مباراة انتهت لا يُعرض ناتجه لأحد.
    mult: settings.viewer && predictionService.isOpen(fixture)
      ? await predictionService.multiplierState(settings.viewer.id, fixture, mine)
        // الفشل يخفي الأداة ولا يُسقط الصفحة — لكنه يُسجَّل: أداة
        // تختفي بلا أثر في السجل عطلٌ لا يبلّغ عنه أحد.
        .catch((err) => {
          logger.error('[pages] multiplier state failed:', err.message);
          return null;
        })
      : null,
    // أول مرة يصل فيها من التهيئة: لافتة تقول ماذا يفعل بالضبط.
    first: req.query.first === '1',
    saved: req.query.saved === '1',
    // تحذير لا خطأ: العملية نجحت وشيء فيها لم يُطبَّق.
    warn: req.query.warn ? String(req.query.warn).slice(0, 160) : null,
    error: req.query.err ? String(req.query.err).slice(0, 120) : null,
  };
}

// ─────────────────── الهدافون ───────────────────
router.get('/scorers', async (req, res) => {
  const leagues = await leagueRepo.findEnabled();
  const asked = String(req.query.league || '');
  const league = /^\d+$/.test(asked) && leagues.some((l) => String(l.id) === asked)
    ? Number(asked)
    : leagues[0]?.id;

  const settings = await pageContext(req);
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

  const [settings, page] = await Promise.all([pageContext(req), siteRepo.getPage(slug)]);
  if (!page) return next();

  res.type('html').send(renderer.renderPage(page, settings));
});

module.exports = router;
