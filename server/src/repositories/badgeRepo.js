// badgeRepo — تعامل جدول user_badges مع القاعدة، وجمع الوقائع التي
// تُبنى عليها قواعد الأوسمة.
//
// القواعد نفسها ليست هنا بل في services/badgeService: هذا الملف
// يجيب عن "ماذا فعل المستخدم؟" لا عن "هل يستحق الوسام؟".
const db = require('../config/db');

// وقائع مستخدم واحد: كل ما تحتاجه الأوسمة التسعة، في جولتين اثنتين.
//
// لماذا لا استعلام لكل وسام؟ تسع جولات إلى القاعدة لكل احتساب ولكل
// فتح للملف الشخصي، وأغلبها يسأل الجدول نفسه بصياغة مختلفة قليلاً.
// ولماذا لا استعلام واحد عملاق؟ لأن السؤالين هنا مختلفا الشكل فعلاً:
// الأول قائمة صفوف مرتبة زمنياً (السلسلة والنتيجة المضبوطة والديربي
// تُقرأ منها بمرور واحد في JS)، والثاني ثلاثة أرقام/أعلام مجمّعة.
// حشرهما معاً يجعل الاستعلام غير قابل للقراءة بلا مكسب — نفس القرار
// المشروح في predictionRepo.profileStats. وPromise.all تجعل زمنهما
// زمن أبطأهما لا مجموعهما.
async function collectFacts(userId) {
  const [timeline, aggregates] = await Promise.all([
    // 1) التوقعات المحتسبة بترتيب المباريات كما جرت.
    //
    // الترتيب نسخة حرفية من استعلام السلسلة في profileStats، وهذا
    // شرط لا زينة: وسام "سلسلة خمسة" يجب أن يُمنح بالضبط حين يقول
    // الملف الشخصي "أطول سلسلة: 5". لو رتّبنا هنا بـ created_at
    // مثلاً لظهر للمستخدم رقم في شاشته ووسام يخالفه.
    //
    // نرجع pred/goals الخام لا حكماً جاهزاً: تصنيف "نتيجة مضبوطة"
    // له تعريف واحد في النظام (scoringService.computeState)، وكتابته
    // ثانية هنا بلغة SQL يخلق نسخة ثانية تنحرف عند أول تعديل على
    // القاعدة. الصفوف تخرج خاماً وتُصنَّف هناك.
    db.query(
      `SELECT p.points, p.pred_home, p.pred_away,
              f.goals_home, f.goals_away,
              f.home_team_id, f.away_team_id
         FROM predictions p
         JOIN fixtures f ON f.id = p.fixture_id
        WHERE p.user_id = $1 AND p.settled_at IS NOT NULL
        ORDER BY f.kickoff_at ASC, p.fixture_id ASC`,
      [userId]
    ),

    // 2) ما لا يُقرأ من قائمة صفوف: عدّاد كلي وسؤالان يقارنان
    //    المستخدم بغيره أو بجدول المباريات كاملاً.
    db.query(
      `SELECT
         -- عدّاد "كم توقعاً سجّل" — يشمل غير المحتسب: أوسمة العدّ
         -- (أول توقّع، مئة توقّع) تكافئ المشاركة لا الإصابة، ومن
         -- توقّع مئة مباراة لم تُلعب بعد شارك مئة مرة فعلاً.
         (SELECT COUNT(*) FROM predictions WHERE user_id = $1)::int AS predictions_count,

         -- جولة كاملة: توجد (موسم، جولة) توقّع فيها المستخدم كل
         -- مبارياتها. LEFT JOIN مقيّد بالمستخدم ثم COUNT(p.id) مقابل
         -- COUNT(*): الأول يعدّ ما توقّعه، والثاني يعدّ مباريات
         -- الجولة كلها، وتساويهما هو تعريف "كاملة" حرفياً.
         -- شرط الجولتين فأكثر يمنع جولة يتيمة (مباراة مؤجلة وحيدة
         -- تحمل اسم جولة) من أن تصير إنجازاً بتوقع واحد.
         EXISTS (
           SELECT 1
             FROM fixtures f
             LEFT JOIN predictions p ON p.fixture_id = f.id AND p.user_id = $1
            WHERE f.round IS NOT NULL
            GROUP BY f.season, f.round
           HAVING COUNT(*) >= 2 AND COUNT(p.id) = COUNT(*)
         ) AS full_round,

         -- ضد الجمهور: أصاب في مباراة أخطأت فيها الأغلبية.
         --
         -- الضم هنا صف المستخدم × كل التوقعات المحتسبة لنفس المباراة،
         -- فيصير COUNT(*) عدد المتوقعين وFILTER عدد المصيبين — وهما
         -- ما تحتاجه القاعدة. والمستخدم نفسه ضمن العدّين لأنه واحد من
         -- جمهور المباراة فعلاً.
         --
         -- عتبة الخمسة متوقعين هي روح الوسام: "أنت وشخص آخر أخطأ"
         -- ليس تحدياً للجمهور بل صدفة بين اثنين، ومنح الوسام عليها
         -- يجعله بلا قيمة في الأسابيع الأولى للتطبيق حين تكون كل
         -- مباراة بمتوقعَين. خمسة أقل عدد يصح فيه القول "الأغلبية".
         --
         -- hits * 2 < total بدل قسمة: القسمة الصحيحة في SQL تبتر،
         -- والضرب يقارن أعداداً صحيحة بلا كسور ولا حالة حدّية غامضة
         -- (عند التعادل تماماً لا وسام — الأغلبية لم تخطئ).
         EXISTS (
           SELECT 1
             FROM predictions mine
             JOIN predictions crowd
               ON crowd.fixture_id = mine.fixture_id AND crowd.settled_at IS NOT NULL
            WHERE mine.user_id = $1 AND mine.settled_at IS NOT NULL AND mine.points > 0
            GROUP BY mine.fixture_id
           HAVING COUNT(*) >= 5
              AND COUNT(*) FILTER (WHERE crowd.points > 0) * 2 < COUNT(*)
         ) AS against_crowd`,
      [userId]
    ),
  ]);

  return { timeline: timeline.rows, ...aggregates.rows[0] };
}

// منح مجموعة أوسمة دفعة واحدة، وإرجاع الجديد منها فقط.
//
// unnest تحوّل مصفوفة نصوص إلى صفوف، فيمر الإدراج كله في جملة واحدة
// بدل حلقة بتسع جولات. وON CONFLICT DO NOTHING هو ضمان عدم التكرار
// المشروح في الهجرة 011: المكرر يسقط بصمت ولا يلمس earned_at.
//
// RETURNING يعيد ما أُدرج فعلاً — أي ما نيل الآن لأول مرة. هذه هي
// الطريقة الوحيدة للتمييز بين "منحناه خمسة أوسمة" و"تحققنا من خمسة
// وكلها قديمة"، وعليها يقوم سجل الاحتساب وملخص سكربت التعبئة.
async function award(userId, badgeKeys) {
  if (badgeKeys.length === 0) return []; // لا داعي لجولة إلى القاعدة
  const { rows } = await db.query(
    `INSERT INTO user_badges (user_id, badge_key)
     SELECT $1, k FROM unnest($2::text[]) AS k
     ON CONFLICT DO NOTHING
     RETURNING badge_key`,
    [userId, badgeKeys]
  );
  return rows.map((r) => r.badge_key);
}

// ما ناله المستخدم ومتى. الترتيب من الكتالوج لا من هنا، لذلك لا
// ORDER BY: العميل يرسم الشبكة بترتيب ثابت متفق عليه في badgeService.
async function listEarned(userId) {
  const { rows } = await db.query(
    `SELECT badge_key, earned_at FROM user_badges WHERE user_id = $1`,
    [userId]
  );
  return rows;
}

module.exports = { collectFacts, award, listEarned };
