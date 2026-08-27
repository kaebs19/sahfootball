// settingsRepo — قراءة وتعديل إعدادات التطبيق (app_settings).
const db = require('../config/db');

// ترجع قيمة الإعداد (كائن JS جاهز — عمود JSONB تفكه مكتبة pg
// تلقائياً)، أو null لو المفتاح غير موجود.
async function get(key) {
  const { rows } = await db.query(
    'SELECT value FROM app_settings WHERE key = $1',
    [key]
  );
  return rows[0]?.value ?? null;
}

async function set(key, value) {
  await db.query(
    `INSERT INTO app_settings (key, value, updated_at)
     VALUES ($1, $2, now())
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
    [key, JSON.stringify(value)]
  );
}

module.exports = { get, set };
