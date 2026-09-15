// syncPlayers — قوائم الأندية وإحصاء اللاعبين. أساس «فريقي»
// (راجع FANTASY.md).
//
// وظيفتان في ملف واحد لأنهما وجهان لشيء واحد — «من اللاعبون وماذا
// فعلوا» — لكنهما تُشغَّلان على إيقاعين مختلفين:
//
//   syncSquads    نادراً (كل بضعة أيام، وبعد الميركاتو). طلبٌ لكل
//                 نادٍ: ثمانية عشر للدوري.
//   syncFixtureStats  بعد كل مباراة، وأثناءها إن أردنا نقاطاً
//                 جارية. طلبٌ لكل مباراة: تسعة للجولة.
//
// ولا تركب أيٌّ منهما نبضةً جديدة: المجدول الموجود يعرف متى تكون
// مباراة في نافذتها الحيّة، ونبضةٌ ثانية بجواره تضاعف استهلاك
// الحصة على نفس المعلومة.
require('dotenv').config();

const footballProvider = require('../services/footballProvider');
const { mapSquad, mapFixturePlayers } = require('../mappers/playerMapper');
const playerRepo = require('../repositories/playerRepo');
const fixtureRepo = require('../repositories/fixtureRepo');
const leagueRepo = require('../repositories/leagueRepo');
const logger = require('../utils/logger');

/**
 * قوائم كل أندية الدوريات المعروضة في التطبيق.
 *
 * الأندية تُقرأ من مبارياتنا لا من المزوّد: جدول الموسم عندنا
 * أصلاً، وطلبُ قائمة الأندية مرة أخرى شراءٌ لما نملك.
 *
 * وفشل نادٍ واحد لا يُسقط البقية: قائمةٌ ناقصة خيرٌ من مزامنة
 * تنهار في النادي الثالث فتترك خمسة عشر بلا لاعبين.
 */
async function syncSquads() {
  const leagues = (await leagueRepo.findEnabled()).filter((l) => l.in_app);
  let total = 0;

  for (const league of leagues) {
    const teamIds = await playerRepo.teamIdsInLeague(league.id, league.season);
    for (const teamId of teamIds) {
      try {
        const raw = await footballProvider.getTeamSquad(teamId);
        const players = mapSquad(raw, {
          leagueId: league.id,
          season: league.season,
        });
        total += await playerRepo.upsertSquad(players);
      } catch (err) {
        logger.error(`[players] squad ${teamId} failed: ${err.message}`);
      }
    }
    logger.info(
      `[players] league ${league.id}: ${teamIds.length} clubs, ${total} players`
    );
  }
  return total;
}

/**
 * إحصاء لاعبي مباريات بعينها.
 *
 * goalsAgainst من صفّ المباراة عندنا: المزوّد يعطي «ما دخل
 * مرماه» للحارس وحده، فبلا هذا يخرج كل مدافع بشباك نظيفة
 * (راجع mapFixturePlayers).
 *
 * @param settled هل انتهت المباريات — يطيل عمر الكاش من دقيقتين
 *   إلى ست ساعات، فلا نعيد شراء إحصاء مباراة أمس لكل من فتحها.
 */
async function syncFixtureStats(fixtureIds, { settled = false } = {}) {
  let rows = 0;
  for (const id of fixtureIds) {
    try {
      const fixture = await fixtureRepo.findById(id);
      if (!fixture) continue;

      const goalsAgainst = {
        [fixture.home_team_id]: fixture.goals_away ?? 0,
        [fixture.away_team_id]: fixture.goals_home ?? 0,
      };

      const raw = await footballProvider.getFixturePlayerStats(id, { settled });
      const stats = mapFixturePlayers(raw, { fixtureId: id, goalsAgainst });
      rows += await playerRepo.upsertFixtureStats(stats);
    } catch (err) {
      logger.error(`[players] stats ${id} failed: ${err.message}`);
    }
  }
  return rows;
}

if (require.main === module) {
  syncSquads()
    .then((n) => {
      logger.info(`[players] done — ${n} players`);
      process.exit(0);
    })
    .catch((err) => {
      logger.error('[players] failed:', err.message);
      process.exit(1);
    });
}

module.exports = { syncSquads, syncFixtureStats };
