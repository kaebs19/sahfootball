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
const { DEFAULT_SCORING } = require('./scoringService');
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
async function submit({ userId, fixtureId, home, away }) {
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

  return predictionRepo.upsert({
    userId, fixtureId, predHome: home, predAway: away,
  });
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
  submit, isOpen, outcomeOf, points,
  DEFAULT_SCORELINE, PredictionError, MAX_GOALS,
};
