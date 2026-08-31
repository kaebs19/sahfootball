// leagueRepo — كل تعامل جدول leagues مع القاعدة.
const db = require('../config/db');

// الأعمدة التي يخرج بها الدوري من هذه الطبقة. name المشتقة بـ COALESCE
// هي نفس "التدهور اللطيف" المتبع في teamRepo: العربي إن وُجد وإلا
// الإنجليزي، مع إبقاء الحقلين الخامين لأن اللوحة تحتاج معرفة ما تُرجم.
const LEAGUE_COLUMNS = `
  l.id,
  COALESCE(l.name_ar, l.name_en) AS name,
  l.name_en,
  l.name_ar,
  l.country,
  l.logo_url,
  l.season,
  l.enabled,
  l.in_app,
  l.sort_order,
  l.last_synced_at,
  l.created_at
`;

// قائمة اللوحة: كل دوري مع حجمه الفعلي عندنا.
//
// fixtures_count يعدّ كل مواسم الدوري وليس الموسم الحالي فقط —
// الرقم يجيب سؤال الأدمن "هل لهذا الدوري بيانات عندي؟" (وهو نفس
// السؤال الذي يمنع الحذف في مسار DELETE).
//
// teams_count مشتق ولا يُخزَّن: لا يوجد جدول يربط فريقاً بدوري،
// فالانتماء نستنتجه من ظهور الفريق في مباريات ذلك الدوري. UNION
// (وليس UNION ALL) يوحّد المضيف والضيف ويحذف التكرار في خطوة واحدة.
async function findAll() {
  const { rows } = await db.query(
    `SELECT ${LEAGUE_COLUMNS},
            (SELECT COUNT(*) FROM fixtures f WHERE f.league_id = l.id)::int AS fixtures_count,
            (SELECT COUNT(*) FROM (
               SELECT home_team_id AS team_id FROM fixtures WHERE league_id = l.id
               UNION
               SELECT away_team_id            FROM fixtures WHERE league_id = l.id
             ) t)::int AS teams_count
     FROM leagues l
     ORDER BY l.sort_order, l.name_en`
  );
  return rows;
}

// الدوريات المفعّلة فقط — هذه هي التي تدور عليها المزامنة، فترتيبها
// يحدد من يُزامن أولاً: عند نفاد الحصة في منتصف الدورة يكون الدوري
// الأهم (sort_order أصغر) قد زُومن مسبقاً.
async function findEnabled() {
  const { rows } = await db.query(
    `SELECT ${LEAGUE_COLUMNS}
     FROM leagues l
     WHERE l.enabled
     ORDER BY l.sort_order, l.name_en`
  );
  return rows;
}

async function findById(id) {
  const { rows } = await db.query(
    `SELECT ${LEAGUE_COLUMNS} FROM leagues l WHERE l.id = $1`,
    [id]
  );
  return rows[0] ?? null;
}

async function create({ id, name_en, name_ar, country, logo_url, season, sort_order }) {
  const { rows } = await db.query(
    `INSERT INTO leagues (id, name_en, name_ar, country, logo_url, season, sort_order)
     VALUES ($1, $2, $3, $4, $5, $6, COALESCE($7, 0))
     RETURNING id, COALESCE(name_ar, name_en) AS name, name_en, name_ar,
               country, logo_url, season, enabled, sort_order, last_synced_at, created_at`,
    [id, name_en, name_ar ?? null, country ?? null, logo_url ?? null, season, sort_order ?? null]
  );
  return rows[0];
}

// الأعمدة المسموح تعديلها من اللوحة. القائمة البيضاء ضرورية لأننا
// نبني أسماء الأعمدة في نص الاستعلام (لا يمكن تمريرها كبارامتر) —
// بدونها يستطيع جسم طلب خبيث حقن اسم عمود.
const UPDATABLE = ['name_en', 'name_ar', 'country', 'logo_url', 'season', 'enabled', 'sort_order'];

// تحديث جزئي: نبني SET من الحقول المرسلة فقط، بنفس أسلوب
// userRepo.updateProfile — إرسال enabled وحده لا يمسح الاسم العربي.
async function update(id, fields = {}) {
  const sets = [];
  const params = [id];

  for (const column of UPDATABLE) {
    if (fields[column] === undefined) continue;
    params.push(fields[column]);
    sets.push(`${column} = $${params.length}`);
  }
  // لا حقول صالحة: لا نُصدر UPDATE فارغاً (خطأ نحوي)، نرجع الصف كما هو.
  if (sets.length === 0) return findById(id);

  const { rows } = await db.query(
    `UPDATE leagues SET ${sets.join(', ')}
     WHERE id = $1
     RETURNING id, COALESCE(name_ar, name_en) AS name, name_en, name_ar,
               country, logo_url, season, enabled, sort_order, last_synced_at, created_at`,
    params
  );
  return rows[0] ?? null; // null = الدوري غير موجود
}

// كم مباراة مخزّنة لهذا الدوري — يستعملها مسار الحذف ليقرر
// الرفض. استعلام مستقل وخفيف بدل جرّ findAll بحساباتها كلها.
async function fixturesCount(id) {
  const { rows } = await db.query(
    `SELECT COUNT(*)::int AS n FROM fixtures WHERE league_id = $1`,
    [id]
  );
  return rows[0].n;
}

async function remove(id) {
  const { rowCount } = await db.query(`DELETE FROM leagues WHERE id = $1`, [id]);
  return rowCount > 0;
}

// ختم آخر مزامنة ناجحة. منفصلة عن update لأنها تُستدعى من المزامنة
// وليس من الأدمن — الوقت من now() في القاعدة وليس من ساعة Node،
// فيبقى مرجع الوقت واحداً مهما تعددت نسخ السيرفر.
async function touchSynced(id) {
  await db.query(`UPDATE leagues SET last_synced_at = now() WHERE id = $1`, [id]);
}

module.exports = {
  findAll,
  findEnabled,
  findById,
  create,
  update,
  fixturesCount,
  remove,
  touchSynced,
};
