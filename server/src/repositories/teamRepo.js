// teamRepo — كل تعامل جدول teams مع قاعدة البيانات يمر من هنا.
//
// لماذا طبقة repository والمشروع بلا ORM؟
// نفس منطق طبقة العزل: الـ routes لا تكتب SQL، والـ SQL لا يعرف
// شيئاً عن HTTP. لو غيّرنا استعلاماً أو أضفنا عموداً، التعديل في
// ملف واحد. كما أنها النقطة الطبيعية لاختبار الوصول للبيانات لاحقاً.
const db = require('../config/db');

// حفظ/تحديث دفعة فرق قادمة من المزامنة.
//
// UPSERT = INSERT مع ON CONFLICT: لو الفريق موجود (نفس id) حدّثه
// بدل أن تفشل. لاحظ أن name_ar غير مذكور إطلاقاً في الاستعلام —
// هذا مقصود: الترجمة تُدخل يدوياً من لوحة التحكم، والمزامنة يجب
// ألا تمسحها أبداً.
async function upsertMany(teams) {
  // حلقة صف-بصف داخل معاملة واحدة بدل INSERT عملاق متعدد الصفوف:
  // أبطأ نظرياً، لكن مع ~18 فريقاً الفرق صفر عملياً والكود أوضح بكثير.
  const client = await db.pool.connect();
  try {
    await client.query('BEGIN');
    for (const t of teams) {
      await client.query(
        `INSERT INTO teams (id, name_en, logo_url, updated_at)
         VALUES ($1, $2, $3, now())
         ON CONFLICT (id) DO UPDATE SET
           name_en    = EXCLUDED.name_en,
           logo_url   = EXCLUDED.logo_url,
           updated_at = now()`,
        [t.id, t.name_en, t.logo_url]
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

// كل الفرق، مع "التدهور اللطيف" للاسم العربي:
// COALESCE ترجع أول قيمة غير NULL — لو name_ar لم يُترجم بعد
// يظهر name_en بدل NULL. نرجع أيضاً الحقلين الخام لأن لوحة
// التحكم ستحتاج معرفة ما تُرجم وما لم يُترجم.
async function findAll() {
  const { rows } = await db.query(
    `SELECT id,
            COALESCE(name_ar, name_en) AS name,
            name_en,
            name_ar,
            logo_url
     FROM teams
     ORDER BY name_en`
  );
  return rows;
}

// تحديث الاسم العربي — يُستدعى من لوحة التحكم فقط.
// name_ar الوحيد الذي يكتب في هذا العمود في المشروع كله:
// المزامنة لا تلمسه (انظر upsertMany أعلاه).
async function updateNameAr(id, nameAr) {
  const { rowCount } = await db.query(
    `UPDATE teams SET name_ar = $2, updated_at = now() WHERE id = $1`,
    [id, nameAr]
  );
  return rowCount > 0;
}


/**
 * أندية الدوريات الداخلة في اللعبة، مجموعةً بدورياتها.
 *
 * المصدر هو fixtures لا جدول عضوية: لا جدول يقول "هذا النادي في
 * هذا الدوري هذا الموسم" — والمباريات تقوله بدقة أعلى، لأن من
 * صعد أو هبط يظهر في مكانه الصحيح تلقائياً بلا صيانة يدوية بعد
 * كل موسم.
 *
 * ومقيّدة بـ in_app لا enabled: هذه القائمة تُعرض لمن يختار فريقه
 * ليتوقّع له، فعرض نادٍ من دوري لا يُلعب فيه وعدٌ يُكسر بعد ضغطة.
 */
async function findPlayable() {
  const { rows } = await db.query(
    `SELECT l.id                            AS league_id,
            COALESCE(l.name_ar, l.name_en)  AS league_name,
            l.sort_order,
            t.id,
            COALESCE(t.name_ar, t.name_en)  AS name,
            t.logo_url
       FROM leagues l
       JOIN fixtures f ON f.league_id = l.id AND f.season = l.season
       JOIN teams t ON t.id IN (f.home_team_id, f.away_team_id)
      WHERE l.in_app
      GROUP BY l.id, l.name_ar, l.name_en, l.sort_order,
               t.id, t.name_ar, t.name_en, t.logo_url
      ORDER BY l.sort_order, 5`
  );
  return rows;
}

module.exports = { upsertMany, findAll, findPlayable, updateNameAr };
