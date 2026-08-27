// authThrottle — حد محاولات لمسارات المصادقة الحساسة.
//
// غير rateLimiter.js (ذاك يحمي حصتنا عند مزود الكرة) — هذا يحمي
// حسابات المستخدمين من التخمين بالقوة (brute force): من جرّب
// تسجيل الدخول 5 مرات فاشلة على نفس البريد ينتظر ربع ساعة.
//
// المفتاح مركب من العملية + البريد: قفل login على ali@x.com
// لا يمنع login على بريد آخر ولا يمنع forgot على نفس البريد.
const redis = require('../config/redis');

const MAX_ATTEMPTS = 5;
const WINDOW_SECONDS = 15 * 60;

// يرمي خطأ 429 (Too Many Requests) عند تجاوز الحد.
async function assertNotLocked(action, identifier) {
  const key = `auth:throttle:${action}:${identifier}`;
  const attempts = Number(await redis.get(key)) || 0;
  if (attempts >= MAX_ATTEMPTS) {
    const err = new Error('محاولات كثيرة، حاول بعد 15 دقيقة');
    err.status = 429;
    err.expose = true;
    throw err;
  }
}

// تُستدعى بعد محاولة فاشلة فقط — النجاح يصفّر العدّاد.
async function recordFailure(action, identifier) {
  const key = `auth:throttle:${action}:${identifier}`;
  const attempts = await redis.incr(key);
  if (attempts === 1) {
    await redis.expire(key, WINDOW_SECONDS);
  }
}

async function clear(action, identifier) {
  await redis.del(`auth:throttle:${action}:${identifier}`);
}

module.exports = { assertNotLocked, recordFailure, clear };
