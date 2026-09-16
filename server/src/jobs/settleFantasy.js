// settleFantasy — تجميد الجولة عند انطلاقها، وتسويتها عند نهايتها.
//
// وظيفتان على طرفَي الجولة، وكلتاهما آمنة التكرار (idempotent)
// فتُستدعى من المجدول بلا حساب: التجميد يتجاهل ما جُمّد، والتسوية
// تتخطّى ما سُوّي (settled_at).
//
// ولماذا التجميد أصلاً؟ لأن اللعبة موسمية: التشكيلة تتغيّر بين
// الجولات، ومن بدّل كابتنه بعد أول مباراة سيأخذ نقاط الكابتن
// الجديد على مباراةٍ لُعبت قبل التبديل. الجولة تُحتسب بما كان.
require('dotenv').config();

const fantasyRepo = require('../repositories/fantasyRepo');
const playerRepo = require('../repositories/playerRepo');
const fixtureRepo = require('../repositories/fixtureRepo');
const leagueRepo = require('../repositories/leagueRepo');
const squadService = require('../services/fantasySquadService');
const fantasyScoring = require('../services/fantasyScoring');
// حركة الأسعار بعد التسوية تحتاجه. وغيابه كان يرمي ReferenceError
// في آخر سطر من الحلقة — بعد كتابة التسوية وقبل تحريك الأسعار،
// فتُسوّى الجولة ولا يتحرّك سعرٌ واحد ولا تُسوّى التي بعدها.
const fantasyMarket = require('../services/fantasyMarket');
const { syncFixtureStats } = require('./syncPlayers');
const db = require('../config/db');
const logger = require('../utils/logger');

/** جولة الدوري الجارية: الجولة التي فيها أقرب مباراة لم تُلعب. */
async function currentRound(league) {
  const { rows } = await db.query(
    `SELECT f.round
       FROM fixtures f
      WHERE f.league_id = $1 AND f.season = $2 AND f.round IS NOT NULL
        AND f.status IN ('scheduled', 'live')
      ORDER BY f.kickoff_at
      LIMIT 1`,
    [league.id, league.season]
  );
  return rows[0]?.round ?? null;
}

/**
 * تجميد الجولة الجارية إن كانت قد بدأت.
 *
 * الشرط «بدأت» لا «ستبدأ بعد ساعة»: الإقفال لحظة انطلاق أول
 * مباراة (راجع FANTASY.md)، وتجميدٌ أبكر يسرق من اللاعب ساعاتٍ
 * يملكها.
 */
async function lockStartedRounds() {
  const leagues = (await leagueRepo.findEnabled()).filter((l) => l.in_app);
  let locked = 0;

  for (const league of leagues) {
    const round = await currentRound(league);
    if (!round) continue;

    const { rows } = await db.query(
      `SELECT COUNT(*) FILTER (WHERE kickoff_at <= now())::int AS started
         FROM fixtures
        WHERE league_id = $1 AND season = $2 AND round = $3`,
      [league.id, league.season, round]
    );
    if (!rows[0].started) continue;

    const n = await fantasyRepo.lockRound(league.id, league.season, round, {
      minPlayers: squadService.RULES.squad_size,
    });
    if (n) logger.info(`[fantasy] locked ${n} squads — league ${league.id} ${round}`);
    locked += n;
  }
  return locked;
}

/**
 * تسوية جولة انتهت مبارياتها كلها.
 *
 * ونجلب إحصاء المباريات قبل الحساب: التسوية تقرأ
 * player_fixture_stats، وجولةٌ لم يُجلب إحصاؤها تُسوّى بأصفار —
 * وهي أسوأ نتيجة ممكنة لأنها تبدو حساباً صحيحاً لأداءٍ سيّئ.
 */
async function settleFinishedRounds() {
  const leagues = (await leagueRepo.findEnabled()).filter((l) => l.in_app);
  const cfg = await fantasyScoring.config();
  let settled = 0;

  for (const league of leagues) {
    const { rows: rounds } = await db.query(
      `SELECT DISTINCT e.round
         FROM fantasy_round_entries e
         JOIN fantasy_squads s ON s.id = e.squad_id
        WHERE s.league_id = $1 AND s.season = $2 AND e.settled_at IS NULL`,
      [league.id, league.season]
    );

    for (const { round } of rounds) {
      const fixtures = await fixtureRepo.byRound(league.id, league.season, round);
      const done = fixtures.every((f) => ['finished', 'postponed', 'cancelled'].includes(f.status));
      if (!done || !fixtures.length) continue;

      await syncFixtureStats(
        fixtures.filter((f) => f.status === 'finished').map((f) => f.id),
        { settled: true }
      );

      const stats = await playerRepo.statsForFixtures(fixtures.map((f) => f.id));
      const statsByPlayer = new Map();
      const players = new Map();
      for (const s of stats) {
        if (!statsByPlayer.has(s.player_id)) statsByPlayer.set(s.player_id, []);
        statsByPlayer.get(s.player_id).push(s);
        players.set(s.player_id, { position: s.position });
      }

      // نقاط كل إحصاء أولاً: مجموع الموسم في players.total_points
      // يُجمع منها، ولو تُركت صفراً لخرج السوق كله بصفر نقطة —
      // رقمٌ يبدو حقيقياً ولا يشتكي منه أحد.
      //
      // وnقاط الإضافة توزَّع داخلها على كل مباراة قبل الحساب،
      // فتصل إلى صفوف statsByPlayer نفسها — وهي التي تقرأها
      // settleRound بعد سطور.
      await playerRepo.writeStatPoints(fantasyScoring.scoreFixtureStats(stats, cfg));

      const entries = (await fantasyRepo.unsettledEntries(round))
        .filter((e) => e.league_id === league.id);

      for (const entry of entries) {
        const lineup = await fantasyRepo.roundLineup(entry.squad_id, round);
        // مركز من لم يلعب لا يصل من الإحصاء (لا صفَّ له أصلاً)،
        // والتبديل التلقائي يحتاجه: بلا مركزٍ للغائب لا يعرف
        // المحرّك أيّ بديلٍ يجوز أن يحلّ محلّه.
        const missing = lineup
          .map((l) => l.player_id)
          .filter((id) => !players.has(id));
        for (const [id, row] of await playerRepo.positionsFor(missing)) {
          players.set(id, row);
        }
        const result = squadService.settleRound(entry, lineup, statsByPlayer, players, cfg);
        await fantasyRepo.writeSettlement(entry.squad_id, round, result.rows, result.points);
        settled += 1;
      }

      if (entries.length) {
        logger.info(`[fantasy] settled ${entries.length} squads — league ${league.id} ${round}`);
      }

      // حركة الأسعار بعد التسوية لا قبلها: الطلب يُقرأ من انتقالات
      // هذه الجولة، والأداء من نقاطها — وكلاهما لا يكتمل قبل أن
      // تُحتسب. والحارس هو settled_at نفسه: الجولة لا تُسوّى مرتين
      // فلا تتحرّك أسعارها مرتين.
      await fantasyMarket.moveLeaguePrices(league.id, league.season, round);
    }
  }

  // حصيلة اللاعب في الموسم — يقرأها السوق للترتيب والتسعير.
  await db.query(
    `UPDATE players p
        SET total_points = COALESCE((
              SELECT SUM(s.points) FROM player_fixture_stats s WHERE s.player_id = p.id
            ), 0)`
  );

  return settled;
}

async function tick() {
  const locked = await lockStartedRounds();
  const settled = await settleFinishedRounds();
  return { locked, settled };
}

if (require.main === module) {
  tick()
    .then(({ locked, settled }) => {
      logger.info(`[fantasy] done — locked ${locked}, settled ${settled}`);
      process.exit(0);
    })
    .catch((err) => {
      logger.error('[fantasy] failed:', err.message);
      process.exit(1);
    });
}

module.exports = { tick, lockStartedRounds, settleFinishedRounds, currentRound };
