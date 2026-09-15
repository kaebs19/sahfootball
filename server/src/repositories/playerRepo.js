// playerRepo — لاعبو الأندية وإحصاؤهم. (لا يخلط بينه وبين
// userRepo: «اللاعب» هناك مستخدمٌ عندنا، وهنا كرويٌّ في الملعب.)
const db = require('../config/db');

/**
 * قائمة نادٍ كاملة في معاملة واحدة.
 *
 * ON CONFLICT يحدّث ولا يتجاهل: اللاعب ينتقل بين الأندية ويغيّر
 * رقمه وتتبدّل صورته، ولو تجاهلنا التعارض لبقي في ناديه القديم
 * إلى الأبد — فيظهر في سوق فريقٍ تركه.
 *
 * والسعر والنقاط **خارج جهة UPDATE عمداً**: الأول يضبطه الأدمن
 * من اللوحة والثاني يُبنى من الجولات، ومزامنةٌ تكتبهما تمسح شهراً
 * من العمل في ثانية بلا خطأ في السجل.
 */
async function upsertSquad(players) {
  if (!players.length) return 0;
  const client = await db.pool.connect();
  try {
    await client.query('BEGIN');
    for (const p of players) {
      await client.query(
        `INSERT INTO players
           (id, team_id, league_id, season, name_en, name_ar,
            photo_url, position, shirt_number, updated_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9, now())
         ON CONFLICT (id) DO UPDATE SET
           team_id      = EXCLUDED.team_id,
           league_id    = EXCLUDED.league_id,
           season       = EXCLUDED.season,
           name_en      = EXCLUDED.name_en,
           -- الاسم العربي يُكتب باليد من اللوحة، والمزوّد لا
           -- يعرفه: COALESCE يبقي المكتوب ولا يدهسه بـ NULL.
           name_ar      = COALESCE(players.name_ar, EXCLUDED.name_ar),
           photo_url    = EXCLUDED.photo_url,
           position     = EXCLUDED.position,
           shirt_number = EXCLUDED.shirt_number,
           available    = true,
           updated_at   = now()`,
        [p.id, p.team_id, p.league_id, p.season, p.name_en, p.name_ar,
         p.photo_url, p.position, p.shirt_number]
      );
    }
    await client.query('COMMIT');
    return players.length;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

/**
 * إحصاء لاعبي مباراة — يُستدعى في كل نبضة أثناء اللعب ومرة بعد
 * الصافرة، فالكتابة هنا idempotent بالكامل.
 *
 * الصفّ الناقص في players قبل الإحصاء: المفتاح الأجنبي يرفض
 * إحصاء لاعبٍ لا نعرفه، ولاعبٌ واحد كهذا كان سيُسقط مباراة
 * كاملة. نزرع له صفّاً بما نملك (اسم وصورة، بلا مركز ولا نادٍ)
 * ثم تكمله أول مزامنة قوائم — وحتى ذلك الحين لا يظهر في السوق
 * لأن available تبقى false عمداً.
 */
async function upsertFixtureStats(rows) {
  if (!rows.length) return 0;
  const client = await db.pool.connect();
  try {
    await client.query('BEGIN');
    for (const r of rows) {
      await client.query(
        `INSERT INTO players (id, name_en, photo_url, available, updated_at)
         VALUES ($1, $2, $3, false, now())
         ON CONFLICT (id) DO NOTHING`,
        [r.player_id, r.player_name, r.player_photo]
      );
      await client.query(
        `INSERT INTO player_fixture_stats
           (fixture_id, player_id, team_id, minutes, started, goals, assists,
            conceded, saves, yellow, red, own_goals,
            pen_scored, pen_missed, pen_saved, rating, updated_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16, now())
         ON CONFLICT (fixture_id, player_id) DO UPDATE SET
           team_id    = EXCLUDED.team_id,
           minutes    = EXCLUDED.minutes,
           started    = EXCLUDED.started,
           goals      = EXCLUDED.goals,
           assists    = EXCLUDED.assists,
           conceded   = EXCLUDED.conceded,
           saves      = EXCLUDED.saves,
           yellow     = EXCLUDED.yellow,
           red        = EXCLUDED.red,
           pen_scored = EXCLUDED.pen_scored,
           pen_missed = EXCLUDED.pen_missed,
           pen_saved  = EXCLUDED.pen_saved,
           rating     = EXCLUDED.rating,
           -- own_goals و points ليسا من المزوّد: الأول يُصحَّح من
           -- أحداث المباراة والثاني يحسبه محرّك النقاط. نبضةٌ
           -- تكتبهما تمحو عمل التسوية في كل تحديث.
           updated_at = now()`,
        [r.fixture_id, r.player_id, r.team_id, r.minutes, r.started,
         r.goals, r.assists, r.conceded, r.saves, r.yellow, r.red,
         r.own_goals, r.pen_scored, r.pen_missed, r.pen_saved, r.rating]
      );
    }
    await client.query('COMMIT');
    return rows.length;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

/** أندية دوري في موسم — مصدر حلقة مزامنة القوائم. */
async function teamIdsInLeague(leagueId, season) {
  const { rows } = await db.query(
    `SELECT DISTINCT team_id FROM (
       SELECT home_team_id AS team_id FROM fixtures
        WHERE league_id = $1 AND season = $2
       UNION
       SELECT away_team_id FROM fixtures
        WHERE league_id = $1 AND season = $2
     ) t
     ORDER BY team_id`,
    [leagueId, season]
  );
  return rows.map((r) => r.team_id);
}

/** إحصاء مباراة واحدة كما هو مخزّن — لمحرّك النقاط وشاشة الجولة. */
async function statsForFixtures(fixtureIds) {
  if (!fixtureIds.length) return [];
  const { rows } = await db.query(
    `SELECT s.*, p.position, p.team_id AS player_team_id,
            COALESCE(p.name_ar, p.name_en) AS player_name
       FROM player_fixture_stats s
       JOIN players p ON p.id = s.player_id
      WHERE s.fixture_id = ANY($1)`,
    [fixtureIds]
  );
  return rows;
}

module.exports = {
  upsertSquad,
  upsertFixtureStats,
  teamIdsInLeague,
  statsForFixtures,
};
