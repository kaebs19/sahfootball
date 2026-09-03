// purchaseRepo — دفتر المشتريات، وما يُشتقّ منه من أرصدة.
//
// الدفتر يُضاف إليه فقط: لا تعديل ولا حذف. الرصيد ليس عموداً هنا
// ولا في أي مكان — يُحسب عند السؤال من (ما اشتُري ناقص ما أُنفق).
// راجع الهجرة 027 لسبب ذلك كاملاً.
const db = require('../config/db');

/**
 * تسجيل عملية شراء.
 *
 * يرجع الصف الجديد، أو null لو كان `externalId` مسجّلاً سلفاً —
 * وهذه ليست حالة خطأ بل الحالة الطبيعية لإيصال يصل مرتين. القيد
 * UNIQUE هو من يكتشفها، لا فحصٌ قبل الكتابة: بين الفحص والكتابة
 * فجوة تمرّ منها طلبات متزامنة، وبين ON CONFLICT والكتابة لا فجوة.
 */
async function record({ userId, kind, quantity = 1, platform, externalId = null }) {
  const { rows } = await db.query(
    `INSERT INTO purchases (user_id, kind, quantity, platform, external_id)
     VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (external_id) DO NOTHING
     RETURNING id, user_id, kind, quantity, platform, external_id, created_at`,
    [userId, kind, quantity, platform, externalId]
  );
  return rows[0] ?? null;
}

/**
 * رصيد المضاعِف المشترى: كم اشترى وكم أنفق وكم بقي.
 *
 * المنفَق يُعدّ من التوقّعات نفسها لا من دفتر إنفاق: من ألغى
 * المضاعِف قبل الصافرة عاد توقّعه إلى 1 فنقص المعدود من نفسه —
 * استردادٌ مجاني بلا سطر كود، تماماً كالمضاعِف المجاني في 019.
 *
 * وهو رصيد عام لا مقيّد بدوري: المجاني حصةٌ نمنحها فتُقسَّم على
 * الدوريات بالتساوي، والمشترى مِلكٌ دفع ثمنه صاحبه — فيُنفق حيث
 * يشاء.
 */
async function multiplierBalance(userId, factor) {
  const { rows } = await db.query(
    `SELECT
       (SELECT COALESCE(SUM(quantity), 0)::int FROM purchases
         WHERE user_id = $1 AND kind = 'multiplier')            AS bought,
       (SELECT COUNT(*)::int FROM predictions
         WHERE user_id = $1 AND multiplier = $2)                AS used`,
    [userId, factor]
  );
  const { bought, used } = rows[0];
  return { bought, used, left: Math.max(0, bought - used) };
}

/** سجلّ مشتريات المستخدم — لشاشة "مشترياتي" وللدعم. */
async function findMine(userId, limit = 50) {
  const { rows } = await db.query(
    `SELECT id, kind, quantity, platform, created_at
       FROM purchases WHERE user_id = $1
      ORDER BY created_at DESC LIMIT $2`,
    [userId, limit]
  );
  return rows;
}

/** للوحة التحكم: آخر المشتريات مع أصحابها. */
async function adminList(limit = 200) {
  const { rows } = await db.query(
    `SELECT p.id, p.kind, p.quantity, p.platform, p.created_at,
            u.id AS user_id, u.email,
            COALESCE(u.display_name, 'مشجع') AS display_name,
            u.premium_until
       FROM purchases p
       JOIN users u ON u.id = p.user_id
      ORDER BY p.created_at DESC
      LIMIT $1`,
    [limit]
  );
  return rows;
}

module.exports = { record, multiplierBalance, findMine, adminList };
