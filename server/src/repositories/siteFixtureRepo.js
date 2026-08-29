// siteFixtureRepo — مباريات الموقع العام.
//
// ملف مستقل عن fixtureRepo لأن السؤالين مختلفان لا لأن الكود مكرر:
// التطبيق يسأل "ما الذي أستطيع توقّعه؟" (قيد in_app)، والموقع يسأل
// "ماذا يُلعب اليوم؟" عبر البطولات الثماني (قيد enabled). دمجهما
// في ملف بعلَم يعني أن كل استعلام جديد يحمل سؤالاً عن أي منهما هو،
// وأن نسيان العلَم يسرّب دوريات للتطبيق بصمت.
//
// والموقع يعرض اسم الدوري وشعاره أيضاً — التطبيق لا يحتاجهما لأن
// كل مبارياته من دوري واحد.
const db = require('../config/db');

const COLUMNS = `
  f.id,
  f.league_id,
  l.sort_order        AS league_order,
  COALESCE(l.name_ar, l.name_en) AS league_name,
  l.logo_url          AS league_logo,
  f.round,
  f.kickoff_at,
  f.status,
  f.elapsed,
  f.goals_home,
  f.goals_away,
  COALESCE(ht.name_ar, ht.name_en) AS home_team_name,
  ht.logo_url         AS home_team_logo,
  COALESCE(at.name_ar, at.name_en) AS away_team_name,
  at.logo_url         AS away_team_logo
`;

const FROM = `
  FROM fixtures f
  JOIN leagues l ON l.id = f.league_id AND l.enabled
  JOIN teams ht ON ht.id = f.home_team_id
  JOIN teams at ON at.id = f.away_team_id
`;

/**
 * مباريات يوم واحد بتوقيت الرياض.
 *
 * "اليوم" في تطبيق عربي هو اليوم في الرياض لا في UTC: مباراة
 * أوروبية تنطلق 22:00 بتوقيت الرياض تقع بعد منتصف ليل UTC، فحساب
 * اليوم بـ UTC ينقلها لليوم التالي ويُفرغ قائمة الليلة.
 *
 * الترتيب: الدوري أولاً (روشن ثم الأبطال ثم الأوروبية) والوقت
 * ثانياً — القارئ يبحث عن دوريه لا عن أبكر مباراة.
 */
async function byDate(date) {
  const { rows } = await db.query(
    `SELECT ${COLUMNS} ${FROM}
      WHERE (f.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date = $1::date
      ORDER BY l.sort_order, f.kickoff_at, f.id`,
    [date]
  );
  return rows;
}

/** الأيام التي فيها مباريات، حول يوم معيّن — لشريط التنقل. */
async function daysAround(date, back = 3, forward = 3) {
  const { rows } = await db.query(
    `SELECT to_char((f.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date, 'YYYY-MM-DD') AS day,
            count(*)::int AS count
       ${FROM}
      WHERE (f.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date
              BETWEEN $1::date - $2::int AND $1::date + $3::int
      GROUP BY 1
      ORDER BY 1`,
    [date, back, forward]
  );
  return rows;
}

/** المباريات الجارية الآن — للشريط الحيّ في الصفحة الرئيسية. */
async function live() {
  const { rows } = await db.query(
    `SELECT ${COLUMNS} ${FROM}
      WHERE f.status = 'live'
      ORDER BY l.sort_order, f.kickoff_at`
  );
  return rows;
}

/**
 * ملخّص الصفحة الرئيسية: ما يُلعب الآن، وإلا فأقرب ما هو قادم.
 *
 * سؤال واحد بجوابين لا استعلامان: الصفحة الرئيسية تريد "أرني شيئاً
 * حياً"، ومعنى ذلك يتغيّر بتغيّر الساعة لا بتغيّر الصفحة.
 */
async function homeStrip(limit = 6) {
  const running = await live();
  if (running.length) return { mode: 'live', fixtures: running.slice(0, limit) };

  const { rows } = await db.query(
    `SELECT ${COLUMNS} ${FROM}
      WHERE f.status = 'scheduled' AND f.kickoff_at >= now()
      ORDER BY f.kickoff_at, l.sort_order
      LIMIT $1`,
    [limit]
  );
  return { mode: 'upcoming', fixtures: rows };
}

module.exports = { byDate, daysAround, live, homeStrip };
