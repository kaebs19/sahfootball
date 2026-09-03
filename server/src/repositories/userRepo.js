// userRepo — كل تعامل جدول users مع القاعدة.
const db = require('../config/db');

// الأعمدة التي يجوز خروجها من هذه الطبقة للأعلى.
// password_hash غير مذكور عمداً في أي SELECT عام — لا يغادر
// هذه الطبقة إلا عبر findByEmailWithHash المخصصة للتحقق فقط.
const PUBLIC_COLUMNS =
  'id, email, display_name, avatar_url, favorite_team_id, onboarded_at, created_at';

async function create({ email, passwordHash, displayName }) {
  const { rows } = await db.query(
    `INSERT INTO users (email, password_hash, display_name)
     VALUES ($1, $2, $3)
     RETURNING ${PUBLIC_COLUMNS}`,
    [email, passwordHash, displayName ?? null]
  );
  return rows[0];
}

// حالة الإيقاف وحدها — أخف استعلام ممكن، ويُستدعى في requireAuth
// أي في كل طلب محمي. لهذا لا يجلب PUBLIC_COLUMNS: عمودان فقط،
// وبحث بالمفتاح الأساسي.
async function findSuspension(id) {
  const { rows } = await db.query(
    `SELECT suspended_at, suspended_reason FROM users WHERE id = $1`,
    [id]
  );
  return rows[0] ?? null;
}

// إيقاف أو رفع الإيقاف. suspendedAt = null يعني الرفع، ومعه نمسح
// السبب أيضاً — سبب معلّق على حساب سليم تشويش لا فائدة منه.
async function setSuspension(id, { suspendedAt, reason }) {
  const { rows } = await db.query(
    `UPDATE users
        SET suspended_at     = $2,
            suspended_reason = CASE WHEN $2::timestamptz IS NULL THEN NULL ELSE $3 END,
            updated_at       = now()
      WHERE id = $1
      RETURNING id, email, suspended_at, suspended_reason`,
    [id, suspendedAt, reason ?? null]
  );
  return rows[0] ?? null;
}

// للتحقق من كلمة السر عند الدخول — الوحيدة التي ترجع الـ hash.
//
// apple_sub معها لأن من يتحقق من الهوية يحتاج الطريقتين: حساب بلا
// hash هو حساب Apple، وإثبات هويته يكون بمطابقة sub لا بكلمة سر.
async function findByEmailWithHash(email) {
  const { rows } = await db.query(
    `SELECT ${PUBLIC_COLUMNS}, password_hash, apple_sub, google_sub FROM users WHERE email = $1`,
    [email]
  );
  return rows[0] ?? null;
}

async function findById(id) {
  const { rows } = await db.query(
    `SELECT ${PUBLIC_COLUMNS} FROM users WHERE id = $1`,
    [id]
  );
  return rows[0] ?? null;
}

async function findByEmail(email) {
  const { rows } = await db.query(
    `SELECT ${PUBLIC_COLUMNS} FROM users WHERE email = $1`,
    [email]
  );
  return rows[0] ?? null;
}

async function findByAppleSub(appleSub) {
  const { rows } = await db.query(
    `SELECT ${PUBLIC_COLUMNS} FROM users WHERE apple_sub = $1`,
    [appleSub]
  );
  return rows[0] ?? null;
}

// إنشاء حساب عبر Apple: بلا كلمة سر (NULL صراحة).
async function createWithApple({ email, appleSub, displayName }) {
  const { rows } = await db.query(
    `INSERT INTO users (email, apple_sub, display_name)
     VALUES ($1, $2, $3)
     RETURNING ${PUBLIC_COLUMNS}`,
    [email, appleSub, displayName ?? null]
  );
  return rows[0];
}

// ربط حساب بريد موجود بهوية Apple (نفس البريد في الجهتين).
async function linkAppleSub(userId, appleSub) {
  await db.query(
    `UPDATE users SET apple_sub = $2, updated_at = now() WHERE id = $1`,
    [userId, appleSub]
  );
}

async function findByGoogleSub(googleSub) {
  const { rows } = await db.query(
    `SELECT ${PUBLIC_COLUMNS} FROM users WHERE google_sub = $1`,
    [googleSub]
  );
  return rows[0] ?? null;
}

// إنشاء حساب عبر جوجل: بلا كلمة سر (NULL صراحة) — كنظيره في Apple.
async function createWithGoogle({ email, googleSub, displayName }) {
  const { rows } = await db.query(
    `INSERT INTO users (email, google_sub, display_name)
     VALUES ($1, $2, $3)
     RETURNING ${PUBLIC_COLUMNS}`,
    [email, googleSub, displayName ?? null]
  );
  return rows[0];
}

// ربط حساب موجود بهوية جوجل (نفس البريد في الجهتين).
async function linkGoogleSub(userId, googleSub) {
  await db.query(
    `UPDATE users SET google_sub = $2, updated_at = now() WHERE id = $1`,
    [userId, googleSub]
  );
}

// تحديث الملف الشخصي — يبني جملة UPDATE ديناميكياً من الحقول
// المرسلة فقط: إرسال displayName وحده لا يمسح الفريق المفضل.
async function updateProfile(userId, { displayName, favoriteTeamId, avatarUrl }) {
  const sets = [];
  const params = [userId];
  const add = (column, value) => {
    params.push(value);
    sets.push(`${column} = $${params.length}`);
  };

  if (displayName !== undefined) add('display_name', displayName);
  if (favoriteTeamId !== undefined) add('favorite_team_id', favoriteTeamId);
  if (avatarUrl !== undefined) add('avatar_url', avatarUrl);
  if (sets.length === 0) return;

  await db.query(
    `UPDATE users SET ${sets.join(', ')}, updated_at = now() WHERE id = $1`,
    params
  );
}

/**
 * وسمُ انتهاء التهيئة.
 *
 * COALESCE لا كتابة مباشرة: من أنهاها ثم فتح الرابط ثانية لا
 * يُزاح تاريخه الأصلي — والتاريخ هو ما نقيس به أثر التهيئة، فكتابة
 * "الآن" فوقه تمحو الحقيقة التي حفظناه لأجلها.
 */
async function markOnboarded(userId) {
  await db.query(
    `UPDATE users SET onboarded_at = COALESCE(onboarded_at, now()), updated_at = now()
      WHERE id = $1`,
    [userId]
  );
}

async function updatePassword(userId, passwordHash) {
  await db.query(
    `UPDATE users SET password_hash = $2, updated_at = now() WHERE id = $1`,
    [userId, passwordHash]
  );
}

// تغيير البريد. لا نفحص التكرار هنا: قيد UNIQUE في القاعدة هو
// الحكم النهائي (فحص ثم إدخال يترك ثغرة زمنية بين الاثنين)، وطبقة
// authService تفحص مسبقاً لتعطي رسالة عربية مفهومة في الحالة الشائعة.
async function updateEmail(userId, email) {
  const { rows } = await db.query(
    `UPDATE users SET email = $2, updated_at = now()
      WHERE id = $1
      RETURNING ${PUBLIC_COLUMNS}`,
    [userId, email]
  );
  return rows[0] ?? null;
}

// قائمة المستخدمين للوحة التحكم، مع إحصاءات توقعاتهم.
// LEFT JOIN وليس JOIN: المستخدم بلا توقعات يجب أن يظهر أيضاً.
async function adminList(search = '') {
  const params = [];
  let where = '';
  if (search) {
    // ILIKE = LIKE غير حساس لحالة الأحرف. %...% للبحث الجزئي.
    params.push(`%${search}%`);
    where = `WHERE u.email ILIKE $1 OR u.display_name ILIKE $1`;
  }
  const { rows } = await db.query(
    `SELECT u.id, u.email, u.display_name, u.avatar_url, u.role, u.created_at,
            -- تكفي اللوحة لتضع شارة "موقوف" بجانب الاسم بلا طلب
            -- إضافي لكل صف. السبب لا يُرسل في القائمة عمداً: نص حر
            -- قد يطول، ومكانه شاشة تفاصيل المستخدم.
            u.suspended_at,
            (u.apple_sub IS NOT NULL) AS via_apple,
            COUNT(p.id)::int AS predictions_count,
            COALESCE(SUM(p.points), 0)::int AS total_points
     FROM users u
     LEFT JOIN predictions p ON p.user_id = u.id
     ${where}
     GROUP BY u.id
     ORDER BY u.created_at DESC
     LIMIT 200`,
    params
  );
  return rows;
}

async function updateRole(id, role) {
  const { rowCount } = await db.query(
    `UPDATE users SET role = $2, updated_at = now() WHERE id = $1`,
    [id, role]
  );
  return rowCount > 0;
}

// كم أدمن غير هذا المستخدم؟ يخدم حارس "آخر أدمن" عند الحذف.
// نمرر client اختيارياً حتى يعمل داخل معاملة الحذف على نفس الاتصال —
// خارجها يكون العدد قديماً لحظة استعماله.
async function countOtherAdmins(id, client = db) {
  const { rows } = await client.query(
    `SELECT COUNT(*)::int AS n FROM users WHERE role = 'admin' AND id <> $1`,
    [id]
  );
  return rows[0].n;
}

// تفاصيل مستخدم واحد للوحة التحكم.
//
// ثلاثة استعلامات متوازية بدل واحد بـ json_agg متداخلة — نفس القرار
// المشروح في /admin/stats: صف المستخدم واحد، أما القروبات والتوقعات
// فقائمتان بأعمدة مختلفة، وحشرها معاً يجعل الاستعلام غير قابل
// للقراءة بلا مكسب (الثلاثة تمشي على التوازي وتصل معاً).
async function adminDetail(id, recentLimit = 20) {
  const [profile, groups, recent] = await Promise.all([
    // 1) الملف + الدور + حالة الإيقاف + الإحصاءات.
    // العدّادات استعلامات فرعية وليست JOIN + GROUP BY: JOIN واحد مع
    // predictions ثم SUM يعمل، لكن إضافة أي JOIN ثانٍ (القروبات مثلاً)
    // يضاعف الصفوف ويضخّم المجاميع بصمت — الفخ الكلاسيكي.
    db.query(
      `SELECT u.id, u.email, u.display_name, u.avatar_url, u.created_at,
              u.role, u.suspended_at, u.suspended_reason,
              (u.apple_sub IS NOT NULL) AS via_apple,
              u.favorite_team_id,
              COALESCE(ft.name_ar, ft.name_en) AS favorite_team_name,
              ft.logo_url                      AS favorite_team_logo,
              (SELECT COUNT(*) FROM predictions p
                WHERE p.user_id = u.id)::int                        AS predictions_count,
              (SELECT COUNT(*) FROM predictions p
                WHERE p.user_id = u.id AND p.settled_at IS NOT NULL)::int AS settled_predictions,
              (SELECT COALESCE(SUM(p.points), 0) FROM predictions p
                WHERE p.user_id = u.id)::int                        AS total_points,
              -- الدقة = نسبة التوقعات المحتسبة التي أعطت نقاطاً.
              -- المقام هو المحتسبة فقط: توقع على مباراة لم تُلعب بعد
              -- ليس خطأً، وحسابه ضمن النسبة يعاقب النشِط على نشاطه.
              -- NULLIF يمنع القسمة على صفر — النتيجة NULL لمن لا
              -- توقعات محتسبة له، واللوحة تعرض "—" لا صفراً مضللاً.
              (SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE p.points > 0)
                            / NULLIF(COUNT(*), 0), 1)
                 FROM predictions p
                WHERE p.user_id = u.id AND p.settled_at IS NOT NULL)::float8 AS accuracy
         FROM users u
         LEFT JOIN teams ft ON ft.id = u.favorite_team_id
        WHERE u.id = $1`,
      [id]
    ),

    // 2) القروبات: ما يملكه وما انضم إليه في قائمة واحدة، و is_owner
    // يفرّق بينهما. قائمة واحدة لأن القروب الواحد لا يظهر مرتين
    // (المالك عضو دائماً — routes/groups يمنعه من المغادرة).
    //
    // البداية من groups مع LEFT JOIN على العضوية وليس العكس: شرط
    // "يملكه أو عضو فيه" يجب أن يلتقط أيضاً قروباً يملكه بلا صف
    // عضوية — حالة لا ينتجها الكود اليوم، لكن بدء الاستعلام من
    // group_members كان سيخفيها بصمت لو حدثت يوماً بخلل بيانات،
    // ومكان اكتشاف مثل هذا الخلل هو لوحة الإشراف بالذات.
    db.query(
      `SELECT g.id, g.name, g.invite_code, g.created_at, gm.joined_at,
              (g.owner_id = $1) AS is_owner,
              (SELECT COUNT(*) FROM group_members m WHERE m.group_id = g.id)::int AS members_count
         FROM groups g
         LEFT JOIN group_members gm ON gm.group_id = g.id AND gm.user_id = $1
        WHERE g.owner_id = $1 OR gm.user_id = $1
        ORDER BY is_owner DESC, gm.joined_at DESC NULLS LAST`,
      [id]
    ),

    // 3) آخر توقعاته مع بيانات المباراة — لتقييم سلوكه بنظرة واحدة
    // (هل يتوقع فعلاً أم يعبث؟). نفس أعمدة predictionRepo.findMine
    // مع النتيجة الفعلية للمقارنة.
    db.query(
      `SELECT p.id, p.fixture_id, p.pred_home, p.pred_away, p.points, p.settled_at, p.created_at,
              f.status, f.kickoff_at, f.goals_home, f.goals_away, f.round, f.league_id,
              COALESCE(ht.name_ar, ht.name_en) AS home_team_name,
              COALESCE(at.name_ar, at.name_en) AS away_team_name
         FROM predictions p
         JOIN fixtures f ON f.id = p.fixture_id
         JOIN teams ht ON ht.id = f.home_team_id
         JOIN teams at ON at.id = f.away_team_id
        WHERE p.user_id = $1
        ORDER BY f.kickoff_at DESC
        LIMIT $2`,
      [id, recentLimit]
    ),
  ]);

  const row = profile.rows[0];
  if (!row) return null;

  // العدّادات مسطّحة مع بقية حقول المستخدم (لا كائن stats متداخل):
  // نفس أسماء lists الأخرى في المشروع — total_points و
  // settled_predictions هما ما ترجعه لوحة الصدارة و adminList
  // أصلاً، فتقرأها اللوحة بنفس الشيفرة في كل الشاشات.
  return { ...row, groups: groups.rows, predictions: recent.rows };
}

// حذف مستخدم نهائياً.
//
// كل ما يشير إلى users في قاعدتنا معرَّف ON DELETE CASCADE
// (predictions، refresh_tokens، group_members، groups.owner_id)،
// فسطر DELETE واحد ينظّف الجداول الأربعة. المعاملة هنا ليست لأجل
// الجداول المتتالية بل لأجل خطوتين لا تستطيع القاعدة فعلهما وحدها:
//
// 1. حارس "آخر أدمن": الفحص والحذف يجب أن يكونا ذرّيين. لو فحص
//    أدمنان في اللحظة نفسها لرأى كلٌّ منهما الآخر موجوداً، ونجح
//    الحذفان، وبقي النظام بلا أي أدمن. FOR UPDATE على صفوف الأدمن
//    يسلسل العمليتين — الثانية تنتظر ثم ترى الواقع بعد الأولى.
//
// 2. نقل ملكية القروبات قبل أن يجرّها الـ CASCADE (انظر أدناه).
//
// نرجع avatar_url للأعلى لأن حذف الملف من القرص لا يمكن التراجع
// عنه: يجري بعد نجاح COMMIT لا قبله.
async function removeWithGroupHandover(id) {
  const client = await db.pool.connect();
  try {
    await client.query('BEGIN');

    // قفل صفوف الأدمن كلها (حفنة صفوف) قبل أي قرار — انظر (1) أعلاه.
    await client.query(`SELECT id FROM users WHERE role = 'admin' FOR UPDATE`);

    const { rows: target } = await client.query(
      `SELECT id, avatar_url, role FROM users WHERE id = $1 FOR UPDATE`,
      [id]
    );
    if (!target[0]) {
      await client.query('ROLLBACK');
      return { ok: false, reason: 'not_found' };
    }
    if (target[0].role === 'admin' && (await countOtherAdmins(id, client)) === 0) {
      await client.query('ROLLBACK');
      return { ok: false, reason: 'last_admin' };
    }

    // نقل ملكية القروبات التي فيها أعضاء آخرون.
    //
    // القرار: القروب يُسلَّم لأقدم عضو غيره، ولا يُحذف إلا إن كان
    // صاحبه عضوه الوحيد.
    // لماذا لا نترك CASCADE يحذفها كما تقول الهجرة 005؟ ذلك القرار
    // كُتب لحذف المستخدم حسابَه بنفسه — حينها كل من في القروب دخلوه
    // بدعوته وزواله معه مفهوم. أما حذف إشرافي لمخالفة فيعاقب أبرياء:
    // عشرة أصدقاء يفقدون قروبهم وتاريخ منافستهم بسبب فعل شخص واحد.
    // والملكية ليست بيانات شخصية للمحذوف — إنها دور إداري ينتقل.
    // المشرف أولاً ثم أقدم عضو: المالك حين عيّن مشرفاً قال فعلياً
    // «هذا من أثق به في الإدارة»، وذلك أقوى من الأقدمية. وبلا مشرف
    // يبقى أقدم عضو لأنه الأقرب لأن يكون الشريك المؤسس.
    const { rows: transferred } = await client.query(
      `UPDATE groups g
          SET owner_id = nxt.user_id
         FROM (
           SELECT DISTINCT ON (gm.group_id) gm.group_id, gm.user_id
             FROM group_members gm
             JOIN groups g2 ON g2.id = gm.group_id
            WHERE g2.owner_id = $1 AND gm.user_id <> $1
            ORDER BY gm.group_id, (gm.role = 'moderator') DESC, gm.joined_at ASC
         ) nxt
        WHERE g.id = nxt.group_id
        RETURNING g.id, g.name, nxt.user_id AS new_owner_id`,
      [id]
    );
    // المالك الجديد يعود عضواً عادياً في صفّ العضوية: الملكية في
    // groups.owner_id، ودورُ «مشرف» باقٍ إلى جانبها يقول شيئين عن
    // شخص واحد.
    await client.query(
      `UPDATE group_members gm SET role = 'member'
         FROM groups g
        WHERE g.id = gm.group_id AND g.owner_id = gm.user_id AND gm.role <> 'member'`
    );

    // ما بقي باسمه بعد النقل = قروبات هو عضوها الوحيد، وسيسحبها
    // الـ CASCADE معه. نقرأها الآن لنخبر الأدمن بما فقده فعلاً.
    const { rows: doomedGroups } = await client.query(
      `SELECT id, name FROM groups WHERE owner_id = $1`,
      [id]
    );
    const { rows: counts } = await client.query(
      `SELECT (SELECT COUNT(*) FROM predictions   WHERE user_id = $1)::int AS predictions,
              (SELECT COUNT(*) FROM group_members WHERE user_id = $1)::int AS memberships,
              (SELECT COUNT(*) FROM refresh_tokens WHERE user_id = $1)::int AS sessions`,
      [id]
    );

    await client.query(`DELETE FROM users WHERE id = $1`, [id]);
    await client.query('COMMIT');

    return {
      ok: true,
      avatar_url: target[0].avatar_url,
      transferred_groups: transferred,
      deleted_groups: doomedGroups,
      deleted: counts[0],
    };
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

// بحث مستخدم لإضافته إلى مجلس — الاسم جزئياً أو البريد كاملاً.
//
// البريد بمطابقة تامة لا جزئية عمداً: «a@» جزئياً يعدّد بريد كل
// المستخدمين حرفاً حرفاً، والتام لا يؤكّد إلا ما يعرفه الباحث
// أصلاً. والبريد نفسه لا يخرج في النتيجة — الاسم والصورة يكفيان
// للتعرّف، وما لا يُرسل لا يتسرّب.
//
// الموقوف لا يظهر: إضافته إلى مجلس تُدخل حساباً لا يستطيع اللعب.
async function searchPublic(query, limit = 10) {
  const q = String(query || '').trim();
  const { rows } = await db.query(
    `SELECT id, COALESCE(display_name, 'مشجع') AS display_name, avatar_url
       FROM users
      WHERE suspended_at IS NULL
        AND (display_name ILIKE $1 OR lower(email) = lower($2))
      ORDER BY (lower(email) = lower($2)) DESC, display_name
      LIMIT $3`,
    [`%${q}%`, q, limit]
  );
  return rows;
}

module.exports = {
  markOnboarded, searchPublic,
  create, findByEmailWithHash, findById, findByEmail, updatePassword, updateProfile,
  findByAppleSub, createWithApple, linkAppleSub, updateEmail,
  findByGoogleSub, createWithGoogle, linkGoogleSub,
  findSuspension, setSuspension,
  adminList, adminDetail, updateRole, countOtherAdmins, removeWithGroupHandover,
};
