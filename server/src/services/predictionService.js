// predictionService — قواعد التوقّع، في مكان واحد.
//
// كانت هذه القواعد داخل routes/predictions مباشرة، وذلك كافٍ ما دام
// للتطبيق باب واحد. ثم صار للموقع باب ثانٍ — ونسخ القواعد في
// الملفين يعني أن أول تعديل عليها (تغيير حد الأرقام، أو السماح
// بالتعديل بعد الانطلاق بدقيقة) يجب تذكّره مرتين، وأن نسيانه يفتح
// ثغرة نزاهة في الباب المنسي لا خطأ ظاهراً.
//
// القاعدة الذهبية هنا: لا توقّع بعد الانطلاق. كل ما عداها تفاصيل.
const settingsRepo = require('../repositories/settingsRepo');
const { DEFAULT_SCORING, DEFAULT_MULTIPLIERS } = require('./scoringService');
const predictionRepo = require('../repositories/predictionRepo');
const fixtureRepo = require('../repositories/fixtureRepo');

/** خطأ متوقّع برمز HTTP ورسالة صالحة للعرض — نفس عقد AuthError. */
class PredictionError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
    this.expose = true;
  }
}

const MAX_GOALS = 99;

/**
 * تسجيل توقّع أو تعديله. UPSERT: نفس المسار للاثنين.
 *
 * fixtureRepo.findById مقيّد بدوريات in_app (راجع FIXTURE_FROM)،
 * فالتوقّع على دوري يُعرض في الموقع ولا يدخل اللعبة يرد 404 من
 * نفسه — بلا فحص إضافي هنا يمكن نسيانه.
 */
async function submit({ userId, fixtureId, home, away, multiplier = null }) {
  // Number.isInteger ترفض "2" النصية و 2.5 و null دفعة واحدة.
  if (!Number.isInteger(fixtureId) ||
      !Number.isInteger(home) || !Number.isInteger(away) ||
      home < 0 || home > MAX_GOALS || away < 0 || away > MAX_GOALS) {
    throw new PredictionError(400, `التوقّع يجب أن يكون رقمين صحيحين بين 0 و${MAX_GOALS}`);
  }

  const fixture = await fixtureRepo.findById(fixtureId);
  if (!fixture) throw new PredictionError(404, 'المباراة غير موجودة');

  // نفحص الحالة والوقت معاً: الحالة قد تتأخر ثلاثين ثانية (دورة
  // الكاش) عن الواقع، لكن kickoff_at لا يكذب.
  if (fixture.status !== 'scheduled' || new Date(fixture.kickoff_at) <= new Date()) {
    throw new PredictionError(409, 'أُغلق التوقّع — المباراة انطلقت أو انتهت');
  }

  // المضاعِف بعد فحص الإقفال لا قبله: من تأخر عن الصافرة يُردّ
  // بـ"أُغلق التوقّع" لا بـ"نفدت مضاعفاتك" — الثانية تصفه بمشكلة
  // لا يملكها وتخفي عنه المشكلة التي يملكها.
  const mult = await resolveMultiplier(userId, fixture, multiplier);

  const row = await predictionRepo.upsert({
    userId, fixtureId, predHome: home, predAway: away, multiplier: mult.value,
  });
  // العلم على الصف لا استثناء: التوقّع نجح، وأداةٌ وحدها لم تتوفّر.
  if (row && mult.denied) row.multiplierDenied = mult.denied;
  return row;
}

/**
 * يتحقق من المضاعِف المطلوب ويرجعه، أو null معناه "لا تغيّره".
 *
 * الحصة لكل (لاعب، دوري، موسم): خمسة في الدوري السعودي لا تُنقص
 * شيئاً من خمسة في دوري الأبطال. وهذا ليس سخاءً بل اتساق — لوحة
 * كل دوري مستقلة، فأداة تُنفق في لوحة وتنقص في أخرى تربط منافستين
 * لا تربطهما نتيجة.
 */
async function resolveMultiplier(userId, fixture, requested) {
  if (requested === null || requested === undefined) return { value: null };

  const cfg = await multipliers();
  const value = Number(requested);

  if (value === 1) return { value: 1 }; // الإلغاء مسموح دائماً، ويردّ الأداة
  if (value !== cfg.factor) {
    throw new PredictionError(400, 'مضاعِف غير معروف');
  }

  const used = await predictionRepo.countMultiplied(
    userId, fixture.league_id, fixture.season, fixture.id
  );

  // نفاد الحصة لا يُسقط التوقّع.
  //
  // الحالة واقعية لا نظرية: صفحتان مفتوحتان في لسانين، أُنفق آخر
  // مضاعِف في إحداهما، ثم أُرسلت الأخرى بمربّع كان مؤشَّراً حين
  // رُسمت. ورفض الطلب كله هنا يمسح توقّعاً صحيحاً تماماً بسبب
  // أداة اختيارية — ويترك اللاعب أمام رسالة خطأ قد يغادر بعدها
  // بلا توقّع أصلاً، وهو أسوأ ما يمكن أن نفعله بمن جاء ليلعب.
  //
  // فنحفظ التوقّع مفرداً ونخبره أن المضاعِف وحده لم يُطبَّق.
  if (used >= cfg.free_per_season) {
    return {
      value: 1,
      denied: `حُفظ توقّعك بلا مضاعِف — استعملت مضاعفاتك ${counted(cfg.free_per_season)} في هذا الدوري لهذا الموسم.`,
    };
  }
  return { value };
}

/**
 * حالة الأداة أمام هذا اللاعب في هذه المباراة — للعرض.
 *
 * exceptFixture مرة أخرى: من فتح مباراة مضاعَفة يجب أن يقرأ
 * "باقٍ 2 من 5" لا "باقٍ 1"، فمضاعِف هذه المباراة ليس منفقاً في
 * غيرها — وإلغاؤه هنا يعيده إليه فوراً.
 */
async function multiplierState(userId, fixture, mine) {
  const cfg = await multipliers();
  const used = await predictionRepo.countMultiplied(
    userId, fixture.league_id, fixture.season, fixture.id
  );
  // المعروض يعدّ هذه المباراة، والمفروض لا يعدّها — وهذا ليس
  // تناقضاً بل سؤالان مختلفان. الفحص يسأل "هل يملك أداة ينفقها
  // هنا؟" فيستثني ما أنفقه هنا سلفاً كي لا يُمنع من تعديل توقّعه.
  // والعرض يجيب "كم بقي لي لمباريات أخرى؟" فيعدّ هذه واحدةً
  // منفَقة ما دامت مؤشَّرة — وإلا قرأ "باقٍ 5 من 5" فوق مربّع
  // مؤشَّر، فظنّ الأداة مجانية بلا حدّ حتى تنفد فجأة.
  const on = (mine?.multiplier ?? 1) > 1;
  return {
    factor: cfg.factor,
    free: cfg.free_per_season,
    used,
    left: Math.max(0, cfg.free_per_season - used - (on ? 1 : 0)),
    on,
  };
}

/** "خمسة" لا "5 مضاعفات" — الرقم بعد فعل ماضٍ يصح مكتوباً. */
function counted(n) {
  return ['', 'الواحد', 'الاثنين', 'الثلاثة', 'الأربعة', 'الخمسة'][n] ?? `الـ${n}`;
}

/** إعدادات المضاعِف المعمول بها. */
async function multipliers() {
  return (await settingsRepo.get('multipliers').catch(() => null)) ?? DEFAULT_MULTIPLIERS;
}

/** هل ما زال التوقّع مفتوحاً على هذه المباراة؟ */
function isOpen(fixture) {
  return fixture.status === 'scheduled' && new Date(fixture.kickoff_at) > new Date();
}

/**
 * نتيجة افتراضية لاتجاه مختار.
 *
 * من يضغط "يفوز الأهلي" يريد أن يقول ذلك لا أن يخمّن 2-1. النتائج
 * هنا هي الأشيع في كرة القدم فعلاً، وتعطيه نقاط الاتجاه على الأقل
 * إن لم يعدّلها — وهو أفضل من أن يغادر بلا توقّع.
 */
const DEFAULT_SCORELINE = {
  home: { home: 1, away: 0 },
  draw: { home: 1, away: 1 },
  away: { home: 0, away: 1 },
};

/** اتجاه توقّع محفوظ: 'home' | 'draw' | 'away'. */
function outcomeOf(prediction) {
  if (!prediction) return null;
  if (prediction.pred_home > prediction.pred_away) return 'home';
  if (prediction.pred_home < prediction.pred_away) return 'away';
  return 'draw';
}

/** جدول النقاط المعمول به — من الإعدادات، وإلا الافتراضي. */
async function points() {
  return (await settingsRepo.get('scoring').catch(() => null)) ?? DEFAULT_SCORING;
}

module.exports = {
  submit, isOpen, outcomeOf, points, multipliers, multiplierState,
  DEFAULT_SCORELINE, PredictionError, MAX_GOALS,
};
