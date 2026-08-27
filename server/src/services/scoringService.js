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
const logger = require('../utils/logger');

// القيم الاحتياطية لو غاب صف الإعدادات لأي سبب — النظام لا يتوقف.
const DEFAULT_SCORING = { exact: 5, diff: 3, outcome: 2 };

// دالة صافية (pure): مدخلات → رقم، بلا قاعدة بيانات ولا حالة.
// عمداً — أسهل شيء للاختبار والفهم.
function computePoints(pred, actual, cfg) {
  if (pred.home === actual.home && pred.away === actual.away) return cfg.exact;
  if (pred.home - pred.away === actual.home - actual.away) return cfg.diff;

  const sign = (n) => (n > 0 ? 1 : n < 0 ? -1 : 0);
  if (sign(pred.home - pred.away) === sign(actual.home - actual.away)) return cfg.outcome;

  return 0;
}

// احتساب كل التوقعات المعلقة لمباريات انتهت.
// آمنة التكرار (idempotent): المحتسب يُوسم بـ settled_at فلا يُلتقط
// ثانية — استدعها كل ساعة أو كل دقيقة، لا فرق.
async function settleFinished() {
  const cfg = (await settingsRepo.get('scoring')) ?? DEFAULT_SCORING;
  const pending = await predictionRepo.findUnsettled();

  for (const p of pending) {
    const points = computePoints(
      { home: p.pred_home, away: p.pred_away },
      { home: p.goals_home, away: p.goals_away },
      cfg
    );
    await predictionRepo.settle(p.id, points);
  }

  if (pending.length > 0) {
    logger.info(`[scoring] settled ${pending.length} predictions`);
  }
  return pending.length;
}

module.exports = { computePoints, settleFinished, DEFAULT_SCORING };
