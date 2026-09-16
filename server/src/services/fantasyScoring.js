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

  // نقاط الإضافة: ما يناله أفضل ثلاثة في كل مباراة.
  //
  // ثلاثةٌ لا واحد: «أفضل لاعب» وحده يعطي دفعةً أو لا شيء، ومن
  // كان ثانياً بفارق نقطةٍ في المؤشّر يخرج كمن لم يلعب. والثلاثة
  // تجعل الأداء الجيّد يُكافأ وإن لم يكن الأفضل.
  bonus_first: 3,
  bonus_second: 2,
  bonus_third: 1,
};

/**
 * أوزان مؤشّر الأداء (BPS) — رقمٌ خام يُرتَّب به لاعبو المباراة،
 * ثم يأخذ أعلى ثلاثة نقاطَ الإضافة.
 *
 * **في الشيفرة لا في الإعدادات** عمداً، بخلاف جدول النقاط: هذه
 * أوزانُ مقياسٍ لا قيمُ مكافأة. تعديل «الهدف ٤ نقاط» يغيّر ما
 * يناله اللاعب ويُفهم في سطر، وتعديل «وزن الهدف في المؤشّر ٢٤»
 * لا يغيّر شيئاً وحده — إنما يغيّر ترتيباً نسبياً بين لاعبين،
 * وهو ما لا يمكن لأحد أن يقدّر أثره من لوحة. وما يُعدَّل من
 * اللوحة هو ٣/٢/١ أعلاه: المكافأة نفسها.
 *
 * والأوزان مقيسة على المعيار المعروف في الفانتازي كي يُقرأ
 * الترتيب مفهوماً لمن لعبها قبلنا.
 */
const BPS_WEIGHTS = {
  played: 3,
  // أكمل الستين: بدل الثلاثة لا فوقها — ستّ لمن لعب مباراة.
  full: 6,
  full_minutes: 60,
  goal: { Goalkeeper: 12, Defender: 12, Midfielder: 18, Attacker: 24 },
  assist: 9,
  clean_sheet: { Goalkeeper: 12, Defender: 12, Midfielder: 0, Attacker: 0 },
  save: 2,
  penalty_saved: 15,
  penalty_missed: -6,
  conceded_per: 2,
  conceded: { Goalkeeper: -4, Defender: -4, Midfielder: 0, Attacker: 0 },
  yellow: -3,
  red: -9,
  own_goal: -6,
};

/** ترتيب المكافآت من الأعلى — يُقرأ منه أيضاً اسم السطر. */
function bonusAwards(cfg) {
  return [cfg.bonus_first ?? 0, cfg.bonus_second ?? 0, cfg.bonus_third ?? 0];
}

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

  // نقاط الإضافة آخر سطر لا أوّله: هي حكمٌ على المباراة كلها
  // يُقرأ بعد ما بُني عليه، ومن رآها أولاً قرأ رقماً بلا سبب.
  if (stat.bonus) {
    const [first] = bonusAwards(cfg);
    add(
      stat.bonus >= first ? 'أفضل لاعب في المباراة' : 'من أفضل ثلاثة',
      stat.bonus
    );
  }

  return {
    points: lines.reduce((sum, l) => sum + l.points, 0),
    lines,
  };
}

/**
 * مؤشّر أداء لاعب في مباراة — رقمٌ خام لا نقاط.
 *
 * مقياسٌ لا مكافأة: لا يُعرض للاعب ولا يُجمع في حصيلته، وكل
 * وظيفته أن يرتّب اثنين وعشرين لاعباً في مباراةٍ واحدة كي نعرف
 * أيّهم الثلاثة. ولهذا أرقامه بالعشرات: الفروق الصغيرة يجب أن
 * تُميّز لا أن تتساوى.
 */
function bonusIndex(stat, position) {
  const w = BPS_WEIGHTS;
  const minutes = stat.minutes ?? 0;
  if (minutes <= 0) return 0;

  let bps = minutes >= w.full_minutes ? w.full : w.played;

  bps += (stat.goals ?? 0) * byPosition(w.goal, position);
  bps += (stat.assists ?? 0) * w.assist;

  const conceded = stat.conceded ?? 0;
  if (conceded === 0 && minutes >= w.full_minutes) {
    bps += byPosition(w.clean_sheet, position);
  } else if (conceded > 0) {
    bps += Math.floor(conceded / w.conceded_per) * byPosition(w.conceded, position);
  }

  bps += (stat.saves ?? 0) * w.save;
  bps += (stat.pen_saved ?? 0) * w.penalty_saved;
  bps += (stat.pen_missed ?? 0) * w.penalty_missed;
  bps += (stat.yellow ?? 0) * w.yellow;
  bps += (stat.red ?? 0) * w.red;
  bps += (stat.own_goals ?? 0) * w.own_goal;

  return Math.round(bps);
}

/**
 * توزيع نقاط الإضافة على لاعبي **مباراة واحدة**.
 *
 * يكتب `bps` و`bonus` في صفوف الإحصاء نفسها ويعيدها: محرّك النقاط
 * يقرأ `stat.bonus` بعدها بسطر، ونسخةٌ ثانية من الصفوف تعني
 * إحصاءً يحمل الإضافة وآخر لا يحملها في نفس النداء.
 *
 * **والتعادل يتقاسم ولا يُكسر.** من تساوى مؤشّرهما لعبا سواءً،
 * وكسرُ التعادل بتقييم المزوّد يعني أن رأياً — لا حدثاً — هو من
 * أعطى النقطة، وهو أول ما يُشتكى منه حين يخسر أحدهم جولته بها.
 * فالمتعادلان في القمة يأخذان ٣ معاً، ومن بعدهما ١ لا ٢: ترتيبه
 * الثالث لأن اثنين فوقه.
 */
function awardBonus(fixtureStats, cfg = DEFAULT_FANTASY_SCORING) {
  const awards = bonusAwards(cfg);

  for (const s of fixtureStats) {
    s.bps = bonusIndex(s, s.position);
    s.bonus = 0;
  }

  const eligible = fixtureStats.filter((s) => (s.minutes ?? 0) > 0 && s.bps > 0);
  for (const s of eligible) {
    // عدد من هو أعلى منه فعلاً — لا موقعه في المصفوفة: المصفوفة
    // ترتّب المتعادلين اعتباطاً، وهذا يمنحهما نفس الرتبة.
    const above = eligible.filter((o) => o.bps > s.bps).length;
    s.bonus = awards[above] ?? 0;
  }

  return fixtureStats;
}

/**
 * نقاط كل صفّ إحصاء في دفعةٍ من المباريات، والإضافة قبلها.
 *
 * والترتيب هو الفائدة: الإضافة تُوزَّع على المباراة كاملةً
 * (ترتيبٌ بين لاعبيها)، والنقاط تُحتسب للاعب وحده — فلو حُسبت
 * النقاط أولاً لخرج كل لاعب بلا إضافته. وكلا المستدعيَين
 * (التسوية والـbackfill) كان يكتب هذا الترتيب بنفسه، ونسختان
 * منه تفترقان عند أول تعديل.
 */
function scoreFixtureStats(stats, cfg = DEFAULT_FANTASY_SCORING) {
  const byFixture = new Map();
  for (const s of stats) {
    if (!byFixture.has(s.fixture_id)) byFixture.set(s.fixture_id, []);
    byFixture.get(s.fixture_id).push(s);
  }
  for (const rows of byFixture.values()) awardBonus(rows, cfg);

  return stats.map((s) => ({
    fixture_id: s.fixture_id,
    player_id: s.player_id,
    bps: s.bps ?? 0,
    bonus: s.bonus ?? 0,
    points: computePlayerPoints(s, s.position, cfg).points,
  }));
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
  bonusIndex,
  awardBonus,
  scoreFixtureStats,
  config,
  DEFAULT_FANTASY_SCORING,
  BPS_WEIGHTS,
};
