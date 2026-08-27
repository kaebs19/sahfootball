// مشغّل الهجرات (migration runner) — بسيط وبدون مكتبات.
//
// الفكرة: جدول schema_migrations يسجّل أسماء الملفات المطبَّقة.
// عند التشغيل نقرأ migrations/*.sql بالترتيب الأبجدي (لهذا نسمّيها
// 001_، 002_ ...) ونطبّق فقط ما لم يُطبَّق بعد.
//
// لماذا لم نستخدم مكتبة مثل node-pg-migrate؟
// احتياجنا الآن هو "شغّل ملفات SQL بالترتيب مرة واحدة" — 40 سطراً
// تكفي، وقراءة SQL خام أوضح لتعلّم ما يحدث فعلاً. لو كبرت الهجرات
// (تراجع rollback، فروع متوازية) ننتقل لمكتبة.
require('dotenv').config();
const fs = require('fs');
const path = require('path');
const { pool } = require('../src/config/db');

const MIGRATIONS_DIR = path.join(__dirname, '..', 'migrations');

async function migrate() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      filename   TEXT PRIMARY KEY,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `);

  const files = fs.readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .sort();

  const { rows } = await pool.query('SELECT filename FROM schema_migrations');
  const applied = new Set(rows.map((r) => r.filename));

  for (const file of files) {
    if (applied.has(file)) {
      console.log(`skip    ${file} (already applied)`);
      continue;
    }

    const sql = fs.readFileSync(path.join(MIGRATIONS_DIR, file), 'utf8');

    // كل هجرة داخل معاملة (transaction): إما تنجح كاملة أو لا شيء.
    // بدونها، فشل في منتصف الملف يترك القاعدة في حالة نصف مهاجرة.
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(sql);
      await client.query('INSERT INTO schema_migrations (filename) VALUES ($1)', [file]);
      await client.query('COMMIT');
      console.log(`applied ${file}`);
    } catch (err) {
      await client.query('ROLLBACK');
      console.error(`FAILED  ${file}:`, err.message);
      process.exitCode = 1;
      break;
    } finally {
      client.release();
    }
  }

  await pool.end();
}

migrate();
