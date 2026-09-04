// pushService — "أرسل هذا الإشعار لهذا المستخدم".
//
// pushProvider يعرف كيف يكلّم آبل وجوجل، وهذا الملف يعرف أن
// للمستخدم عدة أجهزة، وأن التوكن الميت يُحذف، وأن فشل الإرسال
// لا يجوز أن يُسقط ما استدعاه.
const provider = require('./pushProvider');
const notificationRepo = require('../repositories/notificationRepo');
const logger = require('../utils/logger');

/**
 * إرسال إشعار واحد إلى كل أجهزة مستخدم. يرجع عدد الأجهزة التي
 * وصلها فعلاً (0 يعني لا جهاز، أو كلها ميتة).
 *
 * لا يرمي أبداً: نداؤه يأتي من وظيفة مجدولة تعالج عشرات
 * المستخدمين في حلقة، وجهاز واحد معطّل يجب ألا يوقف البقية.
 */
async function sendToUser(userId, { title, body, data, collapseId }) {
  const devices = await notificationRepo.tokensForUser(userId);
  if (!devices.length) return 0;

  const dead = [];
  let delivered = 0;

  // على التوازي: أجهزة المستخدم الواحد نادراً ما تتجاوز الثلاثة،
  // وكل إرسال نداء شبكة مستقل تماماً.
  await Promise.all(devices.map(async ({ token, platform }) => {
    try {
      const result = await provider.send({ token, platform, title, body, data, collapseId });
      if (result === provider.GONE) dead.push(token);
      else delivered += 1;
    } catch (err) {
      // خطأ عابر (شبكة، مهلة، عطل عند المزوّد): نسجّله ولا نحذف
      // التوكن. حذفه هنا يعني فقدان جهاز سليم بسبب انقطاع دقيقة.
      logger.error(`[push] فشل إرسال إلى ${platform}: ${err.message}`);
    }
  }));

  if (dead.length) {
    await notificationRepo.removeTokens(dead);
    logger.info(`[push] حُذفت ${dead.length} توكنات ميتة`);
  }

  return delivered;
}

module.exports = { sendToUser };
