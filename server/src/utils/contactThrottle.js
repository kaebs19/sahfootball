// contactThrottle — حد إرسال نموذج "تواصل معنا".
//
// أخوان سابقان لهذا الملف: rateLimiter.js يحمي حصتنا عند مزود
// الكرة، و authThrottle.js يحمي الحسابات من تخمين كلمات المرور.
// وهذا يحمي صندوق الوارد نفسه: المسار عام بلا مصادقة وبلا تكلفة
// على المرسل، وهذه بالضبط صفات هدف الإغراق الآلي. بلا حدّ يستطيع
// سكربت واحد أن يدفن الرسائل الحقيقية تحت آلاف الصفوف في دقائق.
//
// نفس نمط authThrottle: عدّاد في Redis بمهلة انتهاء، والمفتاح هو
// ما نريد تقييده — العنوان (IP) هنا بدل البريد هناك. العدّاد في
// Redis لا في الذاكرة للسبب المشروح في rateLimiter: إعادة تشغيل
// السيرفر لا يجوز أن تكون طريقة تصفير الحد.
//
// ⚠️ خلف بروكسي عكسي (nginx / Cloudflare / أي مستضيف مُدار) يجب
// ضبط app.set('trust proxy', ...) في app.js. بدونه تكون req.ip
// هي عنوان البروكسي نفسه في كل طلب: فيصير المفتاح واحداً للزوار
// جميعاً، وأول ثلاث رسائل تقفل النموذج على الإنترنت كله. لم نضبطه
// الآن لأن السيرفر يعمل مباشرة في التطوير، والثقة بترويسة
// X-Forwarded-For بلا بروكسي أمامها أسوأ: يزوّرها المهاجم فيتجاوز
// الحد بعنوان مختلف في كل طلب.
const redis = require('../config/redis');

const MAX_MESSAGES = 3;
const WINDOW_SECONDS = 60 * 60; // ثلاث رسائل في الساعة تكفي أي مستخدم صادق

function key(ip) {
  return `contact:throttle:${ip}`;
}

// يرمي خطأ 429 عند التجاوز — بنفس شكل أخطاء authThrottle
// (expose + status) ليلتقطه معالج الأخطاء المركزي في app.js.
async function assertNotFlooding(ip) {
  const sent = Number(await redis.get(key(ip))) || 0;
  if (sent >= MAX_MESSAGES) {
    const err = new Error('أرسلت رسائل كثيرة، حاول بعد ساعة');
    err.status = 429;
    err.expose = true;
    throw err;
  }
}

// كل رسالة تُحسب — بخلاف تسجيل الدخول حيث يُحسب الفشل فقط.
// المشكلة هنا هي الكثرة نفسها لا الفشل.
async function record(ip) {
  const count = await redis.incr(key(ip));
  if (count === 1) {
    await redis.expire(key(ip), WINDOW_SECONDS);
  }
}

module.exports = { assertNotFlooding, record, MAX_MESSAGES };
