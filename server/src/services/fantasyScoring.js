// fantasyScoring — نقاط لاعب كرة واحد في مباراة واحدة.
//
// أخته scoringService تحتسب نقاط **التوقّعات**، وهذه نقاط
// **الفانتازي**، وهما لعبتان لا لعبة بمقياسين (راجع FANTASY.md).
// ملفان منفصلان عمداً: خلطهما في ملف واحد يجعل تعديل سعر الهدف
// في الفانتازي يمرّ بجوار سعر «النتيجة المضبوطة» في التوقّعات،
// وأول خطأ نسخٍ هناك يفسد اللعبتين معاً.
//
// الدالة الجوهرية صافية (pure): إحصاء + جدول → رقم. بلا قاعدة
// بيانات ولا حالة، فتُختبر بأمثلة ورقية ويستعملها الحيّ والمنتهي
// على السواء — نفس سبب computeState هناك.
const settingsRepo = require('../repositories/settingsRepo');

/**
 * الجدول الاحتياطي لو غاب صفّ الإعدادات. القيم الحقيقية في
 * `app_settings.fantasy_scoring` ويعدّلها الأدمن بلا نشر.
 *
 * والمفاتيح بأسماء المراكز كما يخزّنها جدول players حرفياً
 * (Goalkeeper / Defender / Midfielder / Attacker)، فالربط بحثٌ
 * في كائن لا سلسلة شروط تقول نفس الشيء.
 */
const DEFAULT_FANTASY_SCORING = {
  // اللعب نفسه: نقطة لمن نزل، واثنتان لمن أكمل ستين دقيقة.
  // العتبة هي ما يجعل «شارك دقيقتين» أقلّ من «لعب مباراة».
  appearance: 1,
  full_appearance: 2,
  full_minutes: 60,

  goal: { Goalkeeper: 6, Defender: 6, Midfielder: 5, Attacker: 4 },
  assist: 3,

  // الشباك النظيفة لمن أكمل ستين دقيقة: من خرج في الأربعين
  // والفريق نظيف وقتها لم يحرس شيئاً حتى النهاية.
  clean_sheet: { Goalkeeper: 4, Defender: 4, Midfielder: 1, Attacker: 0 },

  // كل هدفين — لا كل هدف: العقوبة على الانهيار لا على الهدف
  // الواحد الذي يقع في أفضل الدفاعات.
  conceded_per: 2,
  conceded_penalty: { Goalkeeper: -1, Defender: -1, Midfielder: 0, Attacker: 0 },

  saves_per: 3,
  save_points: 1,

  penalty_saved: 5,
  penalty_missed: -2,
  yellow: -1,
  red: -3,
  own_goal: -2,

  // مضاعِف الكابتن. في كائن الإعدادات لا ثابتاً في الشيفرة: قد
  // نجرّب ×٣ في جولة احتفالية بلا نشر نسخة.
  captain_multiplier: 2,
};

/** قيمة من جدولٍ قد يكون رقماً واحداً أو كائناً بالمراكز. */
function byPosition(value, position, fallback = 0) {
  if (typeof value === 'number') return value;
  return value?.[position] ?? fallback;
}

/**
 * نقاط لاعب في مباراة.
 *
 * @param stat صفّ من player_fixture_stats (خام لا نقاط).
 * @param position مركزه كما في players.position.
 * @param cfg الجدول من الإعدادات.
 * @returns {{points:number, lines:Array<{label:string,points:number}>}}
 *
 * ولماذا `lines` مع الرقم؟ لأن شاشة «نقاط الجولة» يجب أن تجيب
 * «من أين جاءت هذه النقاط؟» بلا أن تعيد الحساب بنفسها — وإعادة
 * الحساب في العميل هي بالضبط الطريق إلى شاشة تقول ٩ وخادمٍ
 * يقول ٨، وهو خلافٌ يقرأه اللاعب سرقةً لا خطأً.
 */
function computePlayerPoints(stat, position, cfg = DEFAULT_FANTASY_SCORING) {
  const lines = [];
  const add = (label, points) => {
    if (points) lines.push({ label, points });
  };

  const minutes = stat.minutes ?? 0;
  // لا دقائق = لا شيء، ولا حتى عقوبة. من لم ينزل لم يخطئ.
  if (minutes <= 0) return { points: 0, lines };

  add(
    minutes >= cfg.full_minutes ? 'لعب المباراة' : 'شارك',
    minutes >= cfg.full_minutes ? cfg.full_appearance : cfg.appearance
  );

  if (stat.goals) {
    add(`${stat.goals} هدف`, stat.goals * byPosition(cfg.goal, position));
  }
  if (stat.assists) {
    add(`${stat.assists} صناعة`, stat.assists * byPosition(cfg.assist, position, cfg.assist));
  }

  const conceded = stat.conceded ?? 0;
  if (conceded === 0 && minutes >= cfg.full_minutes) {
    add('شباك نظيفة', byPosition(cfg.clean_sheet, position));
  } else if (conceded > 0) {
    // القسمة الصحيحة: ثلاثة أهداف عقوبتها كهدفين، والرابع يبدأ
    // شطراً جديداً. هذا هو المعيار المعروف، وكسرُه يفاجئ اللاعب.
    const chunks = Math.floor(conceded / cfg.conceded_per);
    add(`دخل مرماه ${conceded}`, chunks * byPosition(cfg.conceded_penalty, position));
  }

  if (stat.saves) {
    add(`${stat.saves} تصدٍّ`, Math.floor(stat.saves / cfg.saves_per) * cfg.save_points);
  }
  if (stat.pen_saved) add('صدّ ركلة جزاء', stat.pen_saved * cfg.penalty_saved);
  if (stat.pen_missed) add('أهدر ركلة جزاء', stat.pen_missed * cfg.penalty_missed);
  if (stat.yellow) add('بطاقة صفراء', stat.yellow * cfg.yellow);
  if (stat.red) add('بطاقة حمراء', stat.red * cfg.red);
  if (stat.own_goals) add('هدف في مرماه', stat.own_goals * cfg.own_goal);

  return {
    points: lines.reduce((sum, l) => sum + l.points, 0),
    lines,
  };
}

/** الجدول الفعلي من الإعدادات، مدموجاً فوق الاحتياطي. */
async function config() {
  const saved = await settingsRepo.get('fantasy_scoring');
  // دمج سطحي لا استبدال: لوحةٌ حفظت `goal` وحدها يجب ألا تمحو
  // بقية الجدول فتصير كل البطاقات بلا عقوبة.
  return { ...DEFAULT_FANTASY_SCORING, ...(saved || {}) };
}

module.exports = {
  computePlayerPoints,
  config,
  DEFAULT_FANTASY_SCORING,
};
