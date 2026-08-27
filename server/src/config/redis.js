// عميل Redis واحد مشترك لكل التطبيق (نمط singleton).
//
// Redis عندنا له وظيفتان:
// 1. الكاش: تخزين استجابات API-Football مؤقتاً حسب المدد المحددة.
// 2. عدّاد حد الطلبات اليومي (100 طلب/يوم في الباقة المجانية).
const Redis = require('ioredis');
const logger = require('../utils/logger');

const redis = new Redis(process.env.REDIS_URL, {
  // maxRetriesPerRequest: لو Redis غير متاح، ioredis افتراضياً يعيد
  // المحاولة 20 مرة لكل أمر قبل أن يفشل — هذا يجمّد الطلبات طويلاً.
  // 3 محاولات كافية: نفضّل فشلاً سريعاً على تعليق المستخدم.
  maxRetriesPerRequest: 3,
});

redis.on('error', (err) => {
  // لا نرمي الخطأ — انقطاع Redis يجب ألا يُسقط السيرفر،
  // فقط يفقدنا الكاش مؤقتاً.
  logger.error('[redis] connection error:', err.message);
});

redis.on('connect', () => {
  logger.info('[redis] connected');
});

module.exports = redis;
