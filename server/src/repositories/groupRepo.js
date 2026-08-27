// groupRepo — تعامل جدولي groups و group_members مع القاعدة.
const db = require('../config/db');

// الإنشاء والانضمام في معاملة واحدة: قروب بلا عضوية مالكه حالة
// نصف مكتملة يجب ألا توجد ولو للحظة.
async function create({ name, inviteCode, ownerId }) {
  const client = await db.pool.connect();
  try {
    await client.query('BEGIN');
    const { rows } = await client.query(
      `INSERT INTO groups (name, invite_code, owner_id)
       VALUES ($1, $2, $3)
       RETURNING id, name, invite_code, owner_id, created_at`,
      [name, inviteCode, ownerId]
    );
    await client.query(
      `INSERT INTO group_members (group_id, user_id) VALUES ($1, $2)`,
      [rows[0].id, ownerId]
    );
    await client.query('COMMIT');
    return rows[0];
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

async function findByCode(inviteCode) {
  const { rows } = await db.query(
    `SELECT id, name, invite_code, owner_id FROM groups WHERE invite_code = $1`,
    [inviteCode]
  );
  return rows[0] ?? null;
}

async function findById(id) {
  const { rows } = await db.query(
    `SELECT g.id, g.name, g.invite_code, g.owner_id, g.created_at,
            (SELECT COUNT(*) FROM group_members gm WHERE gm.group_id = g.id)::int AS members_count
     FROM groups g WHERE g.id = $1`,
    [id]
  );
  return rows[0] ?? null;
}

// قروبات المستخدم مع عدد الأعضاء وهل هو المالك.
async function findMine(userId) {
  const { rows } = await db.query(
    `SELECT g.id, g.name, g.invite_code, g.created_at,
            (g.owner_id = $1) AS is_owner,
            (SELECT COUNT(*) FROM group_members m WHERE m.group_id = g.id)::int AS members_count
     FROM group_members gm
     JOIN groups g ON g.id = gm.group_id
     WHERE gm.user_id = $1
     ORDER BY gm.joined_at DESC`,
    [userId]
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

// ترتيب أعضاء القروب: نفس منطق الصدارة العامة لكن مقصوراً على
// الأعضاء. LEFT JOIN حتى يظهر العضو الجديد بلا توقعات بصفر نقاط —
// اختفاؤه من القائمة سيبدو خطأً لأصحابه.
async function leaderboard(groupId) {
  const { rows } = await db.query(
    `SELECT u.id AS user_id,
            COALESCE(u.display_name, 'مشجع') AS display_name,
            u.avatar_url,
            u.favorite_team_id,
            ft.logo_url AS favorite_team_logo,
            COALESCE(SUM(p.points), 0)::int AS total_points,
            COUNT(p.points)::int AS settled_predictions,
            gm.joined_at
     FROM group_members gm
     JOIN users u ON u.id = gm.user_id
     LEFT JOIN teams ft ON ft.id = u.favorite_team_id
     LEFT JOIN predictions p ON p.user_id = u.id
     WHERE gm.group_id = $1
     GROUP BY u.id, ft.logo_url, gm.joined_at
     ORDER BY total_points DESC, gm.joined_at ASC`,
    [groupId]
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
    `SELECT g.id, g.name, g.invite_code, g.created_at,
            u.email AS owner_email,
            (SELECT COUNT(*) FROM group_members m WHERE m.group_id = g.id)::int AS members_count
     FROM groups g
     JOIN users u ON u.id = g.owner_id
     ${where}
     ORDER BY g.created_at DESC
     LIMIT 200`,
    params
  );
  return rows;
}

module.exports = {
  create, findByCode, findById, findMine, isMember, memberCount,
  addMember, removeMember, leaderboard, fixturePredictions,
  remove, countOwnedBy, adminList,
};
