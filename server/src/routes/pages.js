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
const groupService = require('../services/groupService');
const badgeService = require('../services/badgeService');
const groupRepo = require('../repositories/groupRepo');
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


// ─────────────────── توقّع الجولة ───────────────────
//
// تسع مباريات في صفحة وزرّ إرسال واحد. راجع renderRound للسبب.

/** عدد صغير من العنوان، محدود بسقف — أو صفر. */
function countParam(v, max) {
  const n = Number(v);
  return Number.isInteger(n) && n > 0 ? Math.min(n, max) : 0;
}

/** الجولة المقصودة: المطلوبة إن صحّت، وإلا أقرب جولة ما زالت مفتوحة. */
function pickRound(rounds, asked) {
  if (asked && rounds.some((r) => r.round === asked)) return asked;
  // أقرب جولة لم يُلعب أكثرها بعد.
  //
  // "أقرب جولة فيها مباراة مفتوحة" تبدو القاعدة الصحيحة وليست
  // كذلك: الجولة الثالثة هنا لُعبت ثمانٍ من تسع وبقيت واحدة
  // مؤجّلة، فتصير الوجهة الافتراضية صفحةً من تسعة صفوف ثمانيةٌ
  // منها مقفلة — وعنوانها "توقّع الجولة".
  //
  // والأغلبية معيار يقرأه المستخدم كما نقصده: هذه هي الجولة
  // القادمة. والمباراة المؤجّلة تبقى قابلة للتوقّع من صفحتها ومن
  // قائمة المباريات، فلا يُحرم منها أحد.
  const upcoming = rounds.find((r) => r.open * 2 > r.total)
    || rounds.find((r) => r.open > 0)
    || rounds[rounds.length - 1];
  return upcoming?.round || null;
}

router.get('/round', async (req, res) => {
  const all = await leagueRepo.findEnabled();
  const leagues = all.filter((l) => l.in_app);

  const askedLeague = String(req.query.league || '');
  const league = /^\d+$/.test(askedLeague) && leagues.some((l) => String(l.id) === askedLeague)
    ? Number(askedLeague)
    : leagues[0]?.id;
  const current = leagues.find((l) => l.id === league);
  if (!current) return res.redirect(303, '/');

  const rounds = await fixtureRepo.roundsFor(current.id, current.season);
  const round = pickRound(rounds, String(req.query.round || ''));

  const settings = await pageContext(req);
  const session = settings.viewer ? await webSession.read(req).catch(() => null) : null;

  const rows = round
    ? await fixtureRepo.byRound(current.id, current.season, round)
    : [];

  // open مشتقّ هنا مرة واحدة: الحالة والوقت معاً، تماماً كما
  // يفحصهما predictionService — فما تعرضه الصفحة قابلاً للتحرير
  // هو ما يقبله الخادم، بلا اجتهاد ثانٍ يفترق عنه.
  const fixtures = rows.map((f) => ({ ...f, open: predictionService.isOpen(f) }));

  const [saved, mult, points] = await Promise.all([
    settings.viewer
      ? predictionRepo.findByUserAndFixtures(settings.viewer.id, fixtures.map((f) => f.id))
        .catch(() => [])
      : [],
    settings.viewer && fixtures.length
      ? predictionService.multiplierState(settings.viewer.id, fixtures[0], null).catch(() => null)
      : null,
    predictionService.points(),
  ]);

  const mine = {};
  for (const p of saved) mine[p.fixture_id] = p;

  res.type('html').send(renderer.renderRound(settings, {
    leagues, league: current.id, rounds, round, fixtures, mine, points, mult,
    csrf: session?.csrf || '',
    viewer: Boolean(settings.viewer),
    // أعداد لا جُمل — العرض يصوغها بالعربية. وnum يحدّها بعدد
    // معقول: الرقم يأتي من العنوان، ومن يكتب 99999 في شريط
    // المتصفح يجب ألا يقرأ "حُفظ 99999 توقّعاً".
    result: {
      ok: countParam(req.query.ok, fixtures.length),
      denied: countParam(req.query.denied, fixtures.length),
      late: countParam(req.query.late, fixtures.length),
      none: req.query.none === '1',
    },
  }));
});

router.post('/round', async (req, res) => {
  const session = await webSession.read(req);
  if (!session) return res.redirect(303, '/login');
  if (!checkCsrf(session, req)) return res.status(403).send('طلب غير صالح');

  const league = Number(req.body?.league);
  const round = String(req.body?.round || '');
  const back = (q) => res.redirect(303,
    `/round?league=${league}&round=${encodeURIComponent(round)}${q}`);

  const current = (await leagueRepo.findEnabled()).find((l) => l.id === league && l.in_app);
  if (!current || !round) return res.redirect(303, '/round');

  // المباريات من القاعدة لا من الجسم المرسل: الجسم يكتبه العميل،
  // ومن يصنع طلباً بيده يستطيع إقحام مباراة من جولة أخرى — بل من
  // دوري لا يتابعه. نعتمد قائمة الخادم ونقرأ منها ما وصل.
  const fixtures = await fixtureRepo.byRound(current.id, current.season, round);

  let ok = 0;
  const denied = [];
  const failed = [];

  for (const f of fixtures) {
    const raw = {
      home: String(req.body?.[`h_${f.id}`] ?? '').trim(),
      away: String(req.body?.[`a_${f.id}`] ?? '').trim(),
    };
    // الصفّان الفارغان معاً = لا توقّع لهذه المباراة. وهذا هو
    // الحال الغالب في صفحة تعرض تسعاً: من يتوقّع ثلاثاً يترك ستّاً
    // فارغة، وحفظها 0-0 يمنحه ستّة تعادلات لم يقصدها.
    if (raw.home === '' && raw.away === '') continue;

    const home = raw.home === '' ? 0 : Number(raw.home);
    const away = raw.away === '' ? 0 : Number(raw.away);
    if (!Number.isInteger(home) || !Number.isInteger(away)) {
      failed.push(f);
      continue;
    }

    try {
      const row = await predictionService.submit({
        userId: session.userId,
        fixtureId: f.id,
        home,
        away,
        // غير المؤشَّر يعني 1 صراحةً لا "اتركه": الصفحة تعرض حالة
        // كل مربّع، فإلغاء التأشير فيها قرارٌ لا سهو.
        multiplier: req.body?.[`m_${f.id}`] ? 2 : 1,
      });
      ok += 1;
      if (row?.multiplierDenied) denied.push(f);
    } catch (err) {
      // مباراة انطلقت بين رسم الصفحة وإرسالها: تُتخطّى ولا تُسقط
      // البقية. حفظ سبع من تسع أفضل من رفض التسع لأجل واحدة.
      failed.push(f);
    }
  }

  if (!ok && !failed.length) {
    return back('&none=1');
  }

  // أرقام لا جُملاً: صياغة العربية وجمعُها يسكنان في طبقة العرض
  // (counted هناك)، ونقلُهما إلى المسار يفتح نسخة ثانية من قواعد
  // الجمع تتباعد عن الأولى — وقد كلّفنا هذا "مباراتين تُقفل" من
  // قبل. المسار يقول ماذا حدث بالعدد، والعرض يقوله بالعربية.
  back(`&ok=${ok}&denied=${denied.length}&late=${failed.length}`);
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
    return res.redirect(303, afterAuth(req, user));
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
    return res.redirect(303, afterAuth(req, user));
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
function afterAuth(req, user) {
  // الدعوة أولاً: من وصل برابط صديق جاء للمجلس لا لشاشة تهيئة،
  // وتأجيلُه خلفها يجعله يبحث عن الرابط بعدها — وأكثرُهم لن يجده.
  // والتهيئة تُعرض له في دخوله التالي، فلا شيء يضيع.
  const invite = readInvite(req);
  if (invite) return `/join/${encodeURIComponent(invite)}`;

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
    return res.redirect(303, afterAuth(req, user));
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
    return res.redirect(303, afterAuth(req, user));
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




// ─────────────────── صفحة لاعب عامة ───────────────────
//
// ما يُعرض هنا هو ما يُعرض في العرش موسّعاً. راجع renderPlayer
// لما لا يُعرض ولماذا.
router.get('/player/:id', async (req, res) => {
  const settings = await pageContext(req);
  const id = String(req.params.id || '');

  // فحص الشكل قبل الاستعلام: معرّف ليس UUID يجعل pg يرمي خطأ نوع
  // (22P02) لا يرجع صفراً، فيتحوّل رابطٌ مكسور إلى خطأ 500.
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) {
    return res.status(404).type('html').send(renderer.renderNotFound(settings));
  }

  const player = await userRepo.findById(id).catch(() => null);
  if (!player) {
    return res.status(404).type('html').send(renderer.renderNotFound(settings));
  }

  const [stats, badges] = await Promise.all([
    predictionRepo.profileStats(id).catch(() => null),
    badgeService.forUser(id).catch(() => []),
  ]);

  res.type('html').send(renderer.renderPlayer(settings, {
    // الاسم وحده من صفّ المستخدم — لا بريد ولا تواريخ. الصفحة
    // عامة، وكل حقل يُمرَّر إليها يصير منشوراً.
    player: { display_name: player.display_name || 'مشجع' },
    stats,
    badges,
    isMe: settings.viewer?.id === id,
  }));
});

// ─────────────────── المجالس ───────────────────
//
// القواعد كلها في groupService — راجعه. هذه الصفحات نماذج ورسائل.

/** كوكي الدعوة: يحمل رمزاً عبر رحلة التسجيل حتى تنتهي بالانضمام. */
const INVITE_COOKIE = 'sah_invite';

function setInvite(res, code, secure) {
  res.setHeader('Set-Cookie',
    `${INVITE_COOKIE}=${encodeURIComponent(code)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=1800`
    + (secure ? '; Secure' : ''));
}
function readInvite(req) {
  const m = new RegExp(`(?:^|;\\s*)${INVITE_COOKIE}=([^;]+)`).exec(req.headers.cookie || '');
  return m ? decodeURIComponent(m[1]) : null;
}
function clearInvite(res, secure) {
  res.setHeader('Set-Cookie',
    `${INVITE_COOKIE}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0` + (secure ? '; Secure' : ''));
}

router.get('/groups', async (req, res) => {
  const session = await webSession.read(req);
  if (!session) return res.redirect(303, '/login');

  const [settings, groups] = await Promise.all([
    pageContext(req),
    groupRepo.findMine(session.userId).catch(() => []),
  ]);

  res.type('html').send(renderer.renderGroups(settings, {
    groups,
    csrf: session.csrf,
    notice: req.query.ok ? String(req.query.ok).slice(0, 120) : null,
    error: req.query.err ? String(req.query.err).slice(0, 120) : null,
  }));
});

router.post('/groups', async (req, res) => {
  const session = await webSession.read(req);
  if (!session) return res.redirect(303, '/login');
  if (!checkCsrf(session, req)) return res.status(403).send('طلب غير صالح');

  try {
    const group = await groupService.create({
      ownerId: session.userId, name: req.body?.name,
    });
    // إلى المجلس مباشرة لا إلى القائمة: أول ما يحتاجه المؤسّس
    // رابطُ الدعوة، ومجلسٌ بعضو واحد لا قيمة له حتى يدعو.
    return res.redirect(303, `/groups/${group.id}`);
  } catch (err) {
    if (err.status && err.expose) {
      return res.redirect(303, `/groups?err=${encodeURIComponent(err.message)}`);
    }
    logger.error('[pages] group create failed:', err.message);
    return res.redirect(303, '/groups?err=' + encodeURIComponent('تعذّر إنشاء المجلس الآن.'));
  }
});

router.post('/groups/join', async (req, res) => {
  const session = await webSession.read(req);
  if (!session) return res.redirect(303, '/login');
  if (!checkCsrf(session, req)) return res.status(403).send('طلب غير صالح');

  try {
    const { group, already } = await groupService.join({
      userId: session.userId, code: req.body?.code,
    });
    // العضو القائم يُرحَّب به لا يُخطَّأ: ضغط الرابط مرتين نيّةُ
    // وصول، والرسالة الوحيدة الصحيحة هي أن يجد نفسه في المجلس.
    return res.redirect(303, `/groups/${group.id}${already ? '' : '?ok=' + encodeURIComponent('انضممت إلى المجلس.')}`);
  } catch (err) {
    if (err.status && err.expose) {
      return res.redirect(303, `/groups?err=${encodeURIComponent(err.message)}`);
    }
    logger.error('[pages] group join failed:', err.message);
    return res.redirect(303, '/groups?err=' + encodeURIComponent('تعذّر الانضمام الآن.'));
  }
});

router.get('/groups/:id', async (req, res) => {
  const session = await webSession.read(req);
  if (!session) return res.redirect(303, '/login');

  const settings = await pageContext(req);
  try {
    // الموقع يرسم الترتيب تحت اسم members منذ نسخته الأولى؛ الخدمة
    // صارت تفرّق بين الترتيب (leaderboard) وقائمة الأعضاء بأدوارهم
    // (members)، والصفحة هنا تريد الأول.
    const { group, leaderboard } = await groupService.view({
      userId: session.userId, groupId: req.params.id,
    });
    res.type('html').send(renderer.renderGroup(settings, {
      group, members: leaderboard, me: session.userId, csrf: session.csrf,
      siteUrl: (process.env.SITE_URL || '').replace(/\/+$/, ''),
      notice: req.query.ok ? String(req.query.ok).slice(0, 120) : null,
      error: req.query.err ? String(req.query.err).slice(0, 120) : null,
    }));
  } catch (err) {
    // معرّف غير موجود أو ليس UUID أصلاً — كلاهما "غير موجود"
    // لغير العضو، فلا يُفرَّق بينهما في الرد.
    if (err.status && err.expose) return res.status(404).type('html').send(renderer.renderNotFound(settings));
    throw err;
  }
});

router.post('/groups/:id/leave', async (req, res) => {
  const session = await webSession.read(req);
  if (!session) return res.redirect(303, '/login');
  if (!checkCsrf(session, req)) return res.status(403).send('طلب غير صالح');

  try {
    await groupService.leave({ userId: session.userId, groupId: req.params.id });
    res.redirect(303, '/groups?ok=' + encodeURIComponent('غادرت المجلس.'));
  } catch (err) {
    const msg = err.expose ? err.message : 'تعذّرت المغادرة الآن.';
    res.redirect(303, `/groups?err=${encodeURIComponent(msg)}`);
  }
});

router.post('/groups/:id/delete', async (req, res) => {
  const session = await webSession.read(req);
  if (!session) return res.redirect(303, '/login');
  if (!checkCsrf(session, req)) return res.status(403).send('طلب غير صالح');

  try {
    await groupService.remove({ userId: session.userId, groupId: req.params.id });
    res.redirect(303, '/groups?ok=' + encodeURIComponent('حُذف المجلس.'));
  } catch (err) {
    const msg = err.expose ? err.message : 'تعذّر الحذف الآن.';
    res.redirect(303, `/groups?err=${encodeURIComponent(msg)}`);
  }
});

/**
 * رابط الدعوة — الوجه العام للمجالس.
 *
 * هذا المسار هو محرّك النمو كله: رابطٌ يُلصق في واتساب، ومن يضغطه
 * وهو مسجَّل ينضمّ في خطوة واحدة، ومن ليس له حساب يرى اسم المجلس
 * وعدد أعضائه ثم يُسجّل — ويُنضمّ فور تسجيله بلا أن يعود للبحث عن
 * الرابط.
 *
 * والذاكرة كوكي نصف ساعة لا معلمة في العنوان: رحلة التسجيل قد
 * تمرّ بجوجل أو آبل وتعود إلى مسار callback عندهما، ولا مكان في
 * تلك الرحلة لحمل معلمة من عنواننا. والكوكي يعبرها كلها.
 */
router.get('/join/:code', async (req, res) => {
  const code = groupService.normalizeCode(req.params.code);
  const settings = await pageContext(req);
  const session = await webSession.read(req).catch(() => null);

  const group = await groupRepo.findByCode(code).catch(() => null);
  if (!group) {
    return res.status(404).type('html').send(renderer.renderJoin(settings, { group: null }));
  }

  if (session) {
    try {
      const { group: joined, already } = await groupService.join({
        userId: session.userId, code,
      });
      clearInvite(res, isSecure(req));
      return res.redirect(303, `/groups/${joined.id}${already ? '' : '?ok=' + encodeURIComponent('انضممت إلى المجلس.')}`);
    } catch (err) {
      const msg = err.expose ? err.message : 'تعذّر الانضمام الآن.';
      return res.status(err.status || 500).type('html')
        .send(renderer.renderJoin(settings, { group: null, error: msg }));
    }
  }

  // ضيف: نحفظ الرمز ونعرض الدعوة.
  //
  // الصفحة معاينة الرابط أيضاً: واتساب يقرأ og:image وog:title منها،
  // فصورة المجلس واسمه هما ما يراه المدعوّ قبل أن يضغط.
  setInvite(res, code, isSecure(req));
  const siteUrl = (process.env.SITE_URL || '').replace(/\/+$/, '');
  res.type('html').send(renderer.renderJoin(settings, {
    group: {
      name: group.name,
      members_count: group.members_count,
      league_name: group.league_name,
      join_policy: group.join_policy,
      image_url: group.image_url,
    },
    imageAbs: group.image_url && siteUrl ? `${siteUrl}${group.image_url}` : null,
  }));
});

// ─────────────────── التهيئة: ثلاث خطوات ───────────────────
//
// دورياتك ← فريقك ← البطل. وكلٌّ ضغطة واحدة، والتخطّي مفتوح في
// كلٍّ منها. راجع renderWelcome لسبب هذا الترتيب.

// بطاقات البطل تُبنى في championService — ثلاثة مستدعين لها الآن
// (الترتيب، الحساب، التطبيق)، وتجميعها هنا كان يجعلها حكراً على
// الويب.
const championCard = (userId, league) => championService.card(userId, league);
const championCards = (userId) => championService.cards(userId);

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



// تغيير الفريق المفضّل من الإعدادات — التهيئة تُعرض مرة واحدة.
router.post('/account/team', async (req, res) => {
  const session = await webSession.read(req);
  if (!session) return res.redirect(303, '/login');
  if (!checkCsrf(session, req)) return res.status(403).send('طلب غير صالح');

  const teamId = Number(req.body?.team);
  if (Number.isInteger(teamId)) {
    await userRepo.updateProfile(session.userId, { favoriteTeamId: teamId });
  }
  res.redirect(303, '/account?tab=settings#team');
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
  res.redirect(303, '/account?tab=settings#leagues');
});

/** أندية الدوريات التي يتابعها — لاختيار فريقه المفضّل. */
async function followedTeams(userId) {
  const followed = await championRepo.followedIds(userId);
  if (!followed.length) return [];
  const teams = await teamRepo.findPlayable();
  return teams.filter((t) => followed.includes(t.league_id));
}

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
  const [settings, user, stats, creds, points, history, champions, leagues, teams, badges] = await Promise.all([
    pageContext(req),
    userRepo.findById(session.userId),
    predictionRepo.profileStats(session.userId).catch(() => null),
    authService.credentials(session.userId).catch(() => null),
    predictionService.points().catch(() => null),
    // آخر عشرين: السجل الكامل قد يبلغ مئات الصفوف في نهاية الموسم،
    // ومن يريد أقدم منها يريد تصفّحاً لا صفحة أطول.
    // خمسون لا عشرون: صار للسجلّ تبويبٌ خاصّ به، ومن يفتحه يفتحه
    // ليقرأه. العشرون كانت مناسبةً حين كان قسماً بين ستة أقسام.
    predictionRepo.findMine(session.userId).then((r) => r.slice(0, 50)).catch(() => []),
    // بطاقات البطل تحتاج سعراً حيّاً لكل دوري، وفشلها لا يُسقط
    // الصفحة: من فتح حسابه ليغيّر كلمة سره لا يُحرم منها لأن
    // استعلام رهانٍ تعثّر.
    championCards(session.userId).catch(() => []),
    followableLeagues(session.userId).catch(() => []),
    // أندية ما يتابعه — لتغيير الفريق المفضّل من الإعدادات.
    followedTeams(session.userId).catch(() => []),
    badgeService.forUser(session.userId).catch(() => []),
  ]);

  // الحساب حُذف بينما الجلسة حية (من التطبيق مثلاً).
  if (!user) {
    await webSession.destroy(req, res);
    return res.redirect(303, '/login');
  }

  res.type('html').send(
    renderer.renderAccount(settings, {
      user, stats, creds, points, history, champions, leagues, teams, badges,
      tab: String(req.query.tab || ''), csrf: session.csrf, ...extra,
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
