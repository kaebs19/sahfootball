// siteRepo — كل تعامل مع جدولَي محتوى الموقع: صفحاته ورسائله.
// (انظر 009_site_content.sql لتصميم الجدولين وأسبابه.)
const db = require('../config/db');

// ── الصفحات ──────────────────────────────────────────────────────

async function getPage(slug) {
  const { rows } = await db.query(
    'SELECT slug, title, body, updated_at FROM site_pages WHERE slug = $1',
    [slug]
  );
  return rows[0] ?? null;
}

// القائمة بلا body عمداً: تخدم قائمة اللوحة وخريطة الموقع، وكلاهما
// يحتاج العناوين فقط. جرّ نصوص أربع صفحات قانونية كاملة في كل نداء
// تحميل زائد بلا مستفيد.
async function listPages() {
  const { rows } = await db.query(
    'SELECT slug, title, updated_at FROM site_pages ORDER BY slug'
  );
  return rows;
}

// تحديث كامل لا جزئي: محرّر الصفحة في اللوحة يرسل العنوان والنص
// معاً دائماً (كلاهما مربع نص أمام الأدمن)، فلا معنى لبناء SET
// ديناميكي هنا كما في leagueRepo.
//
// updated_at = now() صراحةً في كل تحديث: القيمة الافتراضية تعمل
// عند الإدخال فقط، ولو تركناها لبقي التاريخ تاريخ البذر — و"آخر
// تحديث" في أسفل صفحة قانونية معلومة يعتمد عليها القارئ.
async function updatePage(slug, { title, body }) {
  const { rows } = await db.query(
    `UPDATE site_pages
        SET title = $2, body = $3, updated_at = now()
      WHERE slug = $1
      RETURNING slug, title, body, updated_at`,
    [slug, title, body]
  );
  return rows[0] ?? null; // null = لا صفحة بهذا الـ slug
}

// ── رسائل التواصل ────────────────────────────────────────────────

async function createMessage({ name, email, subject, message, ip }) {
  const { rows } = await db.query(
    `INSERT INTO contact_messages (name, email, subject, message, ip)
     VALUES ($1, $2, $3, $4, $5)
     RETURNING id, name, email, subject, message, read_at, created_at`,
    [name ?? null, email ?? null, subject ?? null, message, ip ?? null]
  );
  return rows[0];
}

// صندوق الوارد. LIMIT ثابت: الصندوق شاشة تصفح لا تصدير بيانات،
// وترقيم صفحات كامل ترف قبل أن تتجاوز الرسائل هذا العدد أصلاً.
//
// id::text — pg يعيد BIGINT كنص أصلاً (قد يتجاوز حدود عدد
// JavaScript الآمن)، فنجعل ذلك صريحاً في الاستعلام بدل أن يفاجئ
// من يقارن id بعدد في الواجهة.
async function listMessages({ unreadOnly = false } = {}) {
  const { rows } = await db.query(
    `SELECT id::text, name, email, subject, message, read_at, created_at, ip
       FROM contact_messages
      WHERE ($1::boolean IS NOT TRUE OR read_at IS NULL)
      ORDER BY created_at DESC
      LIMIT 200`,
    [unreadOnly]
  );
  return rows;
}

// وسم الرسالة مقروءة. COALESCE يجعلها آمنة التكرار: ضغطة ثانية
// على رسالة مقروءة لا تزيّف وقت القراءة الأول.
async function markRead(id) {
  const { rows } = await db.query(
    `UPDATE contact_messages
        SET read_at = COALESCE(read_at, now())
      WHERE id = $1
      RETURNING id::text, name, email, subject, message, read_at, created_at`,
    [id]
  );
  return rows[0] ?? null;
}

async function deleteMessage(id) {
  const { rowCount } = await db.query('DELETE FROM contact_messages WHERE id = $1', [id]);
  return rowCount > 0;
}

// عدّاد شارة الصندوق في اللوحة. ::int لأن COUNT يرجع BIGINT
// (نصاً في pg) والشارة تحتاج رقماً.
async function countUnread() {
  const { rows } = await db.query(
    'SELECT COUNT(*)::int AS n FROM contact_messages WHERE read_at IS NULL'
  );
  return rows[0].n;
}

module.exports = {
  getPage,
  listPages,
  updatePage,
  createMessage,
  listMessages,
  markRead,
  deleteMessage,
  countUnread,
};
