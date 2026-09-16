// routes/fantasy — «فريقي»: السوق والتشكيلة والجولة والعرش.
//
// كله خلف requireAuth: التشكيلة ملكُ صاحبها، والسوق نفسه يعرض
// أسعاراً تخصّ لعبةً لا يدخلها ضيف. والعرش وحده كان يمكن أن يكون
// عاماً، لكنه يُقرأ من داخل التبويب فلا فائدة من فتحه.
//
// والقواعد كلها في fantasySquadService: هذا المسار يفهم HTTP
// ويحوّل أخطاء القواعد إلى 400 برسالتها العربية كما هي.
const express = require('express');
const requireAuth = require('../middleware/requireAuth');
const leagueRepo = require('../repositories/leagueRepo');
const championRepo = require('../repositories/championRepo');
const fixtureRepo = require('../repositories/fixtureRepo');
const fantasyRepo = require('../repositories/fantasyRepo');
const squadService = require('../services/fantasySquadService');
const db = require('../config/db');
const logger = require('../utils/logger');

const router = express.Router();
router.use(requireAuth);

/**
 * الدوري المقصود: المطلوب إن كان يتابعه، وإلا أول متابعاته.
 *
 * نفس حارس routes/round: التشكيلة تُبنى من لاعبي دوريٍّ يتابعه،
 * ومن لا يتابع شيئاً لا تشكيلة له — والجواب دعوةٌ للمتابعة لا
 * قائمةٌ فارغة لا تشرح نفسها.
 */
async function resolveLeague(req) {
  const followed = await championRepo.followedIds(req.userId);
  const leagues = (await leagueRepo.findEnabled()).filter(
    (l) => l.in_app && followed.includes(l.id)
  );
  if (!leagues.length) return null;
  const asked = Number(req.query.league || req.body?.league);
  return leagues.find((l) => l.id === asked) || leagues[0];
}

const FOLLOW_REQUIRED = { follow_required: true, league: null, squad: null };

/**
 * الجولة المفتوحة للتعديل الآن، ونصف الموسم الذي تقع فيه.
 *
 * النصف يُحسب من ترتيب الجولة في الموسم لا من التاريخ: المواسم
 * تختلف أطوالاً وتتأجّل جولاتٌ، و«منتصف الموسم» بالتقويم قد يقع
 * في الجولة الثامنة أو العشرين.
 */
async function openRoundOf(league) {
  const rounds = await fixtureRepo.roundsFor(league.id, league.season);
  if (!rounds.length) return { round: null, half: 1, rounds: [] };
  const index = rounds.findIndex((r) => r.open > 0);
  const at = index === -1 ? rounds.length - 1 : index;
  return {
    round: rounds[at].round,
    half: at < rounds.length / 2 ? 1 : 2,
    rounds,
  };
}

// GET /api/fantasy/setup — ما يحتاجه أول دخول: دورياتي وأنديتها
//
// شاشة التهيئة تسأل سؤالين متتاليين (أي دوري؟ ثم أي نادٍ؟)،
// وطلبان متتاليان يعنيان دوّارتين على شبكة بطيئة. وهذا طلبٌ
// واحد: الدوريات كلها، وأندية المطلوب منها.
//
// وكل دوري يحمل `has_squad`: اللاعب قد يتابع الإسباني والسعودي،
// وله في كلٍّ منهما تشكيلة مستقلة — فالشاشة يجب أن تقول له أين
// بدأ وأين لم يبدأ بعد، لا أن تفتح على أوّلها وتصمت.
router.get('/setup', async (req, res) => {
  const followed = await championRepo.followedIds(req.userId);
  const leagues = (await leagueRepo.findEnabled()).filter(
    (l) => l.in_app && followed.includes(l.id)
  );
  if (!leagues.length) return res.json({ ...FOLLOW_REQUIRED, leagues: [], clubs: [] });

  const asked = Number(req.query.league);
  const league = leagues.find((l) => l.id === asked) || leagues[0];

  // «لك فريق هنا» للتشكيلات المبنيّة وحدها: من ثبّت ناديه ولم
  // يكمل الخمسة عشر له صفٌّ في الجدول (راجع setClub)، وعدُّه
  // بداية يقول للاعب إنه بدأ حيث لم يبدأ.
  const { rows: squads } = await db.query(
    `SELECT s.league_id FROM fantasy_squads s
      WHERE s.user_id = $1 AND s.season = ANY($2)
        AND EXISTS (SELECT 1 FROM fantasy_squad_players sp WHERE sp.squad_id = s.id)`,
    [req.userId, [...new Set(leagues.map((l) => l.season))]]
  );
  const started = new Set(squads.map((r) => r.league_id));

  // الأندية من مبارياتنا لا من جدول الفرق كله: جدول الفرق يحمل
  // أندية ثمانية دوريات، وقائمةٌ فيها ريال مدريد لمن يختار ناديه
  // السعودي دعوةٌ لخطأ يرفضه الخادم بعد ثلاث ضغطات.
  const { rows: clubs } = await db.query(
    `SELECT DISTINCT t.id, COALESCE(t.name_ar, t.name_en) AS name, t.logo_url
       FROM teams t
       JOIN (
         SELECT home_team_id AS team_id FROM fixtures
          WHERE league_id = $1 AND season = $2
         UNION
         SELECT away_team_id FROM fixtures
          WHERE league_id = $1 AND season = $2
       ) f ON f.team_id = t.id
      ORDER BY name`,
    [league.id, league.season]
  );

  // النادي المثبَّت في هذا الدوري إن وُجد: لا يتغيّر بعد اختياره،
  // فالشاشة يجب أن تعرضه مقفلاً بدل أن تعرض شبكةً تدعو إلى اختيارٍ
  // يرفضه الخادم.
  const mine = await fantasyRepo.findSquad(req.userId, league.id, league.season);

  res.json({
    leagues: leagues.map((l) => ({
      id: l.id,
      name: l.name_ar || l.name_en,
      logo_url: `/logos/league-${l.id}.png`,
      has_squad: started.has(l.id),
    })),
    league: { id: league.id, name: league.name_ar || league.name_en },
    club: mine?.club_team_id || null,
    clubs,
    rules: squadService.RULES,
  });
});

// GET /api/fantasy/market — سوق اللاعبين
router.get('/market', async (req, res) => {
  const league = await resolveLeague(req);
  if (!league) return res.json({ ...FOLLOW_REQUIRED, players: [] });

  const players = await fantasyRepo.market(league.id, league.season, {
    position: ['Goalkeeper', 'Defender', 'Midfielder', 'Attacker']
      .includes(req.query.position) ? req.query.position : null,
    teamId: /^\d+$/.test(req.query.team) ? Number(req.query.team) : null,
    search: String(req.query.q || '').trim() || null,
  });

  res.json({
    league: { id: league.id, name: league.name, logo_url: `/logos/league-${league.id}.png` },
    rules: squadService.RULES,
    formations: Object.keys(squadService.FORMATIONS),
    quota: squadService.SQUAD_QUOTA,
    players,
  });
});

// GET /api/fantasy/squad — تشكيلتي
router.get('/squad', async (req, res) => {
  const league = await resolveLeague(req);
  if (!league) return res.json(FOLLOW_REQUIRED);

  const squad = await fantasyRepo.findSquad(req.userId, league.id, league.season);
  const { round: openRound, half } = await openRoundOf(league);

  let pending = null;
  if (squad) {
    const used = await fantasyRepo.transfersThisRound(squad.id, openRound);
    const chips = await fantasyRepo.chipsFor(squad.id);
    const wildcardNow = chips.some((c) => c.chip === 'wildcard' && c.round === openRound);
    pending = {
      round: openRound,
      used,
      free: squad.free_transfers,
      cost: wildcardNow ? 0 : Math.max(0, used - squad.free_transfers) * -4,
      wildcard_active: wildcardNow,
      // متاحة إن لم تُستعمل في هذا النصف.
      wildcard_available:
        !chips.some((c) => c.chip === 'wildcard' && c.half === half),
    };
  }

  res.json({
    league: { id: league.id, name: league.name },
    rules: squadService.RULES,
    formations: Object.keys(squadService.FORMATIONS),
    squad: squad && {
      id: squad.id,
      name: squad.name,
      club_team_id: squad.club_team_id,
      // اسم النادي وشعاره من الخادم لا من لاعبي التشكيلة: من ثبّت
      // ناديه ولم يشترِ بعد لا لاعب له يُستنبط منه الشعار، وشريط
      // «فريقي» عندها يظهر بلا هوية في أهمّ لحظة — أول دخول.
      club_name: squad.club_name,
      club_logo: squad.club_logo,
      formation: squad.formation,
      budget_left: Number(squad.budget_left),
      // قيمة اللاعبين بأسعار اليوم. مع المحفظة تعطي «قيمة فريقك»،
      // وهي المقياس الثاني في اللعبة بعد النقاط: من ينمو فريقه
      // يشتري ما لا يستطيعه غيره.
      squad_value: Number(squad.squad_value),
      free_transfers: squad.free_transfers,
      total_points: squad.total_points,
      players: await fantasyRepo.squadPlayers(squad.id),
    },
    // ما ستكلّفه انتقالاتُ هذا الأسبوع لو أُقفلت الجولة الآن.
    // يُعرض قبل الإقفال لا بعده: خصمٌ يُكتشف بعد وقوعه عقوبةٌ،
    // وخصمٌ يُرى قبله قرار.
    transfers: pending,
  });
});

// PUT /api/fantasy/club — تثبيت «فريقي» قبل بناء التشكيلة
//
// مسارٌ مستقلّ عن حفظ التشكيلة لأن القرارين مستقلان في الزمن:
// النادي يُختار في الثانية الأولى، والتشكيلة تكتمل بعد ربع ساعة
// من المفاضلة في السوق. وربطُ حفظ النادي بحفظ الخمسة عشر يعني أن
// كل من خرج في المنتصف يعود فلا يجد شيئاً — وهو ما كان يحدث.
router.put('/club', async (req, res) => {
  const league = await resolveLeague(req);
  if (!league) return res.status(400).json({ error: 'تابِع دورياً أولاً كي تبني تشكيلتك.' });

  const clubTeamId = Number(req.body?.club_team_id);
  if (!Number.isInteger(clubTeamId)) {
    return res.status(400).json({ error: 'اختر ناديك.' });
  }

  // ناديه من أندية هذا الدوري: قائمة الشاشة تُبنى من مبارياتنا،
  // ومعرّفٌ من خارجها يعني تشكيلةً لا يمكن أن تُبنى أصلاً —
  // ولاعباً يكتشف ذلك بعد خمسة عشر اختياراً.
  const { rows: inLeague } = await db.query(
    `SELECT 1 FROM fixtures
      WHERE league_id = $1 AND season = $2
        AND (home_team_id = $3 OR away_team_id = $3)
      LIMIT 1`,
    [league.id, league.season, clubTeamId]
  );
  if (!inLeague.length) {
    return res.status(400).json({ error: 'هذا النادي ليس من هذا الدوري.' });
  }

  // **والنادي لا يتغيّر بعد اختياره.** هذه قاعدة لعبة لا قيد
  // تقني: «فريقي» هوية لا إعداد، ومن يبدّل ناديه كل أسبوع يتبع
  // النجوم لا ناديه — فتذوب القاعدة التي تميّز اللعبة كلها
  // (ثلاثة من ناديك) وتصير قيداً شكلياً يُلتفّ عليه بضغطتين.
  //
  // والقيد في الخادم لا في الشاشة وحدها: زرٌّ مخفيٌّ ليس قاعدة.
  const current = await fantasyRepo.findSquad(req.userId, league.id, league.season);
  if (current?.club_team_id && current.club_team_id !== clubTeamId) {
    return res.status(400).json({
      error: `ناديك في هذا الدوري ${current.club_name || 'مختار'} — `
        + 'ولا يتغيّر هذا الموسم.',
    });
  }
  // نفس النادي مرة أخرى: ليس خطأً، ولا حاجة لكتابةٍ ثانية.
  if (current?.club_team_id === clubTeamId) {
    return res.json({
      league: { id: league.id, name: league.name_ar || league.name_en || league.name },
      club: { id: clubTeamId, name: current.club_name, logo_url: current.club_logo },
    });
  }

  await fantasyRepo.setClub({
    userId: req.userId,
    leagueId: league.id,
    season: league.season,
    clubTeamId,
    budget: squadService.RULES.budget,
  });

  const squad = await fantasyRepo.findSquad(req.userId, league.id, league.season);
  res.json({
    league: { id: league.id, name: league.name_ar || league.name_en || league.name },
    club: {
      id: squad.club_team_id,
      name: squad.club_name,
      logo_url: squad.club_logo,
    },
  });
});

// PUT /api/fantasy/squad — حفظ التشكيلة كاملة
//
// كاملة لا جزئية: قواعد اللعبة (الحصص، الخطة، الأندية، الميزانية)
// لا تُفحص إلا على خمسة عشر معاً، وتعديلٌ جزئي يعني حالةً وسيطة
// مكسورة يجب أن نقرّر ماذا نفعل بها — ولا جواب صحيح.
router.put('/squad', async (req, res) => {
  const league = await resolveLeague(req);
  if (!league) return res.status(400).json({ error: 'تابِع دورياً أولاً كي تبني تشكيلتك.' });

  const picks = Array.isArray(req.body?.players) ? req.body.players : [];
  const formation = String(req.body?.formation || '');
  const clubTeamId = Number(req.body?.club_team_id) || null;

  const ids = picks.map((p) => Number(p.player_id)).filter(Number.isInteger);
  const rows = await fantasyRepo.playersByIds(ids);
  const byId = new Map(rows.map((r) => [r.player_id, r]));

  const cleaned = picks.map((p) => ({
    player_id: Number(p.player_id),
    on_bench: !!p.on_bench,
    is_captain: !!p.is_captain,
    is_vice: !!p.is_vice,
  }));

  try {
    // المحفظة قبل التحقّق: قاعدتها حركةُ بيعٍ وشراء لا مجموع
    // أسعار اليوم، فلا يمكن للفحص أن يعرفها وحده.
    const plan = await fantasyRepo.planTransaction({
      userId: req.userId,
      leagueId: league.id,
      season: league.season,
      picks: cleaned,
      prices: byId,
      budget: squadService.RULES.budget,
    });

    const result = squadService.validateSquad(cleaned, byId, {
      formation,
      clubTeamId,
      leagueId: league.id,
      wallet: plan.wallet,
    });

    // ترتيب الدكّة من الخدمة لا من العميل: هي من تعرف أن الحارس
    // البديل يبقى آخراً، والعميل قد يرسل ترتيباً يكسر التبديل.
    const benchOrder = new Map(result.bench.map((b, i) => [b.player_id, i]));

    // الجولة التي تُسجَّل فيها الانتقالات: الجارية — وهي نافذة
    // السوق المفتوحة الآن.
    const { round: openRound } = await openRoundOf(league);

    await fantasyRepo.saveSquad({
      userId: req.userId,
      leagueId: league.id,
      season: league.season,
      clubTeamId,
      formation,
      name: req.body?.name,
      wallet: plan.wallet,
      value: result.value,
      sold: plan.sold,
      bought: plan.bought.map((p) => ({
        player_id: p.player_id,
        price: byId.get(p.player_id)?.price ?? 0,
      })),
      // **أول بناء ليس انتقالات.** سجلّ الانتقالات يُكتب لمن بدّل
      // لاعباً بلاعب، ومن بنى تشكيلته الأولى لم يبدّل شيئاً — كان
      // عنده صفر. وبلا هذا الشرط تُسجَّل خمسة عشر «دخولاً» في
      // جولته الأولى، فيُخصم منه عند الإقفال ٤ عن كل واحدٍ فوق
      // المجاني: ـ٥٦ نقطة عقوبةً على أنه بدأ اللعب.
      //
      // (ولم يظهر العيب في الاختبار لأن أول من جرّب كان قد فعّل
      // الوايلد كارد، وهي تُلغي الكلفة كلها.)
      round: plan.squad?.player_count > 0 ? openRound : null,
      rows: result.rows.map((r) => ({
        player_id: r.player_id,
        on_bench: r.on_bench,
        bench_order: benchOrder.get(r.player_id) ?? 0,
        is_captain: r.is_captain,
        is_vice: r.is_vice,
        price: r.price,
      })),
    });

    const squad = await fantasyRepo.findSquad(req.userId, league.id, league.season);
    res.json({
      squad: {
        id: squad.id,
        formation: squad.formation,
        club_team_id: squad.club_team_id,
        club_name: squad.club_name,
        club_logo: squad.club_logo,
        budget_left: Number(squad.budget_left),
        squad_value: Number(squad.squad_value),
        free_transfers: squad.free_transfers,
        total_points: squad.total_points,
        players: await fantasyRepo.squadPlayers(squad.id),
      },
    });
  } catch (err) {
    if (err.code === 'FANTASY_RULE') return res.status(400).json({ error: err.message });
    throw err;
  }
});

// POST /api/fantasy/autopick — تشكيلةٌ مقترحة تُملأ بها الخانات
//
// **تقترح ولا تحفظ.** الردّ خمسة عشر لاعباً يراهم صاحبها على
// الملعب فيبدّل ما شاء ثم يحفظ بنفسه. وبناءٌ يحفظ نفسه يسرق من
// اللاعب القرار الذي فتح اللعبة من أجله — ويجعل التراجع انتقالات
// لها ثمن.
router.post('/autopick', async (req, res) => {
  const league = await resolveLeague(req);
  if (!league) return res.status(400).json({ error: 'تابِع دورياً أولاً كي تبني تشكيلتك.' });

  const squad = await fantasyRepo.findSquad(req.userId, league.id, league.season);
  const clubTeamId = squad?.club_team_id || null;
  if (!clubTeamId) return res.status(400).json({ error: 'اختر ناديك أولاً.' });

  // من بنى تشكيلةً لا يُقترح عليه غيرها: الاستبدال الكامل بعد
  // الإقفال الأول انتقالاتٌ ثمنها ـ٤ لكل لاعب، وزرٌّ يفعلها بضغطة
  // بلا أن يقول ثمنها فخّ لا أداة.
  if (squad && squad.player_count > 0) {
    return res.status(400).json({
      error: 'تشكيلتك مبنيّة — بدّل لاعبيك من السوق.',
    });
  }

  const pool = await fantasyRepo.market(league.id, league.season, {});
  try {
    const { rows } = squadService.autoPick(pool, {
      clubTeamId,
      formation: String(req.body?.formation || '4-4-2'),
    });
    const byId = new Map(pool.map((p) => [p.player_id, p]));
    res.json({
      players: rows.map((r) => ({ ...byId.get(r.player_id), ...r })),
    });
  } catch (err) {
    if (err.code === 'FANTASY_RULE') return res.status(400).json({ error: err.message });
    throw err;
  }
});

// GET /api/fantasy/manager/:userId — تشكيلة مدرّبٍ آخر وترتيبه
//
// **المجمَّدة لا الحيّة** (راجع FANTASY.md): من رأى تشكيلة
// المتصدّر قبل صافرة البداية نسخها، فتموت المفاضلة التي هي اللعبة
// كلها. وقبل أول إقفال لا تُعرض تشكيلة أصلاً — ويُقال ذلك بدل
// ملعبٍ فارغ لا يشرح صمته.
router.get('/manager/:userId', async (req, res) => {
  const league = await resolveLeague(req);
  if (!league) return res.json({ ...FOLLOW_REQUIRED, manager: null, players: [] });

  const squad = await fantasyRepo.squadOfUser(req.params.userId, league.id, league.season);
  if (!squad) {
    return res.json({
      league: { id: league.id, name: league.name },
      manager: null,
      round: null,
      players: [],
    });
  }

  const round = await fantasyRepo.lastLockedRound(squad.id);
  const players = round ? await fantasyRepo.roundLineupDetailed(squad.id, round) : [];
  const rank = await fantasyRepo.rankOf(squad.id, league.id, league.season);

  res.json({
    league: { id: league.id, name: league.name },
    manager: {
      user_id: squad.user_id,
      name: squad.display_name,
      avatar_url: squad.avatar_url,
      club_name: squad.club_name,
      club_logo: squad.club_logo,
      formation: squad.formation,
      rank,
      total_points: squad.total_points,
      squad_value: Number(squad.squad_value) + Number(squad.budget_left),
    },
    round,
    total: players.reduce((sum, p) => sum + (p.on_bench ? 0 : p.points), 0),
    players,
  });
});

// POST /api/fantasy/wildcard — تفعيل الوايلد كارد للجولة الجارية
//
// تُفعَّل قبل الإقفال وتسري على انتقالات هذا الأسبوع كلها: من
// فعّلها ثم بدّل عشرة لاعبين لا يُخصم منه شيء.
//
// ولا تُلغى بعد التفعيل: قرارُ استعمالها هو نصف قيمتها، وزرُّ
// تراجعٍ يجعلها بلا ثمن — يفعّلها الجميع كل أسبوع ثم يتراجعون
// عمّا لم يحتاجوه.
router.post('/wildcard', async (req, res) => {
  const league = await resolveLeague(req);
  if (!league) return res.status(400).json({ error: 'تابِع دورياً أولاً.' });

  const squad = await fantasyRepo.findSquad(req.userId, league.id, league.season);
  if (!squad) return res.status(400).json({ error: 'ابنِ تشكيلتك أولاً.' });

  const { round, half } = await openRoundOf(league);
  if (!round) return res.status(400).json({ error: 'لا جولة مفتوحة الآن.' });

  const ok = await fantasyRepo.useChip(squad.id, 'wildcard', round, half);
  if (!ok) {
    return res.status(400).json({
      error: 'استعملت الوايلد كارد في هذا النصف من الموسم.',
    });
  }
  res.json({ wildcard: { round, half } });
});

// GET /api/fantasy/round — نقاط الجولة، لاعباً لاعباً
//
// من الجولة المجمّدة لا من التشكيلة الحالية: من بدّل كابتنه بعد
// المباراة الأولى يجب أن يرى الجولة كما لُعبت لا كما صارت.
router.get('/round', async (req, res) => {
  const league = await resolveLeague(req);
  if (!league) return res.json({ ...FOLLOW_REQUIRED, round: null, players: [] });

  const squad = await fantasyRepo.findSquad(req.userId, league.id, league.season);
  if (!squad) return res.json({ league: { id: league.id }, squad: null, round: null, players: [] });

  const rounds = await fixtureRepo.roundsFor(league.id, league.season);
  const asked = String(req.query.round || '');
  const round = rounds.some((r) => r.round === asked)
    ? asked
    : (rounds.find((r) => r.open > 0) || rounds[rounds.length - 1])?.round || null;

  // بأسمائها من جدول اللاعبين لا من التشكيلة الحالية: من باع
  // لاعباً بعد الجولة كان يراه في جولته بلا اسمٍ ولا صورة.
  const lineup = round ? await fantasyRepo.roundLineupDetailed(squad.id, round) : [];

  const { rows: entries } = await require('../config/db').query(
    'SELECT transfers_cost, transfers_used, wildcard FROM fantasy_round_entries WHERE squad_id = $1 AND round = $2',
    [squad.id, round]
  );
  const entry = entries[0] || null;

  res.json({
    league: { id: league.id, name: league.name },
    round,
    rounds: rounds.map((r) => r.round),
    // الكلفة مفصولة عن المجموع لا مدموجة فيه: «٥٤ نقطة، −٤
    // انتقالات» تُفهم، ورقمٌ واحد لا يُفسَّر.
    transfers_cost: entry?.transfers_cost ?? 0,
    transfers_used: entry?.transfers_used ?? 0,
    wildcard: entry?.wildcard ?? false,
    total: lineup.reduce((sum, l) => sum + l.points, 0),
    players: lineup,
  });
});

// GET /api/fantasy/leaderboard — عرش «فريقي»
router.get('/leaderboard', async (req, res) => {
  const league = await resolveLeague(req);
  if (!league) return res.json({ ...FOLLOW_REQUIRED, entries: [] });

  const entries = await fantasyRepo.leaderboard(league.id, league.season);
  res.json({
    league: { id: league.id, name: league.name },
    me: entries.find((e) => e.user_id === req.userId) || null,
    entries: entries.map((e) => ({
      rank: Number(e.rank),
      // معرّفه معه: الصفّ بابٌ إلى تشكيلته وترتيبه، و«من هذا الذي
      // يتصدّرني؟» سؤالٌ يُسأل من داخل العرش لا من مكان آخر.
      user_id: e.user_id,
      name: e.name || e.display_name || 'مشجع',
      avatar_url: e.avatar_url,
      club_name: e.club_name,
      club_logo: e.club_logo,
      total_points: e.total_points,
      is_me: e.user_id === req.userId,
    })),
  });
});

module.exports = router;
