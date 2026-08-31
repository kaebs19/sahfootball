// routes/round — توقّع الجولة: تسع مباريات في طلب واحد.
//
// كان توقّع جولة كاملة تسعة طلبات وتسع فتحات لشيت التوقّع. ومن
// يريد الجولة كاملة يستسلم عند الرابعة.
//
// والقواعد كلها في predictionService كما في كل باب: هذا المسار
// حلقةٌ فوقها لا نسخةٌ منها.
const express = require('express');
const requireAuth = require('../middleware/requireAuth');
const leagueRepo = require('../repositories/leagueRepo');
const fixtureRepo = require('../repositories/fixtureRepo');
const predictionRepo = require('../repositories/predictionRepo');
const predictionService = require('../services/predictionService');

const router = express.Router();
router.use(requireAuth);

/** الجولة المقصودة: المطلوبة إن صحّت، وإلا أقرب جولة لم يُلعب أكثرها. */
function pickRound(rounds, asked) {
  if (asked && rounds.some((r) => r.round === asked)) return asked;
  // "أقرب جولة فيها مباراة مفتوحة" تبدو صحيحة وليست كذلك: جولةٌ
  // لُعبت ثمانٍ من تسع وبقيت واحدة مؤجّلة تصير الوجهة الافتراضية
  // لشاشة اسمها "توقّع الجولة" وثمانية صفوفها مقفلة.
  return (rounds.find((r) => r.open * 2 > r.total)
    || rounds.find((r) => r.open > 0)
    || rounds[rounds.length - 1])?.round || null;
}

// GET /api/round?league=307&round=...
router.get('/', async (req, res) => {
  const leagues = (await leagueRepo.findEnabled()).filter((l) => l.in_app);
  const askedLeague = Number(req.query.league);
  const league = leagues.find((l) => l.id === askedLeague) || leagues[0];
  if (!league) return res.json({ league: null, rounds: [], fixtures: [] });

  const rounds = await fixtureRepo.roundsFor(league.id, league.season);
  const round = pickRound(rounds, String(req.query.round || ''));
  const rows = round
    ? await fixtureRepo.byRound(league.id, league.season, round)
    : [];

  const mine = rows.length
    ? await predictionRepo.findByUserAndFixtures(req.userId, rows.map((f) => f.id))
    : [];
  const byFixture = new Map(mine.map((p) => [p.fixture_id, p]));

  // حالة الأداة مرة واحدة للجولة كلها لا لكل مباراة: الحصة على
  // مستوى الدوري والموسم، فتسعة استعلامات عدّ تعطي تسع نسخ من
  // رقم واحد.
  const mult = rows.length
    ? await predictionService.multiplierState(req.userId, rows[0], null).catch(() => null)
    : null;

  res.json({
    league: { id: league.id, name: league.name, logo_url: `/logos/league-${league.id}.png` },
    rounds: rounds.map((r) => ({ round: r.round, total: r.total, open: r.open })),
    round,
    multiplier: mult,
    fixtures: rows.map((f) => {
      const p = byFixture.get(f.id) || null;
      return {
        id: f.id,
        kickoff_at: f.kickoff_at,
        status: f.status,
        open: predictionService.isOpen(f),
        home_team_id: f.home_team_id,
        home_team_name: f.home_team_name,
        home_logo: `/logos/team-${f.home_team_id}.png`,
        away_team_id: f.away_team_id,
        away_team_name: f.away_team_name,
        away_logo: `/logos/team-${f.away_team_id}.png`,
        goals_home: f.goals_home,
        goals_away: f.goals_away,
        pred_home: p?.pred_home ?? null,
        pred_away: p?.pred_away ?? null,
        multiplier: p?.multiplier ?? 1,
      };
    }),
  });
});

// POST /api/round — { predictions: [{ fixtureId, home, away, multiplier }] }
router.post('/', async (req, res) => {
  const list = Array.isArray(req.body?.predictions) ? req.body.predictions : null;
  if (!list) return res.status(400).json({ error: 'predictions مطلوبة كمصفوفة' });

  // سقف يمنع طلباً واحداً يحمل ألف توقّع: أطول جولة عندنا عشر
  // مباريات، والعشرون هامش سخيّ.
  if (list.length > 20) {
    return res.status(400).json({ error: 'دفعة أكبر من جولة' });
  }

  let saved = 0;
  let denied = 0;
  let late = 0;

  for (const item of list) {
    try {
      const row = await predictionService.submit({
        userId: req.userId,
        fixtureId: Number(item?.fixtureId),
        home: Number(item?.home),
        away: Number(item?.away),
        multiplier: item?.multiplier === undefined ? null : Number(item.multiplier),
      });
      saved += 1;
      if (row?.multiplierDenied) denied += 1;
    } catch (err) {
      // مباراة انطلقت بين رسم الشاشة وإرسالها: تُتخطّى ولا تُسقط
      // البقية. حفظ سبع من تسع أفضل من رفض التسع لأجل واحدة.
      if (err.status === 409 || err.status === 404 || err.status === 400) late += 1;
      else throw err;
    }
  }

  res.status(201).json({ saved, denied, late });
});

module.exports = router;
