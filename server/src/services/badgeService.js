// badgeService — كتالوج الأوسمة وقواعد نيلها.
//
// الوسام يُنال مرة ولا يُفقد: القاعدة تُفحص كل مرة، لكن الصف يُكتب
// أول مرة فقط (المفتاح المركّب في الهجرة 011). فمن نال "سلسلة عشرة"
// ثم انقطعت سلسلته يحتفظ بالوسام — الإنجاز حدث، ومحوه لاحقاً يعاقب
// المستخدم على استمراره في اللعب.
//
// الكتالوج قائمة مرتبة لا كائن: التطبيق يرسم الشبكة بهذا الترتيب
// بالضبط، فترتيب السطور هنا قرار تصميم لا تفصيل تنفيذ. والتدرج
// مقصود — الأسهل أولاً كي لا تبدأ الشاشة بصفّ كامل من الأوسمة
// المطفأة المستحيلة.
const badgeRepo = require('../repositories/badgeRepo');
const { computeStreaks } = require('../repositories/predictionRepo');
const premiumService = require('./premiumService');
const logger = require('../utils/logger');

// أزواج الديربي.
//
// قائمة تحريرية من عندنا، وليست بياناً يرسله المزوّد: لا يوجد في
// API-Football حقل يقول "هذه مباراة ديربي" — الفكرة ثقافية لا
// إحصائية. ولهذا نتيجتان عمليتان:
//   • إضافة دوري جديد للتطبيق تعني مراجعة هذه القائمة، وإلا بقي
//     وسام الديربي حكراً على السعودية بينما يلعب المستخدم في دوري آخر.
//   • أي خلاف على "ما الديربي؟" يُحسم هنا بسطر، لا بهجرة قاعدة بيانات.
// المعرّفات هي معرّفات المزوّد نفسها (انظر 001_init.sql).
const DERBIES = [
  [2932, 2939], // ديربي الرياض: الهلال × النصر
  [2938, 2929], // ديربي جدة: الاتحاد × الأهلي
];

// عتبة رتبة "الملك" في سلّم الرتب
// (مشجّع 0 · لاعب 500 · فارس 1500 · أمير 3000 · الملك 5000).
// السلّم نفسه يعيش في العميل لأنه عرض بحت، وما يهم السيرفر منه
// عتبة واحدة: الوسام يجب أن يضيء في نفس اللحظة التي يقول فيها
// التطبيق "الملك"، فرقم واحد مشترك أضمن من قائمة مكررة.
const KING_POINTS = 5000;

// كل وسام: مفتاحه، اسمه، شرطه كما يُقرأ تحت الوسام المطفأ، ودالة
// فحصه فوق وقائع جاهزة. الفحص لا يلمس القاعدة: الوقائع تُجمع مرة
// واحدة في collectFacts، فإضافة وسام جديد لا تضيف جولة إلى القاعدة
// ما دام يُقرأ من نفس الوقائع.
const BADGES = [
  {
    key: 'first_pick',
    title: 'أول توقّع',
    requirement: 'سجّل توقعك الأول',
    check: (f) => f.predictions_count >= 1,
  },
  {
    key: 'exact_score',
    title: 'نتيجة مضبوطة',
    requirement: 'أصب نتيجة مباراة بالضبط',
    check: (f) => f.has_exact,
  },
  {
    key: 'streak_5',
    title: 'سلسلة خمسة',
    requirement: 'خمسة توقعات صحيحة متتالية',
    check: (f) => f.longest_streak >= 5,
  },
  {
    key: 'streak_10',
    title: 'سلسلة عشرة',
    requirement: 'عشرة توقعات صحيحة متتالية',
    check: (f) => f.longest_streak >= 10,
  },
  {
    key: 'full_round',
    title: 'جولة كاملة',
    requirement: 'توقّع كل مباريات جولة واحدة',
    check: (f) => f.full_round,
  },
  {
    key: 'against_crowd',
    title: 'ضد الجمهور',
    requirement: 'أصب بينما أخطأت الأغلبية',
    check: (f) => f.against_crowd,
  },
  {
    key: 'derby',
    title: 'ديربي',
    requirement: 'أصب نتيجة ديربي',
    check: (f) => f.has_derby,
  },
  {
    key: 'century',
    title: 'مئة توقّع',
    requirement: 'سجّل مئة توقّع',
    check: (f) => f.predictions_count >= 100,
  },
  {
    key: 'king',
    title: 'الملك',
    requirement: 'ابلغ رتبة الملك — 5000 نقطة',
    check: (f) => f.total_points >= KING_POINTS,
  },
];

function isDerby(homeTeamId, awayTeamId) {
  // الاتجاهان سواء: الديربي هو اللقاء، لا من يستضيف فيه.
  return DERBIES.some(
    ([a, b]) =>
      (homeTeamId === a && awayTeamId === b) || (homeTeamId === b && awayTeamId === a)
  );
}

// من صفوف القاعدة إلى الوقائع التي تفحصها الأوسمة.
//
// مرور واحد على التوقعات المحتسبة يعطي أربعاً منها: السلسلة، والنتيجة
// المضبوطة، والديربي، ومجموع النقاط. القائمة عشرات أو مئات الصفوف
// لمستخدم واحد، فالحلقة أوضح من أربعة استعلامات وأسرع منها.
function deriveFacts(raw, shield = undefined) {
  // الاستيراد داخل الدالة لا في رأس الملف عمداً: scoringService
  // يستورد هذا الملف ليمنح الأوسمة بعد الاحتساب، ولو استوردناه في
  // الرأس لصارت الدورة مغلقة — CommonJS يعطي أحد الملفين كائناً
  // ناقصاً حسب أيهما حُمّل أولاً، والعطل يظهر وقت التشغيل فقط
  // (computeState is not a function). التأجيل يفك الدورة: حين تُنفَّذ
  // هذه الدالة يكون الملف الآخر مكتملاً في ذاكرة require.
  const { computeState } = require('./scoringService');

  let total_points = 0;
  let has_exact = false;
  let has_derby = false;

  for (const r of raw.timeline) {
    total_points += r.points;

    // "مضبوطة" تعريفها الوحيد في النظام هو computeState — نفس الدالة
    // التي تمنح النقاط وتضيء الشارة في تبويب "مباشر". لو تغيّرت
    // القاعدة يوماً (ركلات الترجيح مثلاً) تغيّر الوسام معها بلا تدخل.
    if (!has_exact) {
      const state = computeState(
        { home: r.pred_home, away: r.pred_away },
        { home: r.goals_home, away: r.goals_away }
      );
      if (state === 'exact') has_exact = true;
    }

    // الديربي يحتاج إصابة لا مجرد مشاركة: الشرط "أصب نتيجة ديربي".
    if (!has_derby && r.points > 0 && isDerby(r.home_team_id, r.away_team_id)) {
      has_derby = true;
    }
  }

  // السلسلة من computeStreaks نفسها التي تغذي شاشة "ملفي" — تعريف
  // واحد للسلسلة في النظام كله. نسخة ثانية هنا كانت ستتفق معها اليوم
  // وتخالفها أول مرة يتغير فيها أحدهما، فيرى المستخدم "أطول سلسلة: 5"
  // ووسام السلسلة مطفأ في نفس الشاشة.
  const { longest_streak } = computeStreaks(
    raw.timeline.map((r) => ({ hit: r.points > 0, at: r.at })), shield);

  return {
    predictions_count: raw.predictions_count,
    full_round: raw.full_round,
    against_crowd: raw.against_crowd,
    total_points,
    has_exact,
    has_derby,
    longest_streak,
  };
}

// فحص كل الأوسمة لمستخدم، ومنح ما استحقه ولم ينله بعد.
// يرجع مفاتيح ما نيل الآن لأول مرة (فارغة = لا جديد).
async function evaluate(userId) {
  // الدرع يدخل في تعريف السلسلة، فوسام "سلسلة خمسة" يجب أن يقرأه
  // بنفس خيارات شاشة "ملفي". قراءته هنا لا في المستدعي: للفحص
  // مستدعيان (شاشة الملف، ومحرّك الاحتساب بعد كل جولة) ونسيانه في
  // أحدهما يمنح وساماً لا يراه صاحبه أو يمنع وساماً استحقه.
  const shield = await premiumService.shieldFor(userId);
  const facts = deriveFacts(await badgeRepo.collectFacts(userId), shield);
  const deserved = BADGES.filter((b) => b.check(facts)).map((b) => b.key);

  // نرسل المستحق كله لا الجديد منه: تمييز الجديد يحتاج قراءة ما نيل
  // سابقاً (جولة إضافية) بينما القاعدة تكفلت به — ON CONFLICT يسقط
  // القديم وRETURNING يخبرنا بالجديد. فحصان لنفس السؤال، أحدهما
  // مجاني وذري (atomic) والآخر عرضة لسباق بين قراءتين.
  return badgeRepo.award(userId, deserved);
}

// نسخة لا تُسقط ما استدعاها مهما حدث.
//
// الأوسمة زينة والنقاط هي المنتج: خطأ في استعلام وسام يجب ألا يوقف
// احتساب نقاط جولة كاملة، ولا أن يحوّل شاشة "ملفي" إلى 500 بينما
// كل أرقامها جاهزة. نسجّل ونكمل. (وevaluate الصريحة تبقى مصدّرة
// لسكربت التعبئة: هناك نريد الخطأ ظاهراً لا مبتلعاً.)
async function evaluateQuietly(userId) {
  try {
    const awarded = await evaluate(userId);
    if (awarded.length > 0) {
      logger.info(`[badges] awarded ${awarded.join(', ')} to ${userId}`);
    }
    return awarded;
  } catch (err) {
    logger.error(`[badges] evaluation failed for ${userId}:`, err.message);
    return [];
  }
}

// الكتالوج كاملاً بحالة كل وسام لهذا المستخدم — هذا ما يذهب للتطبيق.
//
// غير المكتسب يخرج أيضاً وبشرطه: رؤية ما لم تنله بعد هي نصف فائدة
// الشاشة، والوسام المطفأ بلا شرط تحته لغز لا هدف.
// نمر على الكتالوج لا على صفوف القاعدة: الترتيب يبقى ثابتاً، ومفتاح
// قديم بقي في الجدول بعد حذفه من الكتالوج لا يظهر بلا اسم.
async function forUser(userId) {
  const rows = await badgeRepo.listEarned(userId);
  const earnedAt = new Map(rows.map((r) => [r.badge_key, r.earned_at]));

  return BADGES.map(({ key, title, requirement }) => ({
    key,
    title,
    requirement,
    earned: earnedAt.has(key),
    earned_at: earnedAt.get(key) ?? null,
  }));
}

module.exports = { BADGES, DERBIES, KING_POINTS, evaluate, evaluateQuietly, forUser };
