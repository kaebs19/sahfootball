// routes/admin — مسارات لوحة التحكم. كل شيء هنا خلف حارسين:
// requireAuth (من أنت؟) ثم requireAdmin (هل يحق لك؟).
// router.use يطبقهما على كل مسارات الملف دفعة واحدة.
const express = require('express');
const requireAuth = require('../middleware/requireAuth');
const requireAdmin = require('../middleware/requireAdmin');
const settingsRepo = require('../repositories/settingsRepo');
const scoringService = require('../services/scoringService');
const teamRepo = require('../repositories/teamRepo');
const userRepo = require('../repositories/userRepo');
const refreshTokenRepo = require('../repositories/refreshTokenRepo');
const { deleteAvatarFile } = require('../utils/avatarFile');
const leagueRepo = require('../repositories/leagueRepo');
const siteRepo = require('../repositories/siteRepo');
const siteSettings = require('../services/siteSettings');
const footballProvider = require('../services/footballProvider');
const standingsService = require('../services/standingsService');
const rateLimiter = require('../utils/rateLimiter');
const db = require('../config/db');
const { syncAll, syncLeague } = require('../jobs/syncFixtures');

const router = express.Router();
router.use(requireAuth, requireAdmin);

// GET /api/admin/stats — أرقام الشاشة الرئيسية للوحة.
//
// أربعة استعلامات وليس واحداً: العدّادات المفردة تُدمج بشكل طبيعي
// في صف واحد، أما السلاسل (رسم بياني، توزيع، أفضل خمسة) فكل منها
// عدة صفوف بأعمدة مختلفة — حشرها في استعلام واحد يحتاج حيلاً
// (json_agg متداخلة) تجعل الاستعلام غير قابل للقراءة بلا مقابل:
// الأربعة تمشي على التوازي بـ Promise.all وتصل معاً.
router.get('/stats', async (req, res) => {
  const [counters, daily, distribution, topUsers, byLeague] = await Promise.all([
    // 1) العدّادات المفردة — استعلام واحد بعدّادات مشروطة (FILTER)
    // بدل عشرة استعلامات. FILTER هي طريقة PostgreSQL لقول
    // "عدّ ما يطابق الشرط فقط".
    db.query(`
      SELECT
        (SELECT COUNT(*) FROM users)::int                                  AS users,
        (SELECT COUNT(*) FROM users
          WHERE created_at >= now() - interval '7 days')::int              AS users_new_7d,
        (SELECT COUNT(*) FROM predictions)::int                            AS predictions,
        (SELECT COUNT(*) FROM predictions
          WHERE created_at >= now() - interval '7 days')::int              AS predictions_7d,
        -- "نشِط" = توقّع فعلاً، وليس مجرد فتح التطبيق. DISTINCT لأن
        -- من توقّع عشر مباريات مستخدم واحد لا عشرة.
        (SELECT COUNT(DISTINCT user_id) FROM predictions
          WHERE created_at >= now() - interval '7 days')::int              AS active_users_7d,
        -- الرقم الذي يكشف عطلاً: توقعات على مباريات منتهية ولم
        -- تُحتسب. المفترض أن يكون صفراً دائماً — أي رقم أكبر يعني
        -- أن الاحتساب لم يعمل، وحلّه زر "احسب الآن".
        (SELECT COUNT(*) FROM predictions p
           JOIN fixtures f ON f.id = p.fixture_id
          WHERE p.settled_at IS NULL AND f.status = 'finished')::int       AS pending_settlement,
        (SELECT COUNT(*) FROM teams)::int                                  AS teams,
        (SELECT COUNT(*) FROM teams WHERE name_ar IS NOT NULL)::int        AS teams_translated,
        (SELECT COUNT(*) FROM groups)::int                                 AS groups,
        (SELECT COUNT(*) FROM groups
          WHERE created_at >= now() - interval '7 days')::int              AS groups_7d,
        (SELECT COUNT(*) FILTER (WHERE enabled) FROM leagues)::int         AS leagues_enabled,
        (SELECT COUNT(*) FROM leagues)::int                                AS leagues_total,
        (SELECT COUNT(*) FILTER (WHERE status = 'scheduled') FROM fixtures)::int AS fixtures_scheduled,
        (SELECT COUNT(*) FILTER (WHERE status = 'live')      FROM fixtures)::int AS fixtures_live,
        (SELECT COUNT(*) FILTER (WHERE status = 'finished')  FROM fixtures)::int AS fixtures_finished,
        -- شارة صندوق الوارد في الشريط الجانبي. مكانها هنا وليس في
        -- طلب مستقل: اللوحة تجلب /stats عند كل فتح أصلاً، ورسالة
        -- تنتظر أسبوعاً لأن أحداً لم يفتح صفحة الرسائل هي بالضبط
        -- ما تمنعه الشارة.
        (SELECT COUNT(*) FROM contact_messages WHERE read_at IS NULL)::int AS unread_messages
    `),

    // 2) توقعات آخر 14 يوماً للرسم البياني.
    //
    // generate_series تولّد صفوف التواريخ الأربعة عشر كاملةً من
    // العدم، ثم LEFT JOIN يعلّق عليها التوقعات. النتيجة: يوم بلا
    // توقعات يظهر بـ count = 0 بدل أن يغيب. لو بدأنا من جدول
    // predictions (GROUP BY تاريخ) لاختفت الأيام الفارغة تماماً
    // ولانضغط الرسم البياني كأن التوقعات متصلة — والملء في
    // الواجهة ترقيع لما يستطيع الاستعلام فعله صحيحاً.
    //
    // اليوم محسوب بتوقيت الرياض لا UTC: توقّع الساعة 2 فجراً
    // بالرياض يقع في اليوم السابق بتوقيت UTC، فتظهر أعمدة الرسم
    // مزاحة يوماً عن إحساس الأدمن بـ"أمس". (نفس سبب التحويل في
    // fixtureRepo.findByDate.)
    db.query(`
      SELECT to_char(d.day, 'YYYY-MM-DD') AS day,
             COUNT(p.id)::int             AS count
      FROM generate_series(
             (now() AT TIME ZONE 'Asia/Riyadh')::date - 13,
             (now() AT TIME ZONE 'Asia/Riyadh')::date,
             interval '1 day'
           ) AS d(day)
      LEFT JOIN predictions p
        ON (p.created_at AT TIME ZONE 'Asia/Riyadh')::date = d.day::date
      GROUP BY d.day
      ORDER BY d.day
    `),

    // 3) توزيع النقاط على التوقعات المحتسبة — يُظهر للأدمن كيف
    // تعمل إعدادات النقاط فعلياً (هل التوقع الدقيق نادر فعلاً؟).
    db.query(`
      -- بالنقاط الأساسية (points / multiplier): السؤال هنا "هل
      -- التوقّع الدقيق نادر فعلاً؟"، والمضاعِف يخلط الجواب — يشقّ
      -- كل صنف إلى صفّين، ويجعل اتجاهاً مضاعَفاً يساوي نتيجة
      -- مضبوطة مفردة فيُعدّ معها.
      SELECT (points / multiplier) AS points, COUNT(*)::int AS count
      FROM predictions
      WHERE settled_at IS NOT NULL AND points IS NOT NULL
      GROUP BY 1
      ORDER BY 1
    `),

    // 4) أفضل خمسة. JOIN وليس LEFT JOIN هنا: قائمة "الأفضل" لا
    // معنى فيها لمستخدم بلا توقعات محتسبة أصلاً.
    db.query(`
      SELECT u.id AS user_id,
             COALESCE(u.display_name, 'مشجع') AS display_name,
             COALESCE(SUM(p.points), 0)::int  AS total_points,
             COUNT(p.points)::int             AS settled_predictions
      FROM users u
      JOIN predictions p ON p.user_id = u.id AND p.settled_at IS NOT NULL
      GROUP BY u.id
      ORDER BY total_points DESC, settled_predictions ASC
      LIMIT 5
    `),

    // 5) المباريات موزعة على الدوريات.
    // LEFT JOIN على leagues: مباريات بـ league_id لا يقابله صف في
    // جدول الدوريات (بقايا إعداد قديم) يجب أن تظهر لا أن تختفي —
    // اختفاؤها يجعل مجموع الجدول أقل من العدّاد أعلاه بلا تفسير.
    db.query(`
      SELECT f.league_id,
             COALESCE(l.name_ar, l.name_en, 'دوري ' || f.league_id) AS name,
             (COUNT(*) FILTER (WHERE f.status = 'scheduled'))::int  AS scheduled,
             (COUNT(*) FILTER (WHERE f.status = 'live'))::int       AS live,
             (COUNT(*) FILTER (WHERE f.status = 'finished'))::int   AS finished
      FROM fixtures f
      LEFT JOIN leagues l ON l.id = f.league_id
      GROUP BY f.league_id, l.name_ar, l.name_en, l.sort_order
      ORDER BY l.sort_order NULLS LAST, f.league_id
    `),
  ]);

  res.json({
    ...counters.rows[0],
    predictions_daily: daily.rows,
    points_distribution: distribution.rows,
    top_users: topUsers.rows,
    fixtures_by_league: byLeague.rows,
    api_requests_today: await rateLimiter.usedToday(),
    api_daily_limit: rateLimiter.DAILY_LIMIT,
  });
});

// POST /api/admin/sync — مزامنة يدوية فورية من المزود.
// تكلفتها حتى طلبين من الحصة (أقل مع الكاش) — الرقم ظاهر في اللوحة.
router.post('/sync', async (req, res) => {
  const result = await syncAll();
  res.json(result);
});

// ---------------------------------------------------------------
// الدوريات
// ---------------------------------------------------------------

// GET /api/admin/leagues — كل الدوريات مع حجمها عندنا
router.get('/leagues', async (req, res) => {
  const leagues = await leagueRepo.findAll();
  res.json({ leagues });
});

// GET /api/admin/leagues/search?q=saudi — البحث عن دوري عند المزود.
//
// مسجّل قبل مسارات /leagues/:id عمداً: Express يطابق بالترتيب،
// ولو سبقه مسار GET بمعامل لالتقط "search" كأنه معرّف دوري.
//
// تحذير تكلفة: هذا المسار الوحيد في اللوحة الذي يستهلك من حصة
// المزود (طلب واحد لكل كلمة بحث جديدة، وصفر لو تكررت خلال 24
// ساعة بفضل الكاش). لذلك نرجع حالة الحصة في نفس الرد — الأدمن
// يرى ثمن بحثه فوراً بدل أن يكتشف نفادها وقت المزامنة.
router.get('/leagues/search', async (req, res) => {
  const q = String(req.query.q || '').trim();
  // المزود يرفض بحثاً أقصر من ثلاثة أحرف. نفحص قبل الإرسال حتى لا
  // يُهدر طلب من الحصة على رد نعرف مسبقاً أنه خطأ.
  if (q.length < 3) {
    return res.status(400).json({ error: 'كلمة البحث يجب أن تكون ٣ أحرف فأكثر' });
  }

  const raw = await footballProvider.searchLeagues(q);

  // نسطّح استجابة المزود لما تحتاجه اللوحة فقط: المعرّف والاسم
  // والشعار والمواسم المتاحة — الأدمن ينسخ منها id و season إلى
  // نموذج الإضافة. لا mapper منفصل لأن النتيجة لا تُخزَّن في
  // القاعدة إطلاقاً (عرض عابر لمساعدة الأدمن).
  const leagues = (raw ?? []).map((item) => ({
    id: item.league?.id,
    name_en: item.league?.name,
    type: item.league?.type,
    logo_url: item.league?.logo ?? null,
    country: item.country?.name ?? null,
    seasons: (item.seasons ?? []).map((s) => s.year),
  }));

  res.json({
    leagues,
    api_requests_today: await rateLimiter.usedToday(),
    api_daily_limit: rateLimiter.DAILY_LIMIT,
  });
});

// POST /api/admin/leagues — { id, name_en, name_ar?, country?, logo_url?, season }
router.post('/leagues', async (req, res) => {
  const { id, name_en, name_ar, country, logo_url, season, sort_order } = req.body || {};

  // المعرّف يأتي من المزود ولا نولّده نحن (انظر 007_leagues.sql)،
  // لذلك هو مُدخل يجب التحقق منه كبقية الحقول.
  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ error: 'معرّف الدوري يجب أن يكون عدداً صحيحاً موجباً' });
  }
  if (!Number.isInteger(season)) {
    return res.status(400).json({ error: 'الموسم يجب أن يكون عدداً صحيحاً' });
  }
  const nameEn = typeof name_en === 'string' ? name_en.trim() : '';
  if (!nameEn) {
    return res.status(400).json({ error: 'الاسم الإنجليزي مطلوب' });
  }

  // الفحص قبل الإدخال يعطي رسالة عربية مفهومة بدل خطأ 500 قادم
  // من انتهاك المفتاح الأساسي في PostgreSQL.
  if (await leagueRepo.findById(id)) {
    return res.status(409).json({ error: 'هذا الدوري مضاف مسبقاً' });
  }

  const league = await leagueRepo.create({
    id,
    name_en: nameEn,
    name_ar: typeof name_ar === 'string' && name_ar.trim() ? name_ar.trim() : null,
    country: typeof country === 'string' && country.trim() ? country.trim() : null,
    logo_url: typeof logo_url === 'string' && logo_url.trim() ? logo_url.trim() : null,
    season,
    sort_order: Number.isInteger(sort_order) ? sort_order : null,
  });
  res.status(201).json({ league });
});

// PUT /api/admin/leagues/:id — تحديث جزئي: { name_ar?, season?, enabled?, sort_order? }
router.put('/leagues/:id', async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) {
    return res.status(400).json({ error: 'معرّف الدوري غير صالح' });
  }

  const { name_ar, season, enabled, sort_order } = req.body || {};
  // نبني كائن التعديل بأنفسنا من الحقول الأربعة المسموحة فقط —
  // نفس منطق إعدادات النقاط: حقول إضافية في الجسم لا تتسرب للقاعدة.
  const fields = {};

  if (name_ar !== undefined) {
    if (typeof name_ar !== 'string') {
      return res.status(400).json({ error: 'الاسم العربي يجب أن يكون نصاً' });
    }
    // نص فارغ يعني "امسح الترجمة" (نفس سلوك ترجمة الفرق).
    const trimmed = name_ar.trim();
    if (trimmed.length > 100) {
      return res.status(400).json({ error: 'الاسم أطول من المسموح' });
    }
    fields.name_ar = trimmed || null;
  }
  if (season !== undefined) {
    if (!Number.isInteger(season)) {
      return res.status(400).json({ error: 'الموسم يجب أن يكون عدداً صحيحاً' });
    }
    fields.season = season;
  }
  if (enabled !== undefined) {
    if (typeof enabled !== 'boolean') {
      return res.status(400).json({ error: 'التفعيل يجب أن يكون true أو false' });
    }
    fields.enabled = enabled;
  }
  if (sort_order !== undefined) {
    if (!Number.isInteger(sort_order)) {
      return res.status(400).json({ error: 'ترتيب العرض يجب أن يكون عدداً صحيحاً' });
    }
    fields.sort_order = sort_order;
  }

  const league = await leagueRepo.update(id, fields);
  if (!league) return res.status(404).json({ error: 'الدوري غير موجود' });
  res.json({ league });
});

// DELETE /api/admin/leagues/:id
router.delete('/leagues/:id', async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) {
    return res.status(400).json({ error: 'معرّف الدوري غير صالح' });
  }

  const league = await leagueRepo.findById(id);
  if (!league) return res.status(404).json({ error: 'الدوري غير موجود' });

  // لماذا نرفض الحذف بدل حذف المباريات معه؟
  // لا يوجد مفتاح أجنبي بين fixtures.league_id و leagues.id (العمود
  // سبق الجدول)، فالقاعدة لن تمنع شيئاً: الحذف ينجح وتبقى مئات
  // المباريات تشير إلى دوري لا وجود له — تختفي من فلاتر اللوحة
  // ومن المزامنة وتظل في التطبيق بلا اسم. والحذف المتتالي أسوأ:
  // يجرّ معه توقعات المستخدمين ونقاطهم (CASCADE من fixtures).
  // الإيقاف (enabled = false) يحقق مقصد الأدمن الحقيقي — إخراج
  // الدوري من التداول — بلا فقد بيانات، وهو قابل للتراجع.
  const fixturesCount = await leagueRepo.fixturesCount(id);
  if (fixturesCount > 0) {
    return res.status(409).json({
      error: `لا يمكن حذف الدوري لأن لديه ${fixturesCount} مباراة مخزّنة. عطّله بدل حذفه.`,
    });
  }

  await leagueRepo.remove(id);
  res.status(204).end();
});

// POST /api/admin/leagues/:id/sync — مزامنة دوري واحد.
// تكلفتها طلبان من الحصة (فرق + مباريات)، وأقل مع الكاش.
router.post('/leagues/:id/sync', async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) {
    return res.status(400).json({ error: 'معرّف الدوري غير صالح' });
  }

  const league = await leagueRepo.findById(id);
  if (!league) return res.status(404).json({ error: 'الدوري غير موجود' });

  // المزامنة اليدوية تعمل حتى على دوري موقوف: الأدمن قد يريد جلب
  // بياناته ومعاينتها قبل أن يفعّله للمستخدمين.
  const result = await syncLeague(league);
  res.json(result);
});

// GET /api/admin/standings?league=&season=
// الترتيب لأي دوري. بلا بارامترات: الدوري الأول من المفعّلة.
// تكلفتها طلب واحد من الحصة، وصفر لو كان الترتيب في الكاش (ساعة).
router.get('/standings', async (req, res) => {
  let leagueId = req.query.league !== undefined && String(req.query.league) !== ''
    ? Number(req.query.league)
    : undefined;
  let season = req.query.season !== undefined && String(req.query.season) !== ''
    ? Number(req.query.season)
    : undefined;

  if (leagueId !== undefined && !Number.isInteger(leagueId)) {
    return res.status(400).json({ error: 'معرّف الدوري غير صالح' });
  }
  if (season !== undefined && !Number.isInteger(season)) {
    return res.status(400).json({ error: 'الموسم غير صالح' });
  }

  if (leagueId === undefined) {
    // الافتراضي: أول دوري مفعّل (حسب sort_order) — وهو ما يعتبره
    // الأدمن "الدوري الرئيسي". لو لم يكن هناك أي دوري مفعّل نترك
    // القرار لقيم .env داخل المزود بدل الرد بخطأ.
    const [first] = await leagueRepo.findEnabled();
    if (first) {
      leagueId = first.id;
      // الموسم يتبع الدوري تلقائياً ما لم يطلب الأدمن موسماً بعينه:
      // كل دوري له موسمه المتاح في الباقة المجانية.
      season = season ?? first.season;
    }
  } else if (season === undefined) {
    const league = await leagueRepo.findById(leagueId);
    if (!league) return res.status(404).json({ error: 'الدوري غير موجود' });
    season = league.season;
  }

  const standings = await standingsService.getStandings({ leagueId, season });
  res.json({
    league_id: leagueId ?? null,
    season: season ?? null,
    standings,
    api_requests_today: await rateLimiter.usedToday(),
    api_daily_limit: rateLimiter.DAILY_LIMIT,
  });
});

// GET /api/admin/teams — الفرق بأسمائها الخام (للترجمة)
router.get('/teams', async (req, res) => {
  const teams = await teamRepo.findAll();
  res.json({ teams });
});

// PUT /api/admin/teams/:id — { name_ar } — نص فارغ يعني مسح الترجمة
router.put('/teams/:id', async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) {
    return res.status(400).json({ error: 'معرّف الفريق غير صالح' });
  }
  let { name_ar } = req.body || {};
  name_ar = typeof name_ar === 'string' ? name_ar.trim() : '';
  if (name_ar.length > 100) {
    return res.status(400).json({ error: 'الاسم أطول من المسموح' });
  }

  const updated = await teamRepo.updateNameAr(id, name_ar || null);
  if (!updated) return res.status(404).json({ error: 'الفريق غير موجود' });
  res.json({ id, name_ar: name_ar || null });
});

// GET /api/admin/fixtures?status=all|scheduled|live|finished&league=307
// قائمة المباريات مع عدد التوقعات على كل واحدة.
router.get('/fixtures', async (req, res) => {
  const status = String(req.query.status || 'all');
  if (!['all', 'scheduled', 'live', 'finished', 'postponed', 'cancelled'].includes(status)) {
    return res.status(400).json({ error: 'حالة غير معروفة' });
  }

  // league اختياري: غيابه يعني كل الدوريات. نمرره كـ NULL بدل بناء
  // WHERE مختلف، والشرط ($2::int IS NULL OR ...) يلغي نفسه حينها.
  let league = null;
  if (req.query.league !== undefined && String(req.query.league) !== '') {
    league = Number(req.query.league);
    if (!Number.isInteger(league)) {
      return res.status(400).json({ error: 'معرّف الدوري غير صالح' });
    }
  }

  // ترتيب حسب السياق: القادمة تصاعدياً (الأقرب أولاً) لأن الأدمن
  // يريد "ما التالي؟"، والمنتهية تنازلياً لأنه يريد "آخر النتائج".
  const order = status === 'scheduled' ? 'ASC' : 'DESC';

  const { rows } = await db.query(
    `SELECT f.id, f.league_id, f.round, f.status, f.kickoff_at, f.goals_home, f.goals_away,
            COALESCE(ht.name_ar, ht.name_en) AS home_team_name, ht.logo_url AS home_team_logo,
            COALESCE(at.name_ar, at.name_en) AS away_team_name, at.logo_url AS away_team_logo,
            COUNT(p.id)::int AS predictions_count
     FROM fixtures f
     JOIN teams ht ON ht.id = f.home_team_id
     JOIN teams at ON at.id = f.away_team_id
     LEFT JOIN predictions p ON p.fixture_id = f.id
     WHERE ($1 = 'all' OR f.status = $1)
       AND ($2::int IS NULL OR f.league_id = $2)
     GROUP BY f.id, ht.id, at.id
     ORDER BY f.kickoff_at ${order}
     LIMIT 100`,
    [status, league]
  );
  res.json({ fixtures: rows });
});

// GET /api/admin/groups?search= — إشراف على القروبات
router.get('/groups', async (req, res) => {
  const groupRepo = require('../repositories/groupRepo');
  const groups = await groupRepo.adminList(String(req.query.search || '').trim());
  res.json({ groups });
});

// DELETE /api/admin/groups/:id — حذف قروب (إشراف: اسم مسيء مثلاً)
router.delete('/groups/:id', async (req, res) => {
  const groupRepo = require('../repositories/groupRepo');
  const removed = await groupRepo.remove(req.params.id).catch(() => false);
  if (!removed) return res.status(404).json({ error: 'القروب غير موجود' });
  res.status(204).end();
});

// ---------------------------------------------------------------
// التاج الذهبي — المشتريات والمنح
// ---------------------------------------------------------------

// GET /api/admin/purchases — آخر المشتريات
router.get('/purchases', async (req, res) => {
  const purchaseRepo = require('../repositories/purchaseRepo');
  res.json({ purchases: await purchaseRepo.adminList() });
});

// POST /api/admin/users/:id/crown — { months? } منح التاج يدوياً.
//
// هذا هو الباب الوحيد للمنح بلا إيصال، وهو خلف requireAdmin عمداً:
// دعمٌ فني (اشترى ولم يصله)، وتجربةٌ على جهاز حقيقي قبل تفعيل
// المشتريات، وهدية لمن يستحقها. أي باب آخر بلا إيصال يعني تاجاً
// مجانياً لمن يعرف كتابة curl.
router.post('/users/:id/crown', async (req, res) => {
  if (!UUID_RE.test(req.params.id)) {
    return res.status(400).json({ error: 'معرّف غير صالح' });
  }
  const premiumService = require('../services/premiumService');
  const months = Number(req.body?.months ?? 1);
  if (!Number.isInteger(months) || months < 1 || months > 24) {
    return res.status(400).json({ error: 'عدد الأشهر بين 1 و24' });
  }
  const { entitlements } = await premiumService.grant({
    userId: req.params.id, kind: 'crown', quantity: months, platform: 'manual',
  });
  res.json({ entitlements });
});

// DELETE /api/admin/users/:id/crown — إلغاء فوري.
//
// لا يمحو الدفتر: المشتريات سجلٌّ لما حدث، ومحوُها يفقدنا القدرة
// على الإجابة عن "هل دفع؟" بعد شهر. الإلغاء يمسّ الصلاحية وحدها.
router.delete('/users/:id/crown', async (req, res) => {
  if (!UUID_RE.test(req.params.id)) {
    return res.status(400).json({ error: 'معرّف غير صالح' });
  }
  await userRepo.clearPremium(req.params.id);
  res.status(204).end();
});

// ---------------------------------------------------------------
// المستخدمون
// ---------------------------------------------------------------

// معرّفات المستخدمين UUID (انظر 002_auth.sql). نفحص الشكل قبل أن
// يصل للقاعدة: بدونه يرمي PostgreSQL خطأ نوع (22P02) فيتحول معرّف
// مكتوب بخطأ إلى 500 "خطأ داخلي" بدل 400 مفهوم.
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// GET /api/admin/users?search=
router.get('/users', async (req, res) => {
  const users = await userRepo.adminList(String(req.query.search || '').trim());
  res.json({ users });
});

// GET /api/admin/users/:id — كل ما يخص مستخدماً واحداً في طلب واحد:
// ملفه، دوره، حالة إيقافه، إحصاءاته، قروباته، وآخر توقعاته.
router.get('/users/:id', async (req, res) => {
  const { id } = req.params;
  if (!UUID_RE.test(id)) {
    return res.status(400).json({ error: 'معرّف المستخدم غير صالح' });
  }

  const user = await userRepo.adminDetail(id);
  if (!user) return res.status(404).json({ error: 'المستخدم غير موجود' });
  res.json({ user });
});

// PUT /api/admin/users/:id/suspend — { suspended: boolean, reason?: string }
router.put('/users/:id/suspend', async (req, res) => {
  const { id } = req.params;
  const { suspended, reason } = req.body || {};

  if (!UUID_RE.test(id)) {
    return res.status(400).json({ error: 'معرّف المستخدم غير صالح' });
  }
  if (typeof suspended !== 'boolean') {
    return res.status(400).json({ error: 'الحقل suspended يجب أن يكون true أو false' });
  }

  // نفس منطق حارس الدور أعلاه: إيقاف نفسك يقفل الباب عليك من الداخل
  // فوراً — requireAuth يرفض طلبك التالي، ولا أحد يستطيع رفع الإيقاف
  // إلا أدمن آخر أو تدخّل مباشر في القاعدة.
  if (id === req.userId && suspended) {
    return res.status(400).json({ error: 'لا يمكنك إيقاف حسابك بنفسك' });
  }

  let cleanReason = null;
  if (suspended && reason !== undefined && reason !== null) {
    if (typeof reason !== 'string') {
      return res.status(400).json({ error: 'السبب يجب أن يكون نصاً' });
    }
    cleanReason = reason.trim().slice(0, 300) || null;
  }

  const user = await userRepo.setSuspension(id, {
    suspendedAt: suspended ? new Date() : null,
    reason: cleanReason,
  });
  if (!user) return res.status(404).json({ error: 'المستخدم غير موجود' });

  if (suspended) {
    // إبطال توكنات التجديد فوراً. بدونه يبقى جهاز الموقوف حاملاً
    // توكن تجديد صالحاً ثلاثين يوماً: صحيح أن authService.refresh
    // يفحص الإيقاف ويرفض، لكن ترك جلسات حية لحساب موقوف يعني أن رفع
    // الإيقاف يعيد كل أجهزته القديمة للعمل صامتةً — والأصح أن يعود
    // بتسجيل دخول واعٍ. الإبطال هنا يجعل حالة القاعدة تطابق القرار.
    await refreshTokenRepo.revokeAllForUser(id);
  }

  res.json({ user });
});

// DELETE /api/admin/users/:id — حذف نهائي (لا تراجع).
router.delete('/users/:id', async (req, res) => {
  const { id } = req.params;
  if (!UUID_RE.test(id)) {
    return res.status(400).json({ error: 'معرّف المستخدم غير صالح' });
  }
  // الحذف أخطر من الإيقاف: لا تراجع فيه. نمنع حذف النفس مبكراً هنا
  // (قبل فتح المعاملة) لأنه خطأ إدخال بشري لا حالة سباق.
  if (id === req.userId) {
    return res.status(400).json({ error: 'لا يمكنك حذف حسابك بنفسك' });
  }

  // بقية الحراسة (المستخدم موجود؟ آخر أدمن؟) داخل معاملة الـ repo:
  // فحصها هنا يترك فجوة بين الفحص والحذف. انظر شرح
  // userRepo.removeWithGroupHandover.
  const result = await userRepo.removeWithGroupHandover(id);
  if (!result.ok) {
    if (result.reason === 'not_found') {
      return res.status(404).json({ error: 'المستخدم غير موجود' });
    }
    return res.status(400).json({ error: 'لا يمكن حذف آخر أدمن في النظام' });
  }

  // حذف الصورة بعد نجاح المعاملة لا قبلها: الملف على القرص خارج
  // نطاق ROLLBACK، فلو فشل الحذف في القاعدة بعده لبقي مستخدم بصورة
  // مفقودة. الترتيب الحالي أسوأ حالاته ملف يتيم في uploads — مزعج،
  // لا مدمّر.
  await deleteAvatarFile(result.avatar_url);

  // 200 لا 204: للأدمن حق أن يرى ما جرّه الحذف معه فعلاً — كم توقعاً
  // اختفى، وأي قروب حُذف وأيها انتقلت ملكيته لعضو آخر.
  res.json({
    deleted: result.deleted,
    deleted_groups: result.deleted_groups,
    transferred_groups: result.transferred_groups,
  });
});

// DELETE /api/admin/users/:id/avatar — إزالة صورة مسيئة.
// إشرافياً هذا أخف عقوبة ممكنة: يبقى الحساب والنقاط والقروبات.
router.delete('/users/:id/avatar', async (req, res) => {
  const { id } = req.params;
  if (!UUID_RE.test(id)) {
    return res.status(400).json({ error: 'معرّف المستخدم غير صالح' });
  }

  const before = await userRepo.findById(id);
  if (!before) return res.status(404).json({ error: 'المستخدم غير موجود' });

  // نفرّغ العمود أولاً ثم نحذف الملف: بالترتيب المعاكس قد يُحذف
  // الملف وتفشل الكتابة، فيبقى الصف يشير إلى صورة مسيئة غير موجودة
  // (رابط مكسور، والصورة نفسها ما زالت في الكاش عند من حمّلها).
  await userRepo.updateProfile(id, { avatarUrl: null });
  await deleteAvatarFile(before.avatar_url);

  res.status(204).end();
});

// PUT /api/admin/users/:id/role — { role: 'user' | 'admin' }
router.put('/users/:id/role', async (req, res) => {
  const { id } = req.params;
  const { role } = req.body || {};

  if (role !== 'user' && role !== 'admin') {
    return res.status(400).json({ error: 'الدور يجب أن يكون user أو admin' });
  }
  // حماية من إقفال الباب على نفسك: آخر أدمن لا يستطيع تنزيل نفسه —
  // وإلا صارت اللوحة بلا أي مدير والحل الوحيد الطرفية.
  if (id === req.userId && role === 'user') {
    return res.status(400).json({ error: 'لا يمكنك إزالة صلاحيتك عن نفسك' });
  }

  const updated = await userRepo.updateRole(id, role);
  if (!updated) return res.status(404).json({ error: 'المستخدم غير موجود' });
  res.json({ id, role });
});

// GET /api/admin/settings/scoring — قيم النقاط الحالية
router.get('/settings/scoring', async (req, res) => {
  const scoring = (await settingsRepo.get('scoring')) ?? scoringService.DEFAULT_SCORING;
  res.json({ scoring });
});

// PUT /api/admin/settings/scoring — { exact, diff, outcome }
router.put('/settings/scoring', async (req, res) => {
  const { exact, diff, outcome } = req.body || {};

  // تحقق صارم: أعداد صحيحة 0-100. نبني الكائن الجديد بأنفسنا من
  // الحقول الثلاثة فقط — لو أرسل أحدهم حقولاً إضافية لا تتسرب
  // للإعدادات المخزنة.
  for (const [name, v] of [['exact', exact], ['diff', diff], ['outcome', outcome]]) {
    // السقف 1000 لا 100: المقياس صار 100/75/50، وسقفٌ يساوي أعلى
    // قيمة معمول بها يمنع رفعها ولو نقطة واحدة.
    if (!Number.isInteger(v) || v < 0 || v > 1000) {
      return res.status(400).json({ error: `${name} يجب أن يكون عدداً صحيحاً بين 0 و 1000` });
    }
  }
  // فحص منطقي: الأدق يستحق أكثر. نمنع إعدادات مقلوبة تفسد عدالة
  // اللعبة بخطأ إدخال (outcome أعلى من exact مثلاً).
  if (!(exact >= diff && diff >= outcome)) {
    return res.status(400).json({ error: 'يجب أن يكون exact ≥ diff ≥ outcome' });
  }

  const scoring = { exact, diff, outcome };
  await settingsRepo.set('scoring', scoring);
  res.json({ scoring });
});

// ---------------------------------------------------------------
// محتوى الموقع العام: الصفحات، الإعدادات، صندوق الرسائل
// ---------------------------------------------------------------

// GET /api/admin/site/pages — فهرس الصفحات (بلا نصوصها)
router.get('/site/pages', async (req, res) => {
  const pages = await siteRepo.listPages();
  res.json({ pages });
});

// GET /api/admin/site/pages/:slug — نص الصفحة للتحرير.
//
// نرجع body الخام فقط بلا body_html: هذا مسار المحرّر، وما يوضع
// في مربع النص هو المصدر لا الناتج. (الموقع العام هو من يحتاج
// المُصيَّر، وهو يطلبه من /api/site/pages/:slug.)
router.get('/site/pages/:slug', async (req, res) => {
  const page = await siteRepo.getPage(String(req.params.slug));
  if (!page) return res.status(404).json({ error: 'الصفحة غير موجودة' });
  res.json({ page });
});

// PUT /api/admin/site/pages/:slug — { title, body }
//
// تعديل فقط، بلا إنشاء: الصفحات مجموعة مغلقة يعرفها الموقع
// بمساراتها الثابتة، وصفحة جديدة في القاعدة لا يوجد ما يعرضها.
// إضافة slug جديد قرار يمر بهجرة وبتعديل الموقع معاً.
router.put('/site/pages/:slug', async (req, res) => {
  const { title, body } = req.body || {};

  const cleanTitle = typeof title === 'string' ? title.trim() : '';
  // body لا يُقصّ بـ trim كاملاً: المسافات في بداية السطور جزء من
  // بنية Markdown. نكتفي بفحص أنه ليس فارغاً.
  const cleanBody = typeof body === 'string' ? body : '';

  if (!cleanTitle) {
    return res.status(400).json({ error: 'عنوان الصفحة مطلوب' });
  }
  if (cleanTitle.length > 120) {
    return res.status(400).json({ error: 'العنوان أطول من المسموح' });
  }
  if (!cleanBody.trim()) {
    return res.status(400).json({ error: 'محتوى الصفحة مطلوب' });
  }
  // 100 ألف حرف: أطول بكثير من أي سياسة خصوصية، وقصير بما يكفي
  // ليمنع لصق ملف كامل في المحرّر بالخطأ.
  if (cleanBody.length > 100000) {
    return res.status(400).json({ error: 'المحتوى أطول من المسموح' });
  }

  const page = await siteRepo.updatePage(String(req.params.slug), {
    title: cleanTitle,
    body: cleanBody,
  });
  if (!page) return res.status(404).json({ error: 'الصفحة غير موجودة' });
  res.json({ page });
});

// GET /api/admin/site/settings
router.get('/site/settings', async (req, res) => {
  const settings = await siteSettings.get();
  res.json({ settings });
});

// PUT /api/admin/site/settings — الشكل في services/siteSettings.js
router.put('/site/settings', async (req, res) => {
  const result = await siteSettings.update(req.body);
  if (result.error) return res.status(400).json({ error: result.error });
  res.json({ settings: result.value });
});

// GET /api/admin/site/messages?unread=1
router.get('/site/messages', async (req, res) => {
  const unreadOnly = String(req.query.unread || '') === '1';
  const messages = await siteRepo.listMessages({ unreadOnly });
  // العدّاد مع القائمة: اللوحة تحدّث الشارة بعد كل قراءة أو حذف
  // بلا طلب ثانٍ لـ /stats.
  res.json({ messages, unread: await siteRepo.countUnread() });
});

// معرّفات الرسائل BIGSERIAL. نفحص الشكل قبل القاعدة لنفس سبب
// UUID_RE أعلاه: معرّف غير رقمي يرمي خطأ نوع من PostgreSQL
// فيظهر 500 "خطأ داخلي" بدل 400 مفهوم.
const BIGINT_RE = /^[0-9]{1,18}$/;

// PUT /api/admin/site/messages/:id/read
router.put('/site/messages/:id/read', async (req, res) => {
  if (!BIGINT_RE.test(req.params.id)) {
    return res.status(400).json({ error: 'معرّف الرسالة غير صالح' });
  }
  const message = await siteRepo.markRead(req.params.id);
  if (!message) return res.status(404).json({ error: 'الرسالة غير موجودة' });
  res.json({ message, unread: await siteRepo.countUnread() });
});

// DELETE /api/admin/site/messages/:id — حذف نهائي.
// لا "سلة محذوفات": الرسائل تصل من نموذج عام، ومعظم ما يُحذف منها
// إغراق — أرشفته تعني الاحتفاظ بالنفاية إلى الأبد.
router.delete('/site/messages/:id', async (req, res) => {
  if (!BIGINT_RE.test(req.params.id)) {
    return res.status(400).json({ error: 'معرّف الرسالة غير صالح' });
  }
  const removed = await siteRepo.deleteMessage(req.params.id);
  if (!removed) return res.status(404).json({ error: 'الرسالة غير موجودة' });
  res.status(204).end();
});

// POST /api/admin/settle — تشغيل الاحتساب يدوياً الآن.
// الاحتساب يعمل تلقائياً بعد كل مزامنة، لكن زر "احسب الآن" في
// اللوحة مفيد بعد تعديل النقاط أو لتصحيح وضع طارئ.
router.post('/settle', async (req, res) => {
  const settled = await scoringService.settleFinished();
  res.json({ settled });
});

module.exports = router;
