// اتصال PostgreSQL عبر Pool واحد مشترك.
//
// لماذا Pool وليس Client؟
// كل طلب HTTP يحتاج اتصالاً بقاعدة البيانات. فتح اتصال جديد لكل طلب
// مكلف (مصافحة TCP + مصادقة). الـ Pool يحتفظ بمجموعة اتصالات مفتوحة
// ويعيد استخدامها — وهذا هو المعيار في تطبيقات Node.
const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  // أقصى عدد اتصالات متزامنة. 10 كافية جداً لمشروعنا الآن.
  max: 10,
});

// لو انقطع اتصال خامل في الـ Pool (مثلاً السيرفر أعاد التشغيل)
// نسجّل الخطأ بدل أن ينهار التطبيق كاملاً.
pool.on('error', (err) => {
  console.error('[db] unexpected pool error:', err.message);
});

module.exports = {
  // نصدّر دالة query واحدة بدل تصدير الـ pool مباشرة،
  // حتى تكون كل الاستعلامات في المشروع بنمط موحّد:
  // db.query('SELECT ...', [params])
  query: (text, params) => pool.query(text, params),
  pool, // نحتاجه للإغلاق النظيف عند إيقاف السيرفر
};
