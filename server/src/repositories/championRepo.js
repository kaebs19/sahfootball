// championRepo — كل SQL توقّع البطل ومتابعة الدوريات.
const db = require('../config/db');

// ─────────────── متابعة الدوريات ───────────────

/** الدوريات التي يتابعها — معرّفاتها فقط. */
async function followedIds(userId) {
  const { rows } = await db.query(
    'SELECT league_id FROM user_leagues WHERE user_id = $1',
    [userId]
  );
  return rows.map((r) => r.league_id);
}

/**
 * ضبط قائمة المتابعة كاملةً في معاملة واحدة.
 *
 * حذفٌ ثم إدراج لا مقارنةُ فروق: القائمة صغيرة (ستة على الأكثر)،
 * والفرق في الأداء لا يُقاس. والمكسب أن الحالة النهائية هي ما
 * أرسله المستخدم بالضبط، بلا منطقٍ يقرّر ما يُضاف وما يُحذف —
 * وذلك المنطق هو ما يخطئ.
 *
 * والمعاملة شرط: بين الحذف والإدراج لحظةٌ لا يتابع فيها شيئاً،
 * وفشلٌ في تلك اللحظة كان سيمحو متابعاته بلا بديل.
 */
async function setFollowed(userId, leagueIds) {
  const client = await db.pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('DELETE FROM user_leagues WHERE user_id = $1', [userId]);
    if (leagueIds.length) {
      await client.query(
        `INSERT INTO user_leagues (user_id, league_id)
         SELECT $1, unnest($2::int[])
         ON CONFLICT DO NOTHING`,
        [userId, leagueIds]
      );
    }
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

// ─────────────── توقّع البطل ───────────────

/** كم مباراة انتهت من هذا الموسم، ومن كم. */
async function seasonProgress(leagueId, season) {
  const { rows } = await db.query(
    `SELECT COUNT(*) FILTER (WHERE status = 'finished')::int AS played,
            COUNT(*)::int                                   AS total
       FROM fixtures
      WHERE league_id = $1 AND season = $2`,
    [leagueId, season]
  );
  return rows[0];
}

async function upsert({ userId, leagueId, season, teamId, award }) {
  const { rows } = await db.query(
    `INSERT INTO champion_picks (user_id, league_id, season, team_id, award)
     VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (user_id, league_id, season) DO UPDATE SET
       team_id   = EXCLUDED.team_id,
       award     = EXCLUDED.award,
       picked_at = now()
     WHERE champion_picks.settled_at IS NULL
     RETURNING league_id, season, team_id, award, picked_at`,
    [userId, leagueId, season, teamId, award]
  );
  return rows[0] ?? null; // null = سُوّي فعلاً فرُفض التغيير
}

/** رهانات هذا المستخدم مع أسماء الأندية — للعرض. */
async function findMine(userId) {
  const { rows } = await db.query(
    `SELECT c.league_id, c.season, c.team_id, c.award, c.points, c.settled_at,
            COALESCE(t.name_ar, t.name_en) AS team_name,
            t.logo_url                     AS team_logo
       FROM champion_picks c
       JOIN teams t ON t.id = c.team_id
      WHERE c.user_id = $1`,
    [userId]
  );
  return rows;
}

/**
 * دوريات انتهت مبارياتها ولم يُسجَّل بطلها بعد.
 *
 * "انتهت" = لا مباراة غير منتهية في الموسم، لا "مرّ تاريخ ما":
 * المباراة المؤجّلة تُلعب بعد نهاية الجدول المعلن أحياناً، وحسم
 * البطل قبلها قد يعطي الكأس لغير صاحبها.
 */
async function leaguesAwaitingChampion() {
  const { rows } = await db.query(
    `SELECT l.id AS league_id, l.season
       FROM leagues l
      WHERE l.in_app
        AND EXISTS (
              SELECT 1 FROM fixtures f
               WHERE f.league_id = l.id AND f.season = l.season)
        AND NOT EXISTS (
              SELECT 1 FROM fixtures f
               WHERE f.league_id = l.id AND f.season = l.season
                 AND f.status <> 'finished')
        AND NOT EXISTS (
              SELECT 1 FROM league_champions c
               WHERE c.league_id = l.id AND c.season = l.season)`
  );
  return rows;
}

async function recordChampion({ leagueId, season, teamId, source }) {
  await db.query(
    `INSERT INTO league_champions (league_id, season, team_id, source)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (league_id, season) DO UPDATE SET
       team_id = EXCLUDED.team_id, decided_at = now(), source = EXCLUDED.source`,
    [leagueId, season, teamId, source || 'auto']
  );
}

/** يمنح الجائزة لمن أصاب وصفراً لمن أخطأ. يرجع عدد ما سُوّي. */
async function settleLeague({ leagueId, season, teamId }) {
  const { rowCount } = await db.query(
    `UPDATE champion_picks
        SET points = CASE WHEN team_id = $3 THEN award ELSE 0 END,
            settled_at = now()
      WHERE league_id = $1 AND season = $2 AND settled_at IS NULL`,
    [leagueId, season, teamId]
  );
  return rowCount;
}

module.exports = {
  followedIds, setFollowed,
  seasonProgress, upsert, findMine,
  leaguesAwaitingChampion, recordChampion, settleLeague,
};
