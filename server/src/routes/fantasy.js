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
  res.json({
    league: { id: league.id, name: league.name },
    rules: squadService.RULES,
    formations: Object.keys(squadService.FORMATIONS),
    squad: squad && {
      id: squad.id,
      name: squad.name,
      club_team_id: squad.club_team_id,
      formation: squad.formation,
      budget_left: Number(squad.budget_left),
      // قيمة اللاعبين بأسعار اليوم. مع المحفظة تعطي «قيمة فريقك»،
      // وهي المقياس الثاني في اللعبة بعد النقاط: من ينمو فريقه
      // يشتري ما لا يستطيعه غيره.
      squad_value: Number(squad.squad_value),
      free_transfers: squad.free_transfers,
      wildcards_used: squad.wildcards_used,
      total_points: squad.total_points,
      players: await fantasyRepo.squadPlayers(squad.id),
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
    const rounds = await fixtureRepo.roundsFor(league.id, league.season);
    const openRound = (rounds.find((r) => r.open > 0) || rounds[rounds.length - 1])?.round;

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
      round: openRound,
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

  const lineup = round ? await fantasyRepo.roundLineup(squad.id, round) : [];
  const names = await fantasyRepo.squadPlayers(squad.id);
  const byId = new Map(names.map((n) => [n.player_id, n]));

  res.json({
    league: { id: league.id, name: league.name },
    round,
    rounds: rounds.map((r) => r.round),
    total: lineup.reduce((sum, l) => sum + l.points, 0),
    players: lineup.map((l) => ({ ...l, ...(byId.get(l.player_id) || {}) })),
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
