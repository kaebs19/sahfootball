// predictionRepo — تعامل جدول predictions مع القاعدة.
const db = require('../config/db');

// حفظ/تعديل توقع. قيد UNIQUE(user_id, fixture_id) يجعل التعديل
// قبل انطلاق المباراة تحديثاً للصف نفسه.
// الشرط WHERE settled_at IS NULL في جهة UPDATE حزام أمان أخير:
// حتى لو أخطأت طبقة أعلى، توقع محتسب لا يُعدَّل أبداً.
async function upsert({ userId, fixtureId, predHome, predAway, multiplier = null }) {
  // multiplier = null معناه "لا تلمسه"، لا "أرجعه إلى 1".
  //
  // للتوقّع بابان: الموقع يرسل الحقل دائماً (مربّع الاختيار
  // المضاعِف جزء من نموذجه)، والتطبيق لا يعرفه بعد. ولولا هذا
  // التمييز لكان أي تعديل من التطبيق على توقّع مضاعَف من الموقع
  // يُسقط المضاعِف بصمت — يخسر اللاعب أداة نادرة لأنه رفع هدفاً
  // من هاتفه. COALESCE على $5 صراحةً لا على EXCLUDED: قيمة
  // EXCLUDED محسوبة سلفاً بـ 1 عند الإدراج، فتضيع نية "اتركه".
  const { rows } = await db.query(
    `INSERT INTO predictions (user_id, fixture_id, pred_home, pred_away, multiplier)
     VALUES ($1, $2, $3, $4, COALESCE($5, 1))
     ON CONFLICT (user_id, fixture_id) DO UPDATE SET
       pred_home  = EXCLUDED.pred_home,
       pred_away  = EXCLUDED.pred_away,
       multiplier = COALESCE($5, predictions.multiplier),
       updated_at = now()
     WHERE predictions.settled_at IS NULL
     RETURNING id, fixture_id, pred_home, pred_away, multiplier, points, created_at, updated_at`,
    [userId, fixtureId, predHome, predAway, multiplier]
  );
  return rows[0] ?? null; // null = الصف محتسب فرفض التحديث
}

/**
 * كم مضاعِفاً استعمل هذا اللاعب في هذا الدوري وهذا الموسم؟
 *
 * exceptFixture يُستثنى عمداً: من يعدّل توقّعاً مضاعَفاً أصلاً لا
 * ينفق مضاعِفاً ثانياً. واستثناؤه في الاستعلام بدل قراءة الصف
 * الحالي أولاً يجعل الإنشاء والتعديل سؤالاً واحداً — والحالتان
 * تسلكان نفس المسار في submit، فالتفريق بينهما هنا خطأ ينتظر.
 */
async function countMultiplied(userId, leagueId, season, exceptFixture = 0) {
  // فحص صريح لأن الصمت هنا يمنح مضاعفات بلا حدّ.
  //
  // مرّ فعلاً: صفحة المباراة تقرأ المباراة من siteFixtureRepo لا من
  // fixtureRepo، وقائمة أعمدة الأولى لم تكن تضم season. فوصلت
  // undefined فأرسلتها pg كـ NULL، و`f.season = NULL` لا يطابق
  // شيئاً أبداً — فرجع العدّ صفراً، وقرأ كل لاعب "باقٍ لك 5 من 5"
  // مهما أنفق. لا خطأ ولا سطر في السجل: حصةٌ تحرسها القاعدة صارت
  // مفتوحة لأن عموداً غاب عن SELECT.
  //
  // القاعدة العامة: مدخلٌ ناقصٌ في استعلام يحرس حصة يجب أن يصرخ،
  // لا أن يُقرأ كـ"لا شيء منفَق".
  if (!Number.isInteger(leagueId) || !Number.isInteger(season)) {
    throw new Error(`countMultiplied: league/season ناقصان (${leagueId}/${season})`);
  }

  const { rows } = await db.query(
    `SELECT COUNT(*)::int AS used
       FROM predictions p
       JOIN fixtures f ON f.id = p.fixture_id
      WHERE p.user_id = $1
        AND p.multiplier > 1
        AND f.league_id = $2
        AND f.season = $3
        AND p.fixture_id <> $4`,
    [userId, leagueId, season, exceptFixture]
  );
  return rows[0].used;
}

// توقعات المستخدم مع معلومات المباراة للعرض مباشرة في التطبيق.
async function findMine(userId) {
  const { rows } = await db.query(
    `SELECT p.id, p.fixture_id, p.pred_home, p.pred_away, p.multiplier, p.points, p.settled_at,
            f.kickoff_at, f.status, f.goals_home, f.goals_away, f.round,
            COALESCE(ht.name_ar, ht.name_en) AS home_team_name,
            COALESCE(at.name_ar, at.name_en) AS away_team_name
     FROM predictions p
     JOIN fixtures f ON f.id = p.fixture_id
     JOIN teams ht ON ht.id = f.home_team_id
     JOIN teams at ON at.id = f.away_team_id
     WHERE p.user_id = $1
     ORDER BY f.kickoff_at DESC`,
    [userId]
  );
  return rows;
}

// توقعات مستخدم واحد لمجموعة مباريات محددة.
//
// استعلام واحد بـ ANY بدل استعلام لكل مباراة: تبويب "مباشر" يجمع
// المباريات الجارية والقادمة والمنتهية اليوم في رد واحد، وسؤال
// القاعدة مرة لكل صف هو مشكلة N+1 الكلاسيكية — تظهر سريعة على
// مباراتين وتخنق السيرفر في جولة كاملة.
// ANY وليس IN (...) المبنية بالنصوص: عدد المعرّفات متغير، وبناء
// جملة SQL بحلقة هو الباب الذي يدخل منه حقن SQL.
async function findByUserAndFixtures(userId, fixtureIds) {
  if (fixtureIds.length === 0) return []; // لا داعي لجولة إلى القاعدة
  const { rows } = await db.query(
    `SELECT fixture_id, pred_home, pred_away, multiplier
     FROM predictions
     WHERE user_id = $1 AND fixture_id = ANY($2::int[])`,
    [userId, fixtureIds]
  );
  return rows;
}

// كل التوقعات غير المحتسبة لمباريات انتهت — مدخلات الاحتساب.
//
// user_id ليس مستخدماً في الاحتساب نفسه بل في ما بعده: الاحتساب هو
// اللحظة الوحيدة التي يمكن أن يُستحق فيها وسام جديد، وصاحب التوقع
// هو من يجب أن يُقيَّم. إخراجه هنا يوفر جولة ثانية للقاعدة تسأل
// "من أصحاب هذه التوقعات؟" بعد أن كانت الإجابة في يدنا أصلاً.
async function findUnsettled() {
  const { rows } = await db.query(
    `SELECT p.id, p.user_id, p.pred_home, p.pred_away, p.multiplier,
            f.goals_home, f.goals_away
     FROM predictions p
     JOIN fixtures f ON f.id = p.fixture_id
     WHERE p.settled_at IS NULL
       AND f.status = 'finished'
       AND f.goals_home IS NOT NULL AND f.goals_away IS NOT NULL`
  );
  return rows;
}

async function settle(id, points) {
  await db.query(
    `UPDATE predictions SET points = $2, settled_at = now() WHERE id = $1`,
    [id, points]
  );
}

// لوحة الصدارة: مجموع نقاط كل مستخدم.
// نحسب المجموع من التوقعات في كل مرة بدل تخزين عمود points في
// users: مصدر حقيقة واحد، لا يمكن أن ينحرف المجموع عن التفاصيل
// (لو أعاد الأدمن الاحتساب مثلاً). عند مئات آلاف المستخدمين نعيد
// النظر — ليس اليوم.
async function leaderboard(limit = 50) {
  const { rows } = await db.query(
    `SELECT u.id AS user_id,
            COALESCE(u.display_name, 'مشجع') AS display_name,
            u.avatar_url,
            u.favorite_team_id,
            ft.logo_url AS favorite_team_logo,
            COALESCE(SUM(p.points), 0)::int AS total_points,
            COUNT(*) FILTER (WHERE p.kind = 'match')::int AS settled_predictions
     FROM users u
     -- settled_at IS NOT NULL في شرط الضم لا في WHERE:
     -- من له توقعات لم تُحتسب بعد يجب ألا يظهر في العرش أصلاً، لا أن
     -- يظهر بصفر نقطة. وهذا نفس تعريف "المتنافس" في profileStats —
     -- ولولا توحيدهما لقال العرش إن المستخدم في المركز الرابع بينما
     -- يقول ملفه إنه لم ينافس بعد. رقمان لحقيقة واحدة.
     -- المصدر view لا جدول: النقاط تأتي من المباريات ورهانات
     -- الأبطال معاً، وجمعُهما في كل استعلام على حدة يخلق نسخاً
     -- تتباعد. راجع user_settled_points في migration 021.
     JOIN user_settled_points p ON p.user_id = u.id
     LEFT JOIN teams ft ON ft.id = u.favorite_team_id
     GROUP BY u.id, ft.logo_url
     ORDER BY total_points DESC, settled_predictions ASC
     LIMIT $1`,
    [limit]
  );
  return rows;
}

// السلسلتان من قائمة مرتبة زمنياً: أطول سلسلة إصابات متتالية،
// والسلسلة الجارية الآن.
//
// لماذا في JavaScript وليس في SQL؟ الحل في SQL هو نمط
// "gaps and islands": ترقيمان متداخلان بـ ROW_NUMBER يُطرح أحدهما
// من الآخر لتوليد معرّف مجموعة، ثم تجميع فوق تجميع. يعمل، لكنه
// استعلام لا يُقرأ إلا بمن كتبه — وصاحب هذا المشروع يعود إليه بعد
// نصف سنة. الحلقة أدناه يفهمها أي أحد من أول قراءة، والمدخلات
// عشرات أو مئات الصفوف لمستخدم واحد لا ملايين، فلا فرق في الأداء.
//
// القائمة مرتبة من الأقدم للأحدث، ولذلك قيمة run بعد انتهاء الحلقة
// هي بالضبط السلسلة الجارية: مرور واحد يعطي الرقمين معاً.
//
// مصدّرة لأن badgeService يمنح أوسمة السلسلة منها هو أيضاً: تعريف
// "السلسلة" في النظام واحد لا اثنان. لو حسبها الوسام بطريقته لظهر
// يوماً ملف يقول "أطول سلسلة: 5" ووسام "سلسلة خمسة" مطفأ بجانبه.
function computeStreaks(hits) {
  let longest = 0;
  let run = 0;
  for (const hit of hits) {
    run = hit ? run + 1 : 0; // أي توقع بلا نقاط يقطع السلسلة
    if (run > longest) longest = run;
  }
  return { longest_streak: longest, current_streak: run };
}

// إحصاءات شاشة "ملفي" كاملة في رد واحد.
//
// خمسة استعلامات متوازية بدل واحد عملاق: كل سؤال هنا مختلف الشكل
// (صف واحد، قائمة توزيع، قائمة جولات، عمود منطقي مرتب)، وحشرها
// معاً بـ json_agg متداخلة يجعل الاستعلام غير قابل للقراءة بلا
// مكسب — نفس القرار المشروح في userRepo.adminDetail. Promise.all
// تشغّلها معاً فتصل كلها بزمن أبطأها لا بمجموعها.
async function profileStats(userId) {
  const [standing, profile, distribution, form, streakRows] = await Promise.all([
    // 1) المركز وعدد المتنافسين.
    //
    // RANK() OVER يحسب المركز داخل القاعدة فوق كل المستخدمين. لا
    // يمكن اشتقاقه من leaderboard() أدناه: تلك محدودة بـ LIMIT 50،
    // ومن ترتيبه 51 لا يجد نفسه في القائمة فيبقى بلا مركز إطلاقاً.
    //
    // ORDER BY داخل النافذة نسخة حرفية من ORDER BY في leaderboard()،
    // وهذا شرط لا زينة: الرقم في ملف المستخدم والرقم في قائمة العرش
    // يجب ألا يختلفا أبداً. أي تعديل على ترتيب إحداهما يجب أن ينزل
    // على الأخرى في نفس اللحظة — ولهذا الدالتان متجاورتان في هذا
    // الملف عمداً، لا في وحدتين متباعدتين تنسى إحداهما الأخرى.
    //
    // RANK وليس ROW_NUMBER: المتساويان في النقاط وفي عدد التوقعات
    // المحتسبة متساويان في المركز فعلاً، وترقيمهما 4 و5 اعتباطاً
    // يجعل مركز المستخدم يتأرجح بين تحديث وآخر بلا سبب يفسره له.
    //
    // WHERE settled_at IS NOT NULL: المتنافس من لعب فعلاً. من سجّل
    // ولم يُحتسب له توقع واحد ليس "الأخير" — هو خارج المنافسة أصلاً،
    // فيرجع rank = NULL ويعرض له التطبيق حالة "لم تنافس بعد" بدل
    // مركز مهين بلا معنى. (فارق مقصود عن leaderboard() التي تضم
    // بـ JOIN كل من له توقع ولو لم يُحتسب؛ صاحب صفر محتسب يظهر هناك
    // بصفر نقطة ولا يُعدّ متنافساً هنا.)
    db.query(
      `WITH ranked AS (
         SELECT p.user_id,
                COALESCE(SUM(p.points), 0)::int AS total_points,
                COUNT(*) FILTER (WHERE p.kind = 'match')::int AS settled_predictions,
                RANK() OVER (ORDER BY COALESCE(SUM(p.points), 0) DESC,
                                      COUNT(*) FILTER (WHERE p.kind = 'match') ASC)::int AS rank
           FROM user_settled_points p
          GROUP BY p.user_id
       )
       -- LEFT JOIN من صف العدّ: يرجع صفاً واحداً دائماً، حتى لمن
       -- ليس في ranked — فيصل total_competitors ومعه rank فارغ.
       SELECT (SELECT COUNT(*) FROM ranked)::int AS total_competitors,
              r.rank, r.total_points, r.settled_predictions
         FROM (SELECT 1) AS always_one_row
         LEFT JOIN ranked r ON r.user_id = $1`,
      [userId]
    ),

    // 2) صف المستخدم: العدّاد الكلي، الدقة، والفريق المفضل.
    //
    // predictions_count يشمل غير المحتسب أيضاً (توقعات على مباريات
    // لم تُلعب بعد) — الرقم يقول "كم لعبتَ"، والمحتسب يأتي من (1).
    //
    // الدقة: مقامها المحتسبة وحدها، فتوقع على مباراة قادمة ليس خطأً
    // وحسابه ضمن النسبة يعاقب النشِط على نشاطه. NULLIF يمنع القسمة
    // على صفر، والنتيجة NULL لمن لا محتسب له — والتطبيق يفرّق بين
    // "لا بيانات" و"صفر بالمئة" بشاشتين مختلفتين، فلا نحوّل NULL
    // إلى صفر هنا إكراماً لنوع البيانات.
    db.query(
      `SELECT (SELECT COUNT(*) FROM predictions p
                WHERE p.user_id = u.id)::int AS predictions_count,
              (SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE p.points > 0)
                            / NULLIF(COUNT(*), 0))
                 FROM predictions p
                WHERE p.user_id = u.id AND p.settled_at IS NOT NULL)::int AS accuracy,
              u.favorite_team_id,
              COALESCE(ft.name_ar, ft.name_en) AS favorite_team_name,
              ft.logo_url                      AS favorite_team_logo
         FROM users u
         LEFT JOIN teams ft ON ft.id = u.favorite_team_id
        WHERE u.id = $1`,
      [userId]
    ),

    // 3) توزيع النقاط: كم مرة أخذ 7، كم مرة 3، كم مرة صفر.
    // لا نثبّت القيم (7/3/2/0) في الاستعلام: الأدمن يعدّلها من
    // app_settings، وأي قائمة مكتوبة هنا تصير كذباً بعد أول تعديل.
    // نسأل القاعدة عمّا حدث فعلاً فتأتي القيم الصحيحة دائماً.
    db.query(
      // points / multiplier لا points: التوزيع يجيب "كم مرة أصبتُ"
      // لا "كم جمعتُ". ولولا القسمة لانشقّ صفّ "نتيجة مضبوطة" إلى
      // صفّين (100 و200) يقولان الشيء نفسه، ولاصطدم المضاعَف
      // الأدنى بالمفرد الأعلى: اتجاه صحيح ×2 يساوي 100 وهو نفسه
      // ثمن النتيجة المضبوطة — فيُقرأ إصابةٌ لم تقع.
      // القسمة صحيحة تماماً لأن points حاصل ضرب في multiplier.
      `SELECT (points / multiplier) AS points, COUNT(*)::int AS count
         FROM predictions
        WHERE user_id = $1 AND settled_at IS NOT NULL
        GROUP BY 1
        ORDER BY 1 DESC`,
      [userId]
    ),

    // 4) شكل الأداء في آخر ٨ جولات — التطبيق يرسمها أعمدة صغيرة.
    //
    // الترتيب بـ MIN(kickoff_at) وليس بـ round: الجولة نص، و"Regular
    // Season - 10" يسبق "Regular Season - 2" أبجدياً فتخرج الأعمدة
    // بترتيب مقلوب بلا خطأ ظاهر. التاريخ هو الترتيب الحقيقي الوحيد.
    //
    // نأخذ آخر ٨ (DESC + LIMIT) ثم نعكس الترتيب في الغلاف الخارجي:
    // LIMIT يحتاج الأحدث أولاً ليعرف ما يقتطع، والعميل يحتاج الأقدم
    // أولاً ليرسم خط تطور يتقدم للأمام.
    // COUNT(*) في المقام لا يكون صفراً أبداً (كل مجموعة فيها صف
    // واحد على الأقل) فلا accuracy فارغة داخل القائمة، وهو شرط
    // العميل: قائمة فارغة مقبولة، وقيمة NULL داخلها ليست كذلك.
    db.query(
      `SELECT round, season, accuracy, settled
         FROM (
           SELECT f.round, f.season,
                  ROUND(100.0 * COUNT(*) FILTER (WHERE p.points > 0)
                        / COUNT(*))::int AS accuracy,
                  COUNT(*)::int          AS settled,
                  MIN(f.kickoff_at)      AS started_at
             FROM predictions p
             JOIN fixtures f ON f.id = p.fixture_id
            WHERE p.user_id = $1 AND p.settled_at IS NOT NULL AND f.round IS NOT NULL
            -- التجميع بالموسم مع الجولة، لا بالجولة وحدها: نص
            -- "Regular Season - 3" يتكرر حرفياً في كل موسم، وتجميعه
            -- وحده يدمج جولة هذا الموسم بجولة الموسم الماضي في عمود
            -- واحد بدقة مغلوطة — خطأ صامت لأن الناتج يبدو سليماً.
            -- والموسم يخرج للعميل مع الاسم: عند حدود الموسم تعود
            -- "الجولة 1" مرتين في نفس الرسم، وبلا الموسم يبدو ذلك
            -- خللاً لا حقيقة. العميل يميّزها به عند الحاجة فقط.
            GROUP BY f.season, f.round
            ORDER BY started_at DESC
            LIMIT 8
         ) recent
        ORDER BY started_at ASC`,
      [userId]
    ),

    // 5) مدخلات السلسلتين: أصاب أم لا، بترتيب انطلاق المباريات.
    // الترتيب بموعد المباراة لا بموعد كتابة التوقع: السلسلة تصف
    // أداءه في المباريات كما جرت، ومن يكتب توقعاته دفعة واحدة
    // مقدماً ليس له ترتيب آخر. fixture_id فاصل ثانوي حتى يكون
    // الترتيب قاطعاً لمباراتين تنطلقان في اللحظة نفسها.
    db.query(
      `SELECT (p.points > 0) AS hit
         FROM predictions p
         JOIN fixtures f ON f.id = p.fixture_id
        WHERE p.user_id = $1 AND p.settled_at IS NOT NULL
        ORDER BY f.kickoff_at ASC, p.fixture_id ASC`,
      [userId]
    ),
  ]);

  const s = standing.rows[0];
  const u = profile.rows[0];
  if (!u) return null; // الحساب اختفى بين الحارس وهذه اللحظة

  // الأصفار الحقيقية للمستخدم الجديد: التطبيق يعرض "0 توقع" بثقة،
  // ولا يحتاج التعامل مع null في كل حقل. الاستثناءان الوحيدان هما
  // rank و accuracy — وغيابهما معلومة مقصودة لا نقص بيانات.
  return {
    rank: s.rank ?? null,
    total_competitors: s.total_competitors,
    total_points: s.total_points ?? 0,
    predictions_count: u.predictions_count,
    settled_predictions: s.settled_predictions ?? 0,
    accuracy: u.accuracy ?? null,
    ...computeStreaks(streakRows.rows.map((r) => r.hit)),
    points_distribution: distribution.rows,
    recent_form: form.rows,
    favorite_team: u.favorite_team_id
      ? { id: u.favorite_team_id, name: u.favorite_team_name, logo_url: u.favorite_team_logo }
      : null,
  };
}

module.exports = {
  upsert,
  countMultiplied,
  findMine,
  findByUserAndFixtures,
  findUnsettled,
  settle,
  leaderboard,
  computeStreaks,
  profileStats,
};
