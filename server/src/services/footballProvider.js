// footballProvider — طبقة العزل الوحيدة أمام API-Football.
//
// القاعدة: لا يوجد أي ملف آخر في المشروع يعرف عنوان المزود، مفتاحه،
// أو شكل استجابته الخام. كل ما يخرج من هنا بيانات "خام من المزود"
// تذهب مباشرة إلى الـ mappers للتطبيع. لو غيّرنا المزود مستقبلاً،
// نعيد كتابة هذا الملف + الـ mappers فقط.
//
// كل دالة عامة هنا تمر بنفس المسار:
//   1. Redis أولاً — لو النتيجة مخبّأة نرجعها فوراً (صفر طلبات خارجية).
//   2. وضع العينات (USE_SAMPLES=true) — نقرأ من samples/ بدل الشبكة.
//   3. الشبكة — بعد المرور على rateLimiter الذي يمنع تجاوز 100 طلب/يوم.
const fs = require('fs/promises');
const path = require('path');
const redis = require('../config/redis');
const rateLimiter = require('../utils/rateLimiter');
const logger = require('../utils/logger');

const BASE_URL = process.env.FOOTBALL_API_URL || 'https://v3.football.api-sports.io';
const SAMPLES_DIR = path.join(__dirname, '..', '..', 'samples');

// مدد الكاش بالثواني، حسب طبيعة كل نوع بيانات (كما في المواصفات).
const TTL = {
  LIVE: 30,            // مباراة جارية: النتيجة تتغير كل لحظة
  FIXTURES: 6 * 3600,  // جدول المباريات: يتغير نادراً
  STANDINGS: 3600,     // الترتيب: يتغير بعد كل جولة
  LINEUPS: 24 * 3600,  // التشكيلات
  EVENTS: 60,          // أحداث مباراة (أهداف/بطاقات) — قصيرة لأنها قد تكون جارية
  LEAGUES_SEARCH: 24 * 3600, // بحث الدوريات: قائمة المزود شبه ثابتة
  STATISTICS: 120,     // إحصاءات مباراة: تتغير أثناء اللعب كالأحداث
  SCORERS: 6 * 3600,   // الهدافون: ترتيب لا يتغير إلا بعد جولة
  H2H: 24 * 3600,      // المواجهات السابقة: تاريخ لا يتغير إلا بمباراة جديدة
  // أحداث وإحصاءات مباراة **انتهت**: لن تتغيّر بعد الآن، وكاش
  // الدقيقة كان يعيد شراءها من المزوّد لكل من فتح مباراة الأمس.
  SETTLED: 6 * 3600,
};

// ---------------------------------------------------------------
// الجوهر المشترك: كاش ← عينات ← شبكة
// ---------------------------------------------------------------

// endpoint: المسار عند المزود، مثال 'fixtures'
// params:   بارامترات الاستعلام، مثال { league: 307, season: 2025 }
// options:  { cacheKey, ttl, sampleFile }
async function request(endpoint, params, { cacheKey, ttl, sampleFile }) {
  // 1) الكاش
  // try/catch حول Redis: لو Redis واقع نكمل بدون كاش بدل أن نفشل.
  try {
    const cached = await redis.get(cacheKey);
    if (cached) return JSON.parse(cached);
  } catch (err) {
    logger.warn('[provider] cache read failed, continuing without cache:', err.message);
  }

  let items;
  if (process.env.USE_SAMPLES === 'true') {
    items = await readSample(sampleFile);
  } else {
    items = await fetchFromApi(endpoint, params);
  }

  try {
    // 'EX' = انتهاء الصلاحية بالثواني. بعد المدة يحذف Redis المفتاح
    // تلقائياً والطلب التالي يذهب للمصدر من جديد.
    await redis.set(cacheKey, JSON.stringify(items), 'EX', ttl);
  } catch (err) {
    logger.warn('[provider] cache write failed:', err.message);
  }

  return items;
}

async function fetchFromApi(endpoint, params) {
  // العدّاد قبل الطلب: يرمي خطأ لو استهلكنا حصة اليوم.
  await rateLimiter.consume();

  const url = new URL(`${BASE_URL}/${endpoint}`);
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null) {
      url.searchParams.set(key, value);
    }
  }

  logger.info(`[provider] GET ${endpoint}`, params);

  // fetch مدمجة في Node 18+ — لا نحتاج axios لطلبات GET بسيطة.
  const res = await fetch(url, {
    headers: { 'x-apisports-key': process.env.FOOTBALL_API_KEY },
  });

  if (!res.ok) {
    throw new Error(`API-Football returned HTTP ${res.status} for ${endpoint}`);
  }

  const body = await res.json();

  // خصوصية API-Football: أخطاء كثيرة (مفتاح خاطئ، تجاوز الحصة) تصل
  // بحالة HTTP 200 لكن مع حقل errors مملوء. يجب فحصه وإلا خزّنّا فراغاً.
  if (body.errors && Object.keys(body.errors).length > 0) {
    throw new Error(`API-Football error: ${JSON.stringify(body.errors)}`);
  }

  // المزود يغلّف النتائج دائماً في { response: [...] } — نفكّ الغلاف
  // هنا حتى لا يعرف بقية المشروع شيئاً عن هذا الشكل.
  return body.response;
}

async function readSample(sampleFile) {
  const filePath = path.join(SAMPLES_DIR, sampleFile);
  try {
    const raw = await fs.readFile(filePath, 'utf8');
    const body = JSON.parse(raw);
    // ملفات العينات نسخ كاملة من استجابة المزود، فنفكّ نفس الغلاف.
    return body.response;
  } catch (err) {
    throw new Error(
      `USE_SAMPLES=true but could not read samples/${sampleFile}: ${err.message}`
    );
  }
}

// ---------------------------------------------------------------
// الواجهة العامة — هذه الدوال فقط ما يستعمله بقية المشروع
// ---------------------------------------------------------------

const LEAGUE = () => process.env.LEAGUE_ID;
const SEASON = () => process.env.SEASON;

// كل دالة تقبل الآن كائن خيارات { leagueId, season } اختياري.
// نحلّه هنا مرة واحدة: الغائب يعود لقيمة .env، فكل مستدعٍ قديم
// يكتب getTeams() بلا وسائط ويحصل على سلوكه السابق حرفياً.
function resolve({ leagueId, season } = {}) {
  return { league: leagueId ?? LEAGUE(), season: season ?? SEASON() };
}

// ملاحظة حرجة تخص كل مفتاح كاش في هذا الملف:
// مفتاح الكاش يجب أن يحتوي معرّف الدوري. كانت المفاتيح تكتفي
// بالموسم أيام الدوري الواحد، وهذا يصبح خطأً صامتاً مع التعدد:
// أول دوري يُطلب يخزّن استجابته تحت المفتاح، ثم يأتي دوري آخر
// بنفس الموسم فيجد المفتاح موجوداً ويستلم مباريات الدوري الأول
// دون أي خطأ يكشف المشكلة. المعرّف في المفتاح هو ما يفصل بينهما.

// كل مباريات الموسم (تُستخدم في المزامنة الدورية).
function getSeasonFixtures(options) {
  const { league, season } = resolve(options);
  return request('fixtures', { league, season }, {
    cacheKey: `football:fixtures:season:${league}:${season}`,
    ttl: TTL.FIXTURES,
    sampleFile: 'fixtures.json',
  });
}

// مباريات يوم محدد (تنسيق YYYY-MM-DD بتوقيت UTC كما يفهمه المزود).
// تستخدمها المزامنة المباشرة: طلب واحد يرجع مباريات اليوم كلها
// بحالاتها اللحظية — الجارية بنتيجتها الحالية والمنتهية بحالة FT —
// فنحصل على التحديث المباشر ولحظة الانتهاء من نفس الطلب.
// كاش 30 ثانية فقط لأن النتيجة تتغير أثناء اللعب.
function getFixturesByDate(date, options) {
  const { league, season } = resolve(options);
  return request('fixtures', { league, season, date }, {
    cacheKey: `football:fixtures:date:${league}:${season}:${date}`,
    ttl: TTL.LIVE,
    sampleFile: 'fixtures.json',
  });
}

// المباريات الجارية الآن — كاش قصير (30 ثانية).
function getLiveFixtures(options) {
  const { league } = resolve(options);
  return request('fixtures', { league, live: 'all' }, {
    cacheKey: `football:fixtures:live:${league}`,
    ttl: TTL.LIVE,
    sampleFile: 'fixtures_live.json',
  });
}

// أحداث مباراة واحدة (أهدف، بطاقات، تبديلات).
//
// `settled` من المستدعي لا من هنا: المزوّد لا يقول في ردّ الأحداث
// إن كانت المباراة انتهت، والمستدعي يحمل صفّ المباراة ويعرف.
// ومفتاح الكاش واحد في الحالتين عمداً — آخر جلب أثناء اللعب يصلح
// أول جلب بعد النهاية، ولا نشتري القائمة مرتين.
function getFixtureEvents(fixtureId, { settled = false } = {}) {
  return request('fixtures/events', { fixture: fixtureId }, {
    cacheKey: `football:events:${fixtureId}`,
    ttl: settled ? TTL.SETTLED : TTL.EVENTS,
    sampleFile: 'fixture_events.json',
  });
}

// تشكيلتا الفريقين. تُنشر قبل ~ساعة من الانطلاق ولا تتغير بعدها،
// فكاش يوم كامل آمن — والنداء قبل النشر يرجع فارغاً لا خطأ.
function getFixtureLineups(fixtureId) {
  return request('fixtures/lineups', { fixture: fixtureId }, {
    cacheKey: `football:lineups:${fixtureId}`,
    ttl: TTL.LINEUPS,
    sampleFile: 'fixture_lineups.json',
  });
}

/**
 * آخر مواجهات بين فريقين.
 *
 * كاش يوم كامل: القائمة لا تتغير إلا حين يلتقيان مجدداً، وذلك
 * مرة أو مرتين في الموسم. الترتيب في المفتاح موحّد (الأصغر أولاً)
 * كي لا تُخزَّن نسختان لنفس المواجهة حسب من كان مضيفاً.
 */
function getHeadToHead(a, b, last = 5) {
  const [x, y] = [a, b].sort((m, n) => m - n);
  return request('fixtures/headtohead', { h2h: `${a}-${b}`, last }, {
    cacheKey: `football:h2h:${x}:${y}:${last}`,
    ttl: TTL.H2H,
    sampleFile: 'fixture_h2h.json',
  });
}

// إحصاءات المباراة: استحواذ، تسديدات، ركنيات، بطاقات.
function getFixtureStatistics(fixtureId, { settled = false } = {}) {
  return request('fixtures/statistics', { fixture: fixtureId }, {
    cacheKey: `football:stats:${fixtureId}`,
    ttl: settled ? TTL.SETTLED : TTL.STATISTICS,
    sampleFile: 'fixture_statistics.json',
  });
}

// هدافو الدوري.
//
// المزود يرجع 20 لاعباً افتراضياً وهو كافٍ للعرض. الكاش ست ساعات
// لأن القائمة لا تتغير إلا بعد جولة كاملة، ونداءٌ لكل زائر كان
// سيستهلك الحصة على بيانات ثابتة عملياً.
function getTopScorers(options) {
  const { league, season } = resolve(options);
  return request('players/topscorers', { league, season }, {
    cacheKey: `football:scorers:${league}:${season}`,
    ttl: TTL.SCORERS,
  });
}

/**
 * حالة الاشتراك: الخطة، تاريخ الانتهاء، والمستهلك من الحصة اليومية.
 *
 * بلا كاش عمداً: تُنادى مرة يومياً من وظيفة المراقبة، وقيمتها كلها
 * في كونها لحظية — رقم استهلاك عمره ساعة لا يفيد في إنذار.
 *
 * وهي لا تُحتسب على الحصة نفسها عند المزوّد.
 */
async function getStatus() {
  const res = await fetch(`${BASE_URL}/status`, {
    headers: { 'x-apisports-key': process.env.FOOTBALL_API_KEY },
    signal: AbortSignal.timeout(10000),
  });
  if (!res.ok) throw new Error(`status ${res.status}`);
  const json = await res.json();
  const r = json.response || {};
  return {
    plan: r.subscription?.plan ?? null,
    endsAt: r.subscription?.end ?? null,
    active: r.subscription?.active ?? false,
    used: r.requests?.current ?? 0,
    limit: r.requests?.limit_day ?? 0,
  };
}

// فرق الدوري للموسم الحالي.
function getTeams(options) {
  const { league, season } = resolve(options);
  return request('teams', { league, season }, {
    cacheKey: `football:teams:${league}:${season}`,
    ttl: TTL.FIXTURES,
    sampleFile: 'teams.json',
  });
}

// جدول الترتيب.
function getStandings(options) {
  const { league, season } = resolve(options);
  return request('standings', { league, season }, {
    cacheKey: `football:standings:${league}:${season}`,
    ttl: TTL.STANDINGS,
    sampleFile: 'standings.json',
  });
}

// البحث عن دوري بالاسم — الطريقة الوحيدة لمعرفة معرّف دوري جديد
// بلا مغادرة اللوحة. لا تأخذ league/season لأنها هي التي تكتشفهما.
//
// كاش 24 ساعة: قائمة الدوريات عند المزود شبه ثابتة، والأدمن يجرب
// كلمات بحث متقاربة ("saudi" ثم "saudi pro") — الكاش يجعل التجربة
// الثانية على نفس الكلمة مجانية. نطبّع الكلمة (حروف صغيرة + قصّ
// الفراغات) داخل المفتاح حتى لا تصير "Saudi" و"saudi " مفتاحين.
function searchLeagues(query) {
  const q = String(query).trim().toLowerCase();
  return request('leagues', { search: q }, {
    cacheKey: `football:leagues:search:${q}`,
    ttl: TTL.LEAGUES_SEARCH,
    sampleFile: 'leagues.json',
  });
}

module.exports = {
  getSeasonFixtures,
  getFixturesByDate,
  getLiveFixtures,
  getFixtureEvents,
  getFixtureLineups,
  getFixtureStatistics,
  getTopScorers,
  getHeadToHead,
  getStatus,
  getTeams,
  getStandings,
  searchLeagues,
};
