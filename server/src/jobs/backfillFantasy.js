// backfillFantasy — إحصاء ما مضى من الموسم، ثم التسعير.
//
// يُشغَّل مرة عند إطلاق «فريقي»، وبعدها لا حاجة له: التسوية
// الدورية تجلب إحصاء كل جولة عند نهايتها.
//
// وبدونه تبدأ اللعبة بسوقٍ كل لاعب فيه بسعر مركزه: لا نجم ولا
// صفقة ولا اكتشاف، والميزانية رقمٌ لا يقيّد شيئاً. التسعير يقرأ
// الأداء، والأداء يحتاج أن يكون مجلوباً أولاً.
//
// الكلفة: طلبٌ لكل مباراة منتهية. ثماني جولات في ستة دوريات ≈
// ٤٠٠ طلب من أصل ٧٥٠٠ يومياً، وبمباعدة المحدِّد (٢٠٠م.ث) تستغرق
// نحو ثمانين ثانية.
require('dotenv').config();

const db = require('../config/db');
const leagueRepo = require('../repositories/leagueRepo');
const playerRepo = require('../repositories/playerRepo');
const fantasyScoring = require('../services/fantasyScoring');
const fantasyPricing = require('../services/fantasyPricing');
const { syncFixtureStats } = require('./syncPlayers');
const logger = require('../utils/logger');

async function backfill({ leagueId = null } = {}) {
  const leagues = (await leagueRepo.findEnabled())
    .filter((l) => l.in_app && (!leagueId || l.id === leagueId));
  const cfg = await fantasyScoring.config();

  let fixtures = 0;
  let priced = 0;

  for (const league of leagues) {
    const { rows } = await db.query(
      `SELECT id FROM fixtures
        WHERE league_id = $1 AND season = $2 AND status = 'finished'
        ORDER BY kickoff_at`,
      [league.id, league.season]
    );

    // المباريات التي جُلب إحصاؤها سلفاً تُتخطّى: إعادة التشغيل
    // بعد انقطاع يجب ألا تشتري ما اشتُري (الكاش يغطّي يوماً واحداً
    // فقط، وهذا يغطّي الموسم كله).
    const { rows: have } = await db.query(
      `SELECT DISTINCT fixture_id FROM player_fixture_stats
        WHERE fixture_id = ANY($1)`,
      [rows.map((r) => r.id)]
    );
    const done = new Set(have.map((h) => h.fixture_id));
    const todo = rows.map((r) => r.id).filter((id) => !done.has(id));

    if (todo.length) {
      logger.info(`[backfill] league ${league.id}: ${todo.length} fixtures`);
      await syncFixtureStats(todo, { settled: true });
      fixtures += todo.length;
    }

    // نقاط كل إحصاء — منها يُحتسب السعر ومنها حصيلة الموسم.
    const stats = await playerRepo.statsForFixtures(rows.map((r) => r.id));
    await playerRepo.writeStatPoints(
      stats.map((s) => ({
        fixture_id: s.fixture_id,
        player_id: s.player_id,
        points: fantasyScoring.computePlayerPoints(s, s.position, cfg).points,
      }))
    );

    priced += await fantasyPricing.repriceLeague(league.id, league.season);
  }

  await db.query(
    `UPDATE players p
        SET total_points = COALESCE((
              SELECT SUM(s.points) FROM player_fixture_stats s WHERE s.player_id = p.id
            ), 0)`
  );

  return { fixtures, priced };
}

if (require.main === module) {
  const asked = Number(process.argv[2]) || null;
  backfill({ leagueId: asked })
    .then(({ fixtures, priced }) => {
      logger.info(`[backfill] done — ${fixtures} fixtures, ${priced} players priced`);
      process.exit(0);
    })
    .catch((err) => {
      logger.error('[backfill] failed:', err.message);
      process.exit(1);
    });
}

module.exports = { backfill };
