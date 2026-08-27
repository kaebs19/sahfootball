// requireAdmin — حارس مسارات الإدارة. يعمل بعد requireAuth
// (الذي وضع req.userId) ويتأكد أن الدور admin.
//
// لماذا نسأل القاعدة في كل طلب بدل وضع الدور داخل الـ JWT؟
// التوكن يعيش 15 دقيقة — لو سحبنا صلاحية أدمن مخترق لبقي أدمن حتى
// انتهاء توكنه. مسارات الإدارة قليلة الاستخدام، فاستعلام إضافي
// ثمن زهيد مقابل إبطال فوري.
const userRepo = require('../repositories/userRepo');
const db = require('../config/db');

async function requireAdmin(req, res, next) {
  const { rows } = await db.query(
    'SELECT role FROM users WHERE id = $1',
    [req.userId]
  );
  if (rows[0]?.role !== 'admin') {
    // 403 وليس 401: نعرف من أنت (التوكن صالح)، لكن لا يحق لك.
    return res.status(403).json({ error: 'هذا المسار للإدارة فقط' });
  }
  next();
}

module.exports = requireAdmin;
