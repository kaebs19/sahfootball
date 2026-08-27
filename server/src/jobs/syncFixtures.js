// syncFixtures — مزامنة الفرق وجدول مباريات الموسم من المزود للقاعدة.
//
// يُشغَّل يدوياً (npm run sync)، ومن المجدول كل SYNC_FULL_HOURS،
// ومن زر المزامنة في اللوحة. الترتيب داخل الدوري الواحد مهم:
// الفرق أولاً ثم المباريات، لأن جدول fixtures فيه مفاتيح أجنبية
// (REFERENCES) نحو جدول teams — إدخال مباراة لفريق غير موجود يفشل.
//
// تكلفة الحصة: طلبان (teams + fixtures) لكل دوري مفعّل، وأقل مع
// الكاش. هذا هو سبب وجود عمود enabled في جدول leagues: خمسة
// دوريات مفعّلة = 10 طلبات لكل مزامنة كاملة من أصل 100 يومياً.
require('dotenv').config();

const footballProvider = require('../services/footballProvider');
const { mapTeam } = require('../mappers/teamMapper');
const { mapFixture } = require('../mappers/fixtureMapper');
const teamRepo = require('../repositories/teamRepo');
const fixtureRepo = require('../repositories/fixtureRepo');
const leagueRepo = require('../repositories/leagueRepo');
const logger = require('../utils/logger');

// مزامنة دوري واحد. لا تحتسب النقاط — الاحتساب يجري مرة واحدة بعد
// كل الدوريات، لأنه استعلام على القاعدة لا علاقة له بأي دوري بعينه.
async function syncLeague(league) {
  const options = { leagueId: league.id, season: league.season };

  const rawTeams = await footballProvider.getTeams(options);
  const teams = rawTeams.map(mapTeam);
  await teamRepo.upsertMany(teams);

  const rawFixtures = await footballProvider.getSeasonFixtures(options);
  const fixtures = rawFixtures.map(mapFixture);
  await fixtureRepo.upsertMany(fixtures);

  await leagueRepo.touchSynced(league.id);
  logger.info(
    `[sync] league ${league.id} (${league.name_en}): ${teams.length} teams, ${fixtures.length} fixtures`
  );

  return { id: league.id, name: league.name, teams: teams.length, fixtures: fixtures.length };
}

async function syncAll() {
  logger.info(`[sync] starting (USE_SAMPLES=${process.env.USE_SAMPLES})`);

  const leagues = await leagueRepo.findEnabled();
  if (leagues.length === 0) {
    logger.warn('[sync] no enabled leagues — nothing to sync');
  }

  const results = [];
  for (const league of leagues) {
    try {
      results.push(await syncLeague(league));
    } catch (err) {
      // فشل دوري واحد لا يوقف البقية. السببان الأكثر ترجيحاً —
      // نفاد الحصة اليومية، أو أن الباقة المجانية لا تغطي هذا
      // الدوري/الموسم — كلاهما يخص دورياً بعينه. لو رمينا الخطأ
      // للأعلى لكان دوري واحد معطوب يمنع تحديث كل الدوريات
      // السليمة إلى أن ينتبه الأدمن. نجمع الخطأ في نتيجة الدوري
      // بدلاً من ذلك، فتظهر اللوحة "هذا فشل" بجانب من نجح.
      logger.error(`[sync] league ${league.id} failed:`, err.message);
      results.push({ id: league.id, name: league.name, teams: 0, fixtures: 0, error: err.message });
    }
  }

  // بعد كل مزامنة نحتسب نقاط المباريات التي انتهت للتو.
  // الدالة آمنة التكرار — المحتسب سابقاً لا يُلمس.
  const scoringService = require('../services/scoringService');
  const settled = await scoringService.settleFinished();
  if (settled > 0) logger.info(`[sync] settled ${settled} predictions`);

  // نرجع ملخصاً تعرضه اللوحة. المجاميع العليا (teams/fixtures/settled)
  // محفوظة بشكلها القديم حرفياً حتى لا تنكسر اللوحة الحالية،
  // والتفصيل لكل دوري يأتي إضافةً في leagues.
  return {
    teams: results.reduce((sum, r) => sum + r.teams, 0),
    fixtures: results.reduce((sum, r) => sum + r.fixtures, 0),
    settled,
    leagues: results,
  };
}

// require.main === module تعني: "هذا الملف شُغِّل مباشرة بـ node"
// وليس مستورداً بـ require من ملف آخر. بهذا يصلح الملف للأمرين:
// سكربت مستقل الآن، ودالة تستدعى من مجدول داخل السيرفر لاحقاً.
if (require.main === module) {
  syncAll()
    .then(() => {
      logger.info('[sync] done');
      process.exit(0); // نخرج صراحة: اتصالات pg/redis المفتوحة تبقي العملية حية
    })
    .catch((err) => {
      logger.error('[sync] failed:', err.message);
      process.exit(1);
    });
}

module.exports = { syncAll, syncLeague };
