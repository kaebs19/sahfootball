// عدّاد حد الطلبات اليومي نحو API-Football.
//
// نمنع التجاوز من جهتنا بدل انتظار رفض المزوّد: تجاوز الحد يعني
// توقف التطبيق عن التحديث بقية اليوم، ومعرفة السبب من عندنا أسرع
// من تتبّع ردود 429 متفرقة.
//
// لماذا العدّاد في Redis وليس متغيراً في الذاكرة؟
// 1. لو أعاد السيرفر التشغيل منتصف اليوم، متغير الذاكرة يصفّر
//    والعدّاد الحقيقي عند المزود لا يصفّر.
// 2. لو شغّلنا أكثر من نسخة من السيرفر مستقبلاً، يجب أن يتشاركوا
//    عدّاداً واحداً.
const redis = require('../config/redis');
const logger = require('./logger');

// الحد يأتي من البيئة لأنه خاصية اشتراك لا ثابت في الكود:
// المجانية 100، وPro 7,500، وUltra 75,000. تركه مثبّتاً على 100
// بعد الترقية كان سيوقف المزامنة عند 100 طلب بينما الاشتراك يسمح
// بسبعين ضعفاً — عطل صامت يبدو كأن المزوّد هو من رفض.
const DAILY_LIMIT = Number(process.env.FOOTBALL_DAILY_LIMIT) || 100;

// نحذّر عند 80% من الحد أياً كان.
const WARN_AT = Math.floor(DAILY_LIMIT * 0.8);

// API-Football يصفّر الحصة عند منتصف الليل UTC،
// لذلك مفتاح العدّاد مبني على تاريخ اليوم بتوقيت UTC.
function todayKey() {
  const today = new Date().toISOString().slice(0, 10); // YYYY-MM-DD
  return `ratelimit:football-api:${today}`;
}

// تُستدعى قبل كل طلب خارجي فعلي. ترمي خطأ لو الحصة انتهت.
async function consume() {
  const key = todayKey();

  // INCR ذرّية (atomic): حتى لو وصل طلبان في نفس اللحظة،
  // كل واحد يحصل على رقم مختلف — لا سباق (race condition).
  const count = await redis.incr(key);

  if (count === 1) {
    // أول طلب اليوم: نضبط انتهاء صلاحية المفتاح بعد 48 ساعة.
    // 48 وليس 24 حتى لا يختفي المفتاح قبل نهاية اليوم بسبب فرق
    // لحظة الإنشاء — المفتاح نفسه مربوط بالتاريخ فالعد يبقى صحيحاً.
    await redis.expire(key, 60 * 60 * 48);
  }

  if (count > DAILY_LIMIT) {
    logger.error(`[rateLimiter] daily limit exceeded (${count}/${DAILY_LIMIT}) — request blocked`);
    const err = new Error('Daily API request limit reached');
    err.code = 'RATE_LIMIT_EXCEEDED';
    throw err;
  }

  if (count >= WARN_AT) {
    logger.warn(`[rateLimiter] approaching daily limit: ${count}/${DAILY_LIMIT}`);
  }

  return count;
}

// كم طلباً استهلكنا اليوم (مفيد لمسار مراقبة لاحقاً).
async function usedToday() {
  const count = await redis.get(todayKey());
  return Number(count) || 0;
}

module.exports = { consume, usedToday, DAILY_LIMIT };
