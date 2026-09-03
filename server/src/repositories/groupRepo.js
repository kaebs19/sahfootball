// groupRepo — تعامل جدولي groups و group_members مع القاعدة.
const db = require('../config/db');

// أعمدة المجلس كما تخرج من هذه الطبقة، في مكان واحد: أربعة
// استعلامات كانت تعيد المجلس بأشكال متقاربة، وإضافة عمود (الدوري،
// العلنية) كانت ستُنسى في أحدها فيصل المجلس ناقصاً من باب دون باب.
//
// شعار الدوري مسارنا لا عمود leagues.logo_url — ذلك العمود فارغ
// لكل الدوريات (راجع routes/leagues)، والمسار يقدّم الملف المحلي
// ويحوّل إلى المزود عند غيابه.
//
// is_public مشتق من join_policy لا عمود: الواجهات تقرؤه منذ 024،
// وحقيقة واحدة في عمود واحد (راجع الهجرة 025).
const GROUP_COLUMNS = `
  g.id, g.name, g.invite_code, g.owner_id, g.join_policy, g.league_id, g.image_url, g.created_at,
  (g.join_policy <> 'code') AS is_public,
  COALESCE(l.name_ar, l.name_en) AS league_name,
  CASE WHEN g.league_id IS NULL THEN NULL
       ELSE '/logos/league-' || g.league_id || '.png' END AS league_logo,
  (SELECT COUNT(*) FROM group_members m WHERE m.group_id = g.id)::int AS members_count,
  (SELECT COUNT(*) FROM group_join_requests r WHERE r.group_id = g.id)::int AS pending_requests`;

const GROUP_FROM = `FROM groups g LEFT JOIN leagues l ON l.id = g.league_id`;

// الإنشاء والانضمام في معاملة واحدة: قروب بلا عضوية مالكه حالة
// نصف مكتملة يجب ألا توجد ولو للحظة.
async function create({ name, inviteCode, ownerId, joinPolicy = 'code', leagueId = null }) {
  const client = await db.pool.connect();
  try {
    await client.query('BEGIN');
    const { rows } = await client.query(
      `INSERT INTO groups (name, invite_code, owner_id, join_policy, league_id)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id`,
      [name, inviteCode, ownerId, joinPolicy, leagueId]
    );
    await client.query(
      `INSERT INTO group_members (group_id, user_id) VALUES ($1, $2)`,
      [rows[0].id, ownerId]
    );
    await client.query('COMMIT');
    return findById(rows[0].id);
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

// تعديل إعدادات المجلس. الحقول بأسماء ثابتة لا من الطلب: أسماء
// الأعمدة لا تُمرَّر كمعاملات في SQL، فقائمة مغلقة هي الحماية.
async function update(id, { name, joinPolicy, leagueId, imageUrl }) {
  const sets = [];
  const params = [];
  if (name !== undefined) { params.push(name); sets.push(`name = $${params.length}`); }
  if (imageUrl !== undefined) { params.push(imageUrl); sets.push(`image_url = $${params.length}`); }
  if (joinPolicy !== undefined) { params.push(joinPolicy); sets.push(`join_policy = $${params.length}`); }
  if (leagueId !== undefined) { params.push(leagueId); sets.push(`league_id = $${params.length}`); }
  if (sets.length === 0) return findById(id);
  params.push(id);
  await db.query(`UPDATE groups SET ${sets.join(', ')} WHERE id = $${params.length}`, params);
  return findById(id);
}

async function findByCode(inviteCode) {
  const { rows } = await db.query(
    `SELECT ${GROUP_COLUMNS} ${GROUP_FROM} WHERE g.invite_code = $1`,
    [inviteCode]
  );
  return rows[0] ?? null;
}

async function findById(id) {
  const { rows } = await db.query(
    `SELECT ${GROUP_COLUMNS} ${GROUP_FROM} WHERE g.id = $1`,
    [id]
  );
  return rows[0] ?? null;
}

// قروبات المستخدم مع عدد الأعضاء ودوره فيها.
//
// is_owner يبقى إلى جانب role: الموقع يقرأ الأول منذ نسخته الأولى،
// والتطبيق يقرأ الثاني — وإسقاط أحدهما يكسر باباً بلا مكسب.
async function findMine(userId) {
  const { rows } = await db.query(
    `SELECT ${GROUP_COLUMNS},
            (g.owner_id = $1) AS is_owner,
            CASE WHEN g.owner_id = $1 THEN 'owner' ELSE gm.role END AS role
     FROM group_members gm
     JOIN groups g ON g.id = gm.group_id
     LEFT JOIN leagues l ON l.id = g.league_id
     WHERE gm.user_id = $1
     ORDER BY gm.joined_at DESC`,
    [userId]
  );
  return rows;
}

// المجالس العامة للاستكشاف — الأكثر أعضاءً أولاً: مجلسٌ فيه ناس
// أدعى للانضمام من مجلس فارغ، والبحث بالاسم يقفز فوق الترتيب.
// is_member وhas_request للطالب كي يعرض الزر الصحيح («انضم» أو
// «اطلب» أو «بانتظار الموافقة» أو «عضو») بلا مقارنة قوائم في العميل.
async function findPublic({ search = '', limit = 50, userId = null } = {}) {
  const params = [userId, limit];
  let where = `WHERE g.join_policy <> 'code'`;
  if (search) {
    params.push(`%${search}%`);
    where += ` AND g.name ILIKE $${params.length}`;
  }
  const { rows } = await db.query(
    `SELECT ${GROUP_COLUMNS},
            EXISTS (SELECT 1 FROM group_members m
                     WHERE m.group_id = g.id AND m.user_id = $1) AS is_member,
            EXISTS (SELECT 1 FROM group_join_requests r
                     WHERE r.group_id = g.id AND r.user_id = $1) AS has_request
     ${GROUP_FROM}
     ${where}
     ORDER BY members_count DESC, g.created_at DESC
     LIMIT $2`,
    params
  );
  return rows;
}

async function isMember(groupId, userId) {
  const { rows } = await db.query(
    `SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2`,
    [groupId, userId]
  );
  return rows.length > 0;
}

/**
 * دور المستخدم في المجلس: 'owner' | 'moderator' | 'member' | null.
 *
 * المالك يُقرأ من groups.owner_id لا من group_members.role — مصدر
 * واحد للملكية، فنقلُها (عند حذف حساب المالك مثلاً) يحدّث عموداً
 * واحداً ولا يحتاج تصحيح صفّ العضوية معه.
 */
async function memberRole(groupId, userId) {
  const { rows } = await db.query(
    `SELECT CASE WHEN g.owner_id = $2 THEN 'owner' ELSE gm.role END AS role
       FROM group_members gm
       JOIN groups g ON g.id = gm.group_id
      WHERE gm.group_id = $1 AND gm.user_id = $2`,
    [groupId, userId]
  );
  return rows[0]?.role ?? null;
}

async function memberCount(groupId) {
  const { rows } = await db.query(
    `SELECT COUNT(*)::int AS n FROM group_members WHERE group_id = $1`,
    [groupId]
  );
  return rows[0].n;
}

async function addMember(groupId, userId) {
  await db.query(
    `INSERT INTO group_members (group_id, user_id) VALUES ($1, $2)`,
    [groupId, userId]
  );
}

async function removeMember(groupId, userId) {
  await db.query(
    `DELETE FROM group_members WHERE group_id = $1 AND user_id = $2`,
    [groupId, userId]
  );
}

// ── طلبات الانضمام ──────────────────────────────────────────────

async function addRequest(groupId, userId) {
  await db.query(
    `INSERT INTO group_join_requests (group_id, user_id) VALUES ($1, $2)
     ON CONFLICT DO NOTHING`,
    [groupId, userId]
  );
}

async function removeRequest(groupId, userId) {
  const { rowCount } = await db.query(
    `DELETE FROM group_join_requests WHERE group_id = $1 AND user_id = $2`,
    [groupId, userId]
  );
  return rowCount > 0;
}

async function hasRequest(groupId, userId) {
  const { rows } = await db.query(
    `SELECT 1 FROM group_join_requests WHERE group_id = $1 AND user_id = $2`,
    [groupId, userId]
  );
  return rows.length > 0;
}

// الطلبات المعلّقة على مجلس، الأقدم أولاً — من انتظر أكثر يُجاب أولاً.
async function requests(groupId) {
  const { rows } = await db.query(
    `SELECT u.id AS user_id,
            COALESCE(u.display_name, 'مشجع') AS display_name,
            u.avatar_url,
            r.created_at AS requested_at
       FROM group_join_requests r
       JOIN users u ON u.id = r.user_id
      WHERE r.group_id = $1
      ORDER BY r.created_at ASC`,
    [groupId]
  );
  return rows;
}

// القبول: حذف الطلب وإدخال العضو في معاملة واحدة — لا لحظة يكون
// فيها الطالب مقبولاً بلا عضوية أو عضواً بطلب معلّق.
async function acceptRequest(groupId, userId) {
  const client = await db.pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `DELETE FROM group_join_requests WHERE group_id = $1 AND user_id = $2`,
      [groupId, userId]
    );
    await client.query(
      `INSERT INTO group_members (group_id, user_id) VALUES ($1, $2)
       ON CONFLICT DO NOTHING`,
      [groupId, userId]
    );
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

/** معرّفات من يدير المجلس: المالك والمشرفون — لإشعارهم بطلب جديد. */
async function managerIds(groupId) {
  const { rows } = await db.query(
    `SELECT gm.user_id
       FROM group_members gm
       JOIN groups g ON g.id = gm.group_id
      WHERE gm.group_id = $1 AND (g.owner_id = gm.user_id OR gm.role = 'moderator')`,
    [groupId]
  );
  return rows.map((r) => r.user_id);
}

async function setRole(groupId, userId, role) {
  await db.query(
    `UPDATE group_members SET role = $3 WHERE group_id = $1 AND user_id = $2`,
    [groupId, userId, role]
  );
}

// قائمة الأعضاء بأدوارهم — للشاشة التي تجيب «من هنا ومن يدير؟».
// المالك أولاً ثم المشرفون ثم الأقدم فالأحدث: الترتيب بالدور هو
// ما يجعل القائمة تُقرأ بلا شارات.
async function members(groupId) {
  const { rows } = await db.query(
    `SELECT u.id AS user_id,
            COALESCE(u.display_name, 'مشجع') AS display_name,
            u.avatar_url,
            ft.logo_url AS favorite_team_logo,
            CASE WHEN g.owner_id = u.id THEN 'owner' ELSE gm.role END AS role,
            gm.joined_at
       FROM group_members gm
       JOIN groups g ON g.id = gm.group_id
       JOIN users u ON u.id = gm.user_id
       LEFT JOIN teams ft ON ft.id = u.favorite_team_id
      WHERE gm.group_id = $1
      ORDER BY (g.owner_id = u.id) DESC, (gm.role = 'moderator') DESC, gm.joined_at ASC`,
    [groupId]
  );
  return rows;
}

// أرقام أعضاء المجلس للموسم وللجولة الأخيرة معاً — والترتيب نفسه
// يُحسب في groupService.rankMembers لا هنا: قواعد التعادل (النقاط ثم
// الأقدمية) تُكتب مرة واحدة في JavaScript وتُطبَّق على الموسم والجولة
// و«قبل الجولة» بالتساوي، بدل ثلاث نسخ من ORDER BY تتباعد.
//
// LEFT JOIN حتى يظهر العضو الجديد بلا توقعات بصفر نقاط — اختفاؤه من
// القائمة سيبدو خطأً لأصحابه.
//
// leagueId هو دوري المجلس: حين يُقيَّد المجلس بدوري تُحسب النقاط من
// مبارياته ورهان بطله وحدهما.
//
// «الجولة الأخيرة» = لكل دوري في النطاق، الجولة التي تحمل آخر مباراة
// احتُسب فيها توقع. مجلس «كل الدوريات» يجمع آخر جولة من كل دوري —
// فلا يُحرم من يلعب الإسباني لأن الإنجليزي لعب بعده بيوم.
// رهان البطل خارج الجولة: هو موسمي بطبيعته.
async function standings(groupId, leagueId = null) {
  const { rows } = await db.query(
    `WITH latest AS (
       SELECT DISTINCT ON (f.league_id) f.league_id, f.round, f.season,
              COALESCE(l.name_ar, l.name_en) AS league_name
         FROM fixtures f
         JOIN leagues l ON l.id = f.league_id
        WHERE f.round IS NOT NULL
          AND ($2::int IS NULL OR f.league_id = $2)
          AND EXISTS (SELECT 1 FROM predictions p
                       WHERE p.fixture_id = f.id AND p.settled_at IS NOT NULL)
        ORDER BY f.league_id, f.kickoff_at DESC
     ),
     season AS (
       -- المصدر view لا جدول predictions: نقاط اللاعب تأتي من
       -- المباريات ورهانات الأبطال معاً، وقراءة الجدول وحده هنا
       -- كانت ستجعل ترتيب المجلس يخالف العرش لنفس الأشخاص.
       SELECT p.user_id,
              COALESCE(SUM(p.points), 0)::int AS points,
              COUNT(*) FILTER (WHERE p.kind = 'match')::int AS settled,
              COUNT(*) FILTER (WHERE p.kind = 'match' AND p.points > 0)::int AS hits
         FROM user_settled_points p
        WHERE ($2::int IS NULL OR p.league_id = $2)
        GROUP BY p.user_id
     ),
     round AS (
       SELECT p.user_id,
              COALESCE(SUM(p.points), 0)::int AS points,
              COUNT(*)::int AS settled,
              COUNT(*) FILTER (WHERE p.points > 0)::int AS hits
         FROM predictions p
         JOIN fixtures f ON f.id = p.fixture_id
         JOIN latest lt ON lt.league_id = f.league_id
                       AND lt.round = f.round AND lt.season = f.season
        WHERE p.settled_at IS NOT NULL
        GROUP BY p.user_id
     )
     SELECT u.id AS user_id,
            COALESCE(u.display_name, 'مشجع') AS display_name,
            u.avatar_url,
            u.favorite_team_id,
            ft.logo_url AS favorite_team_logo,
            CASE WHEN g.owner_id = u.id THEN 'owner' ELSE gm.role END AS role,
            gm.joined_at,
            COALESCE(s.points, 0)  AS season_points,
            COALESCE(s.settled, 0) AS season_settled,
            COALESCE(s.hits, 0)    AS season_hits,
            COALESCE(r.points, 0)  AS round_points,
            COALESCE(r.settled, 0) AS round_settled,
            COALESCE(r.hits, 0)    AS round_hits,
            (SELECT json_agg(json_build_object('league_id', league_id, 'round', round,
                                               'league_name', league_name))
               FROM latest) AS latest_rounds
       FROM group_members gm
       JOIN groups g ON g.id = gm.group_id
       JOIN users u ON u.id = gm.user_id
       LEFT JOIN teams ft ON ft.id = u.favorite_team_id
       LEFT JOIN season s ON s.user_id = u.id
       LEFT JOIN round  r ON r.user_id = u.id
      WHERE gm.group_id = $1
      ORDER BY gm.joined_at ASC`,
    [groupId, leagueId]
  );
  return rows;
}

// توقعات أعضاء القروب على مباراة محددة.
// LEFT JOIN مزدوج المعنى: كل الأعضاء يظهرون، ومن لم يتوقع تكون
// حقول توقعه NULL — التطبيق يعرضه "لم يتوقع" بدل إخفائه.
// شرط p.fixture_id داخل ON وليس WHERE: لو وضعناه في WHERE لتحول
// الـ LEFT JOIN فعلياً إلى JOIN عادي واختفى غير المتوقعين.
async function fixturePredictions(groupId, fixtureId) {
  const { rows } = await db.query(
    `SELECT u.id AS user_id,
            COALESCE(u.display_name, 'مشجع') AS display_name,
            u.avatar_url,
            p.pred_home, p.pred_away, p.points
     FROM group_members gm
     JOIN users u ON u.id = gm.user_id
     LEFT JOIN predictions p ON p.user_id = u.id AND p.fixture_id = $2
     WHERE gm.group_id = $1
     ORDER BY p.points DESC NULLS LAST, display_name`,
    [groupId, fixtureId]
  );
  return rows;
}

async function remove(id) {
  // الأعضاء يُحذفون تلقائياً (ON DELETE CASCADE في الهجرة).
  const { rowCount } = await db.query(`DELETE FROM groups WHERE id = $1`, [id]);
  return rowCount > 0;
}

// كم قروباً يملك المستخدم — لفرض الحد الأقصى.
async function countOwnedBy(userId) {
  const { rows } = await db.query(
    `SELECT COUNT(*)::int AS n FROM groups WHERE owner_id = $1`,
    [userId]
  );
  return rows[0].n;
}

// للوحة التحكم: كل القروبات مع مالكها وعدد أعضائها.
async function adminList(search = '') {
  const params = [];
  let where = '';
  if (search) {
    params.push(`%${search}%`);
    where = `WHERE g.name ILIKE $1 OR u.email ILIKE $1 OR g.invite_code ILIKE $1`;
  }
  const { rows } = await db.query(
    `SELECT g.id, g.name, g.invite_code, g.created_at, g.join_policy,
            (g.join_policy <> 'code') AS is_public,
            COALESCE(l.name_ar, l.name_en) AS league_name,
            u.email AS owner_email,
            (SELECT COUNT(*) FROM group_members m WHERE m.group_id = g.id)::int AS members_count
     FROM groups g
     JOIN users u ON u.id = g.owner_id
     LEFT JOIN leagues l ON l.id = g.league_id
     ${where}
     ORDER BY g.created_at DESC
     LIMIT 200`,
    params
  );
  return rows;
}

module.exports = {
  create, update, findByCode, findById, findMine, findPublic,
  isMember, memberRole, memberCount,
  addMember, removeMember, setRole, members,
  addRequest, removeRequest, hasRequest, requests, acceptRequest, managerIds,
  standings, fixturePredictions,
  remove, countOwnedBy, adminList,
};
