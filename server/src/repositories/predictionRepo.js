// predictionRepo — تعامل جدول predictions مع القاعدة.
const db = require('../config/db');

// حفظ/تعديل توقع. قيد UNIQUE(user_id, fixture_id) يجعل التعديل
// قبل انطلاق المباراة تحديثاً للصف نفسه.
// الشرط WHERE settled_at IS NULL في جهة UPDATE حزام أمان أخير:
// حتى لو أخطأت طبقة أعلى، توقع محتسب لا يُعدَّل أبداً.
async function upsert({ userId, fixtureId, predHome, predAway }) {
  const { rows } = await db.query(
    `INSERT INTO predictions (user_id, fixture_id, pred_home, pred_away)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (user_id, fixture_id) DO UPDATE SET
       pred_home  = EXCLUDED.pred_home,
       pred_away  = EXCLUDED.pred_away,
       updated_at = now()
     WHERE predictions.settled_at IS NULL
     RETURNING id, fixture_id, pred_home, pred_away, points, created_at, updated_at`,
    [userId, fixtureId, predHome, predAway]
  );
  return rows[0] ?? null; // null = الصف محتسب فرفض التحديث
}

// توقعات المستخدم مع معلومات المباراة للعرض مباشرة في التطبيق.
async function findMine(userId) {
  const { rows } = await db.query(
    `SELECT p.id, p.fixture_id, p.pred_home, p.pred_away, p.points, p.settled_at,
            f.kickoff_at, f.status, f.goals_home, f.goals_away, f.round,
            COALESCE(ht.name_ar, ht.name_en) AS home_team_name,
            COALESCE(at.name_ar, at.name_en) AS away_team_name
     FROM predictions p
     JOIN fixtures f ON f.id = p.fixture_id
     JOIN teams ht ON ht.id = f.home_team_id
     JOIN teams at ON at.id = f.away_team_id
     WHERE p.user_id = $1
     ORDER BY f.kickoff_at DESC`,
    [userId]
  );
  return rows;
}

// كل التوقعات غير المحتسبة لمباريات انتهت — مدخلات الاحتساب.
async function findUnsettled() {
  const { rows } = await db.query(
    `SELECT p.id, p.pred_home, p.pred_away,
            f.goals_home, f.goals_away
     FROM predictions p
     JOIN fixtures f ON f.id = p.fixture_id
     WHERE p.settled_at IS NULL
       AND f.status = 'finished'
       AND f.goals_home IS NOT NULL AND f.goals_away IS NOT NULL`
  );
  return rows;
}

async function settle(id, points) {
  await db.query(
    `UPDATE predictions SET points = $2, settled_at = now() WHERE id = $1`,
    [id, points]
  );
}

// لوحة الصدارة: مجموع نقاط كل مستخدم.
// نحسب المجموع من التوقعات في كل مرة بدل تخزين عمود points في
// users: مصدر حقيقة واحد، لا يمكن أن ينحرف المجموع عن التفاصيل
// (لو أعاد الأدمن الاحتساب مثلاً). عند مئات آلاف المستخدمين نعيد
// النظر — ليس اليوم.
async function leaderboard(limit = 50) {
  const { rows } = await db.query(
    `SELECT u.id AS user_id,
            COALESCE(u.display_name, 'مشجع') AS display_name,
            u.avatar_url,
            u.favorite_team_id,
            ft.logo_url AS favorite_team_logo,
            COALESCE(SUM(p.points), 0)::int AS total_points,
            COUNT(p.points)::int AS settled_predictions
     FROM users u
     JOIN predictions p ON p.user_id = u.id
     LEFT JOIN teams ft ON ft.id = u.favorite_team_id
     GROUP BY u.id, ft.logo_url
     ORDER BY total_points DESC, settled_predictions ASC
     LIMIT $1`,
    [limit]
  );
  return rows;
}

module.exports = { upsert, findMine, findUnsettled, settle, leaderboard };
