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

module.exports = { upsertMany, findAll, updateNameAr };
