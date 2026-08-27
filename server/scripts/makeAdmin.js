// ترقية مستخدم إلى أدمن — من الطرفية وليس من API.
//
// قرار مقصود: لا يوجد مسار HTTP لإنشاء أول أدمن. لو وُجد لاحتاج
// حماية بأدمن موجود (بيضة ودجاجة)، أو بقي مفتوحاً (كارثة).
// الوصول للسيرفر نفسه هو التفويض.
//
// الاستخدام: node scripts/makeAdmin.js email@example.com
require('dotenv').config();
const { pool } = require('../src/config/db');

async function main() {
  const email = String(process.argv[2] || '').trim().toLowerCase();
  if (!email) {
    console.error('usage: node scripts/makeAdmin.js <email>');
    process.exit(1);
  }

  const { rowCount } = await pool.query(
    `UPDATE users SET role = 'admin', updated_at = now() WHERE email = $1`,
    [email]
  );
  if (rowCount === 0) {
    console.error(`no user with email: ${email} (سجّل الحساب أولاً ثم رقّه)`);
    process.exit(1);
  }
  console.log(`${email} is now admin`);
  await pool.end();
}

main();
