// scoringService — منطق احتساب النقاط.
//
// القواعد (قيمها من app_settings، يعدّلها الأدمن من اللوحة):
//   exact:   النتيجة بالضبط        (توقع 2-1 وكانت 2-1)
//   diff:    فارق الأهداف صحيح     (توقع 2-1 وكانت 3-2 — الفارق +1)
//   outcome: الاتجاه فقط           (توقع فوز المضيف وفاز بأي نتيجة)
// ملاحظة رياضية مريحة: تساوي الفارق يتضمن صحة الاتجاه تلقائياً
// (فارق موجب = فوز مضيف دائماً، صفر = تعادل، سالب = فوز ضيف)،
// لذلك يكفي فحص الشروط بالترتيب من الأدق للأعم.
const settingsRepo = require('../repositories/settingsRepo');
const predictionRepo = require('../repositories/predictionRepo');
const badgeService = require('./badgeService');
const logger = require('../utils/logger');

// القيم الاحتياطية لو غاب صف الإعدادات لأي سبب — النظام لا يتوقف.
const DEFAULT_SCORING = { exact: 5, diff: 3, outcome: 2 };

// تصنيف التوقع مقابل نتيجة: 'exact' | 'diff' | 'outcome' | 'none'.
//
// هذه هي المقارنة الوحيدة في النظام كله، وكل من يحتاجها يمر بها.
// السبب عملي: تبويب "مباشر" يعرض شارة ("نتيجة مضبوطة!") بينما
// المباراة جارية، والاحتساب النهائي يمنح النقاط بعد الصافرة. لو
// كتبنا المقارنة مرة هنا ومرة في الـ route لصار التطابق بينهما
// مسألة انضباط بشري: أي تعديل مستقبلي على القاعدة (احتساب ركلات
// الترجيح مثلاً) يُطبَّق في نسخة وينسى في الأخرى، فيرى المستخدم
// شارة "مضبوطة" طوال المباراة ثم نقاط اتجاه فقط عند النهاية —
// وهو تناقض يقرأه كسرقة نقاط، لا كخلل برمجي.
// دالة واحدة تجعل التناقض مستحيلاً لا مستبعداً.
//
// صافية (pure): مدخلات → نص، بلا قاعدة بيانات ولا حالة.
//
// الترتيب من الأدق للأعم مقصود: تساوي الفارق يتضمن صحة الاتجاه
// تلقائياً، والنتيجة المضبوطة تتضمن الاثنين.
function computeState(pred, actual) {
  if (pred.home === actual.home && pred.away === actual.away) return 'exact';
  if (pred.home - pred.away === actual.home - actual.away) return 'diff';

  const sign = (n) => (n > 0 ? 1 : n < 0 ? -1 : 0);
  if (sign(pred.home - pred.away) === sign(actual.home - actual.away)) return 'outcome';

  return 'none';
}

// النقاط = سعر التصنيف حسب الإعدادات.
// أسماء حالات computeState هي نفسها مفاتيح cfg عمداً — الربط
// بينهما يصبح بحثاً في كائن بدل سلسلة شروط ثانية تقول نفس الشيء.
function computePoints(pred, actual, cfg) {
  const state = computeState(pred, actual);
  return state === 'none' ? 0 : cfg[state];
}

// احتساب كل التوقعات المعلقة لمباريات انتهت.
// آمنة التكرار (idempotent): المحتسب يُوسم بـ settled_at فلا يُلتقط
// ثانية — استدعها كل ساعة أو كل دقيقة، لا فرق.
async function settleFinished() {
  const cfg = (await settingsRepo.get('scoring')) ?? DEFAULT_SCORING;
  const pending = await predictionRepo.findUnsettled();

  const touchedUsers = new Set();
  for (const p of pending) {
    const points = computePoints(
      { home: p.pred_home, away: p.pred_away },
      { home: p.goals_home, away: p.goals_away },
      cfg
    );
    await predictionRepo.settle(p.id, points);
    touchedUsers.add(p.user_id); // Set لأن للمستخدم توقعات كثيرة في الدورة الواحدة
  }

  if (pending.length > 0) {
    logger.info(`[scoring] settled ${pending.length} predictions`);
  }

  // الأوسمة بعد الاحتساب كله، لا داخل الحلقة: الوسام يُقاس على حالة
  // مكتملة. تقييم المستخدم بعد توقعه الأول مباشرة يرى سلسلة تنتهي
  // عند مباراة لم تُحتسب بعد رغم أنها انتهت في نفس الدقيقة، فيمنع
  // وسام سلسلة يستحقه — ثم يناله عند الاحتساب التالي بلا سبب ظاهر له.
  //
  // ولمن مسّه الاحتساب فقط: الاحتساب هو اللحظة الوحيدة التي تتغير
  // فيها وقائع المستخدم، ومن لم يُحتسب له شيء الآن لم يتغير شيء عنده.
  // المرور على كل المستخدمين في كل دورة عمل بلا نتيجة.
  //
  // evaluateQuietly لا evaluate: النقاط هي المنتج والأوسمة زينة.
  // خطأ في استعلام وسام يجب ألا يُسقط الاحتساب ولا المزامنة التي
  // استدعته — التوقعات محفوظة ومحتسبة فعلاً في هذه النقطة، وإجهاض
  // العملية هنا يعني تكرار كل شيء في الدورة القادمة بلا داعٍ.
  for (const userId of touchedUsers) {
    await badgeService.evaluateQuietly(userId);
  }

  return pending.length;
}

module.exports = { computePoints, computeState, settleFinished, DEFAULT_SCORING };
