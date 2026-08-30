// fixtureRepo — كل تعامل جدولي fixtures و fixture_events مع القاعدة.
const db = require('../config/db');

// أعمدة المباراة المشتركة لكل الاستعلامات.
const FIXTURE_COLUMNS = `
  f.id, f.league_id, f.season, f.round, f.kickoff_at, f.status,
  f.goals_home, f.goals_away,
  f.home_team_id,
  COALESCE(ht.name_ar, ht.name_en) AS home_team_name,
  ht.logo_url AS home_team_logo,
  f.away_team_id,
  COALESCE(at.name_ar, at.name_en) AS away_team_name,
  at.logo_url AS away_team_logo
`;

// نضم جدول الفرق مرتين (مرة للمضيف ومرة للضيف) بأسماء مستعارة
// ht و at، مع التدهور اللطيف للاسم العربي عبر COALESCE أعلاه.
//
// وJOIN مع leagues بقيد in_app: هذا الملف يخدم التطبيق وحده (راجع
// من يستدعيه: routes/fixtures و predictions و groups)، والتطبيق
// لعبة توقّعات حول دوري روشن. الموقع العام يعرض ثماني بطولات
// ويستعلم من siteFixtureRepo بقيد enabled بدلاً منه.
//
// القيد هنا في المصدر الواحد لا في كل استعلام: إضافته يدوياً في
// ستة استعلامات تعني أن السابع سينساه، ويظهر في التطبيق دوري
// إسباني لا يُتوقَّع عليه — وهو عطل يبدو ميزة فلا يُبلَّغ عنه.
const FIXTURE_FROM = `
  FROM fixtures f
  JOIN teams ht ON ht.id = f.home_team_id
  JOIN teams at ON at.id = f.away_team_id
  JOIN leagues l ON l.id = f.league_id AND l.in_app
`;

const FIXTURE_SELECT = `SELECT ${FIXTURE_COLUMNS} ${FIXTURE_FROM}`;

// نفس الشكل زائد الدقيقة، لاستعلامات تبويب "مباشر" وحده.
//
// لماذا شكلان بدل إضافة elapsed لـ FIXTURE_SELECT مباشرة؟
// شكل /api/fixtures يستهلكه التطبيق الآن، وتوسيعه لأجل حقل لا
// يعني قائمة المباريات في شيء (دقيقة اللعب معناها الوحيد أثناء
// اللعب) تغيير عقد قائم بلا مقابل. والفصل هنا لا يكرر شيئاً:
// الأعمدة والـ JOIN مصدرهما ثابت واحد، فلا يمكن أن ينحرف الشكلان.
const FIXTURE_SELECT_LIVE = `SELECT ${FIXTURE_COLUMNS}, f.elapsed ${FIXTURE_FROM}`;

async function upsertMany(fixtures) {
  const client = await db.pool.connect();
  try {
    await client.query('BEGIN');
    for (const f of fixtures) {
      await client.query(
        `INSERT INTO fixtures
           (id, league_id, season, home_team_id, away_team_id,
            kickoff_at, status, goals_home, goals_away, elapsed, round,
            venue_name, venue_city, referee, ht_home, ht_away,
            pen_home, pen_away, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11,
                 $12, $13, $14, $15, $16, $17, $18, now())
         ON CONFLICT (id) DO UPDATE SET
           kickoff_at = EXCLUDED.kickoff_at,  -- قد تتأجل المباراة لموعد جديد
           status     = EXCLUDED.status,
           goals_home = EXCLUDED.goals_home,
           goals_away = EXCLUDED.goals_away,
           -- الدقيقة في جهة UPDATE وليست في INSERT فقط: هذا الصف
           -- يُدخَل مرة واحدة (قبل الموسم، بلا دقيقة) ثم يُحدَّث في
           -- كل نبضة مباشرة. لو نسيناها هنا لتجمّد العداد على 0'
           -- طوال المباراة — وهو أسوأ من ألا نعرض دقيقة أصلاً،
           -- لأن الخطأ يبدو كمعلومة صحيحة.
           elapsed    = EXCLUDED.elapsed,
           round      = EXCLUDED.round,
           -- الملعب والحكم قد يتغيّران قبل المباراة (نقل، تعيين
           -- جديد)، ونتيجة الشوط الأول تُملأ عند نهايته. كلها في
           -- جهة UPDATE لنفس سبب elapsed.
           venue_name = EXCLUDED.venue_name,
           venue_city = EXCLUDED.venue_city,
           referee    = EXCLUDED.referee,
           ht_home    = EXCLUDED.ht_home,
           ht_away    = EXCLUDED.ht_away,
           pen_home   = EXCLUDED.pen_home,
           pen_away   = EXCLUDED.pen_away,
           updated_at = now()`,
        [f.id, f.league_id, f.season, f.home_team_id, f.away_team_id,
         f.kickoff_at, f.status, f.goals_home, f.goals_away, f.elapsed ?? null, f.round,
         f.venue_name ?? null, f.venue_city ?? null, f.referee ?? null,
         f.ht_home ?? null, f.ht_away ?? null,
         f.pen_home ?? null, f.pen_away ?? null]
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

// مباريات يوم معيّن.
//
// نقطة مهمة: kickoff_at مخزّن بتوقيت UTC، لكن المستخدم السعودي حين
// يسأل عن "مباريات اليوم" يقصد اليوم بتوقيت الرياض. مباراة الساعة
// 00:30 فجر السبت بتوقيت الرياض هي مساء الجمعة بتوقيت UTC —
// المقارنة بـ UTC سترجعها في اليوم الخطأ. لذلك نحوّل للمنطقة
// الزمنية Asia/Riyadh قبل قصّ التاريخ.
async function findByDate(date) {
  const { rows } = await db.query(
    `${FIXTURE_SELECT}
     WHERE (f.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date = $1
     ORDER BY f.kickoff_at`,
    [date]
  );
  return rows;
}

// المباريات القادمة: المجدولة التي لم يحن موعدها بعد.
async function findUpcoming(limit = 20) {
  const { rows } = await db.query(
    `${FIXTURE_SELECT}
     WHERE f.status = 'scheduled' AND f.kickoff_at >= now()
     ORDER BY f.kickoff_at
     LIMIT $1`,
    [limit]
  );
  return rows;
}

// ── استعلامات تبويب "مباشر" ─────────────────────────────────────

// المباريات الجارية الآن.
async function findLive() {
  const { rows } = await db.query(
    `${FIXTURE_SELECT_LIVE}
     WHERE f.status = 'live'
     ORDER BY f.kickoff_at`
  );
  return rows;
}

// أقرب مباراة قادمة — واحدة فقط.
//
// وجودها في تبويب "مباشر" ليس حشواً: المباريات تُلعب ساعات معدودة
// في الأسبوع، فالتبويب فارغ في أغلب الأوقات. "لا شيء الآن، والقادم
// بعد ١٧ ساعة" جواب مفيد، أما الشاشة الفارغة فتبدو عطلاً.
async function findNextKickoff() {
  const { rows } = await db.query(
    `${FIXTURE_SELECT_LIVE}
     WHERE f.status = 'scheduled' AND f.kickoff_at > now()
     ORDER BY f.kickoff_at
     LIMIT 1`
  );
  return rows[0] ?? null;
}

// مباريات انتهت اليوم — نتائج الأمس القريب التي ما زالت حديثاً.
//
// "اليوم" هنا يوم الرياض لا يوم UTC، لنفس السبب المشروح في
// findByDate: مباراة الساعة 00:30 بتوقيت الرياض ما زالت "مباراة
// الليلة" عند المستخدم بينما UTC نقلها ليوم آخر.
// والتصفية على kickoff_at وليست على وقت انتهاء (لا نخزّنه): فارق
// الساعتين بين الانطلاق والنهاية لا يغيّر اليوم إلا في حالة نادرة
// جداً، وتخزين عمود ثالث لأجلها مبالغة.
async function findFinishedToday() {
  const { rows } = await db.query(
    `${FIXTURE_SELECT_LIVE}
     WHERE f.status = 'finished'
       AND (f.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date
         = (now() AT TIME ZONE 'Asia/Riyadh')::date
     ORDER BY f.kickoff_at`
  );
  return rows;
}

async function findById(id) {
  const { rows } = await db.query(
    `${FIXTURE_SELECT} WHERE f.id = $1`,
    [id]
  );
  return rows[0] ?? null; // null أوضح من undefined للمستدعي
}

// استبدال أحداث مباراة بالكامل (حذف ثم إدخال).
//
// لماذا الاستبدال وليس UPSERT؟ المزود لا يعطي الأحداث معرّفات،
// فلا نستطيع معرفة "هذا الحدث موجود عندنا مسبقاً". كما أن الحدث قد
// يُلغى (هدف ملغى بالـ VAR يختفي من القائمة). أبسط طريقة صحيحة:
// قائمة المزود هي الحقيقة الكاملة، نستبدل ما عندنا بها كل مرة.
async function replaceEvents(fixtureId, events) {
  const client = await db.pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('DELETE FROM fixture_events WHERE fixture_id = $1', [fixtureId]);
    for (const e of events) {
      await client.query(
        `INSERT INTO fixture_events
           (fixture_id, type, detail, minute, player_id, assist_id, team_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [e.fixture_id, e.type, e.detail, e.minute, e.player_id, e.assist_id, e.team_id]
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

async function findEvents(fixtureId) {
  // LEFT JOIN وليس JOIN: الحدث قد يخص فريقاً/لاعباً لم نخزنه بعد،
  // ويجب أن يظهر الحدث رغم ذلك (باسم فريق NULL) بدل أن يختفي.
  const { rows } = await db.query(
    // e.id::int — عمود BIGSERIAL نوعه bigint، ومكتبة pg ترجعه نصاً
    // ("1" بدل 1) لأن bigint قد يتجاوز أرقام JavaScript الآمنة.
    // أعداد الأحداث لن تقترب من ذلك الحد، فنحوّله لرقم عادي.
    `SELECT e.id::int AS id, e.type, e.detail, e.minute,
            e.player_id, e.assist_id, e.team_id,
            COALESCE(t.name_ar, t.name_en) AS team_name
     FROM fixture_events e
     LEFT JOIN teams t ON t.id = e.team_id
     WHERE e.fixture_id = $1
     ORDER BY e.minute, e.id`,
    [fixtureId]
  );
  return rows;
}

/**
 * أقرب مباراة قادمة لهذا النادي — مفتوحة للتوقّع.
 *
 * FIXTURE_SELECT مقيّد بـ in_app أصلاً، فالنتيجة قابلة للتوقّع
 * بحكم الاستعلام لا بفحص إضافي بعده.
 */
async function nextForTeam(teamId) {
  const { rows } = await db.query(
    `${FIXTURE_SELECT}
     WHERE f.status = 'scheduled'
       AND f.kickoff_at > now()
      AND (f.home_team_id = $1 OR f.away_team_id = $1)
     ORDER BY f.kickoff_at ASC
     LIMIT 1`,
    [teamId]
  );
  return rows[0] ?? null;
}

module.exports = {
  nextForTeam,
  upsertMany,
  findByDate,
  findUpcoming,
  findLive,
  findNextKickoff,
  findFinishedToday,
  findById,
  replaceEvents,
  findEvents,
};
