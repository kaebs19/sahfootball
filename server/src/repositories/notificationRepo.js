// notificationRepo — كل SQL الإشعارات: الأجهزة، التفضيلات، سجل
// المُرسَل، والاستعلامان اللذان يجيبان "من يستحق إشعاراً الآن؟".
//
// القرار بمن يُرسَل له هو استعلام لا حلقة في JS: البديل أن نجلب
// كل المستخدمين وكل المباريات وكل التوقعات ونقارنها في الذاكرة —
// يعمل بأربعة حسابات تجريبية وينهار بأربعة آلاف.
const db = require('../config/db');

/** تسجيل جهاز. الجهاز نفسه قد يكون مسجّلاً باسم مستخدم سابق. */
async function registerToken({ token, userId, platform }) {
  await db.query(
    `INSERT INTO device_tokens (token, user_id, platform)
     VALUES ($1, $2, $3)
     ON CONFLICT (token) DO UPDATE
       SET user_id = EXCLUDED.user_id,
           platform = EXCLUDED.platform,
           last_seen_at = now()`,
    [token, userId, platform]
  );
}

/** إلغاء تسجيل جهاز — يُنادى عند الخروج من الحساب. */
async function removeToken(token) {
  await db.query('DELETE FROM device_tokens WHERE token = $1', [token]);
}

/** حذف التوكنات التي ردّ عليها المزوّد بأنها ميتة. */
async function removeTokens(tokens) {
  if (!tokens.length) return;
  await db.query('DELETE FROM device_tokens WHERE token = ANY($1)', [tokens]);
}

/** أجهزة مستخدم واحد. */
async function tokensForUser(userId) {
  const { rows } = await db.query(
    'SELECT token, platform FROM device_tokens WHERE user_id = $1',
    [userId]
  );
  return rows;
}

async function getPrefs(userId) {
  const { rows } = await db.query(
    'SELECT notify_reminders, notify_results FROM users WHERE id = $1',
    [userId]
  );
  return rows[0] || null;
}

async function updatePrefs(userId, { reminders, results }) {
  const { rows } = await db.query(
    `UPDATE users
        SET notify_reminders = COALESCE($2, notify_reminders),
            notify_results   = COALESCE($3, notify_results),
            updated_at = now()
      WHERE id = $1
      RETURNING notify_reminders, notify_results`,
    [userId, reminders ?? null, results ?? null]
  );
  return rows[0] || null;
}

/**
 * التذكير: من لم يتوقّع لمباراة تنطلق خلال النافذة القادمة.
 *
 * الشروط مجتمعة تصف "مستخدم يستحق تذكيراً" بلا استثناء:
 *  - له جهاز مسجّل (EXISTS لا JOIN: الانضمام يكرّر الصف لكل
 *    جهاز، فيصل نفس الإشعار مرتين لصاحب هاتف وآيباد)
 *  - مفعّل التذكيرات وغير موقوف
 *  - المباراة في دوري مفعّل ولم تنطلق بعد
 *  - لا يملك توقعاً لها  ← NOT EXISTS
 *  - ولم نذكّره بها من قبل ← NOT EXISTS على sent_notifications
 *
 * الشرط الأخير هو ما يمنع تكرار نفس الإشعار كل دورة، ووجوده هنا
 * (لا في JS بعد الجلب) مقصود: يقلّص النتيجة إلى الجديد فعلاً بدل
 * أن نجلب مئات الصفوف ونرمي أغلبها.
 *
 * الحد الأدنى للنافذة (kickoff > now()) يحمي من حالة حقيقية:
 * سيرفر متوقف ساعتين يعود ليجد مباريات انطلقت، فيرسل "توقّع قبل
 * أن تُقفل" لمباريات أُقفلت — أسوأ من ألا يرسل شيئاً.
 */
async function usersNeedingReminder(leadMinutes) {
  const { rows } = await db.query(
    `SELECT u.id AS user_id, f.id AS fixture_id, f.kickoff_at,
            COALESCE(ht.name_ar, ht.name_en) AS home_name,
            COALESCE(at.name_ar, at.name_en) AS away_name
       FROM users u
       JOIN fixtures f ON f.status = 'scheduled'
                      AND f.kickoff_at > now()
                      AND f.kickoff_at <= now() + ($1 || ' minutes')::interval
       JOIN leagues l ON l.id = f.league_id AND l.enabled
       JOIN teams ht ON ht.id = f.home_team_id
       JOIN teams at ON at.id = f.away_team_id
      WHERE u.notify_reminders
        AND u.suspended_at IS NULL
        AND EXISTS (
              SELECT 1 FROM device_tokens d WHERE d.user_id = u.id)
        AND NOT EXISTS (
              SELECT 1 FROM predictions p
               WHERE p.user_id = u.id AND p.fixture_id = f.id)
        AND NOT EXISTS (
              SELECT 1 FROM sent_notifications s
               WHERE s.user_id = u.id AND s.kind = 'reminder'
                 AND s.ref = f.id::text)
      ORDER BY f.kickoff_at ASC`,
    [String(leadMinutes)]
  );
  return rows;
}

/**
 * النتائج: توقعات احتُسبت ولم يُبلَّغ صاحبها بعد.
 *
 * لا نافذة زمنية هنا ولا "منذ آخر مرة": الوجود في
 * sent_notifications هو الحد الوحيد، فمستخدم أُرسل له بالفعل لا
 * يظهر مهما تكرر الاستعلام. هذا أمتن من مقارنة settled_at بوقت
 * التشغيل السابق، التي تفقد صفوفاً إن أُعيد تشغيل السيرفر في
 * اللحظة الخطأ.
 *
 * الحد الزمني الوحيد (يومان) غرضه مختلف تماماً: أول تشغيل بعد
 * هذه الهجرة يجد سجل الإرسال فارغاً وكل التوقعات القديمة "لم
 * يُبلَّغ عنها"، فينهال على المستخدم إشعار لكل مباراة لعبها منذ
 * إطلاق التطبيق. الشرط يقصر الأمر على ما احتُسب فعلاً هذه الأيام.
 */
async function unnotifiedResults() {
  const { rows } = await db.query(
    `SELECT u.id AS user_id, p.fixture_id, p.points,
            f.goals_home, f.goals_away,
            COALESCE(ht.name_ar, ht.name_en) AS home_name,
            COALESCE(at.name_ar, at.name_en) AS away_name
       FROM predictions p
       JOIN users u ON u.id = p.user_id
       JOIN fixtures f ON f.id = p.fixture_id
       JOIN teams ht ON ht.id = f.home_team_id
       JOIN teams at ON at.id = f.away_team_id
      WHERE p.settled_at IS NOT NULL
        AND p.settled_at > now() - interval '2 days'
        AND u.notify_results
        AND u.suspended_at IS NULL
        AND EXISTS (
              SELECT 1 FROM device_tokens d WHERE d.user_id = u.id)
        AND NOT EXISTS (
              SELECT 1 FROM sent_notifications s
               WHERE s.user_id = u.id AND s.kind = 'result'
                 AND s.ref = p.fixture_id::text)
      ORDER BY p.settled_at ASC`
  );
  return rows;
}

/**
 * تسجيل ما أُرسل. المفتاح المركّب في القاعدة يجعل التكرار تصادماً
 * يسقط بصمت — فلا حاجة لفحص مسبق، ولا سباق بين نسختين من الوظيفة.
 */
async function markSent(userId, kind, refs) {
  if (!refs.length) return;
  await db.query(
    `INSERT INTO sent_notifications (user_id, kind, ref)
     SELECT $1, $2, unnest($3::text[])
     ON CONFLICT DO NOTHING`,
    [userId, kind, refs.map(String)]
  );
}

/**
 * حذف سجلّات الإرسال القديمة.
 *
 * الجدول موجود لمنع التكرار لا للتأريخ، وصف عمره شهر لا يمنع شيئاً:
 * مباراته انتهت واحتُسبت ولن يُسأل عنها ثانية. بلا هذا ينمو الجدول
 * بمعدل (مستخدم × مباراة) إلى الأبد.
 *
 * الحد ثلاثون يوماً لا يوم واحد: النافذة يجب أن تتجاوز بفارق مريح
 * أطول مدة يبقى فيها صف "ذا معنى" — وهي هنا يومان (شرط
 * unnotifiedResults). هامش واسع مقابل صفوف قليلة رخيصة.
 */
async function purgeOldSent(days = 30) {
  const { rowCount } = await db.query(
    `DELETE FROM sent_notifications
      WHERE sent_at < now() - ($1 || ' days')::interval`,
    [String(days)]
  );
  return rowCount;
}

module.exports = {
  registerToken,
  removeToken,
  removeTokens,
  tokensForUser,
  getPrefs,
  updatePrefs,
  usersNeedingReminder,
  unnotifiedResults,
  markSent,
  purgeOldSent,
};
