// webSession — جلسة المتصفح لصفحات الموقع.
//
// لماذا جلسة مستقلة بدل استعمال توكنات JWT نفسها؟
// لأنهما بيئتان مختلفتان في تهديداتهما. التطبيق يحفظ التوكن في
// تخزين آمن ويضعه في ترويسة يكتبها هو، فلا يرسله أحد نيابة عنه.
// المتصفح يرسل الكوكي تلقائياً مع كل طلب لنطاقنا — بما فيها طلب
// يبدأه موقع آخر (CSRF). ووضع JWT في كوكي يجمع أسوأ ما في
// الاثنين: لا يمكن إبطاله قبل انتهائه، ويُرسل تلقائياً.
//
// معرّف عشوائي في Redis يحل الاثنين: إبطال فوري بحذف المفتاح،
// وانتهاء تلقائي بـ TTL، ورمز CSRF مربوط بالجلسة نفسها.
//
// وبلا أي حزمة: لا express-session ولا cookie-parser. ما نحتاجه
// قراءة ترويسة وكتابة أخرى، وcrypto مدمج.
const crypto = require('crypto');
const redis = require('../config/redis');

const COOKIE = 'sah_web';
const TTL_SECONDS = 14 * 24 * 3600; // أسبوعان

const key = (id) => `web:sess:${id}`;

/** يقرأ كوكي واحداً من الترويسة الخام. */
function readCookie(req, name) {
  const header = req.headers.cookie;
  if (!header) return null;
  for (const part of header.split(';')) {
    const eq = part.indexOf('=');
    if (eq === -1) continue;
    if (part.slice(0, eq).trim() === name) {
      return decodeURIComponent(part.slice(eq + 1).trim());
    }
  }
  return null;
}

/**
 * إنشاء جلسة. يرجع رمز CSRF كي تضعه الصفحة في نماذجها.
 *
 * الرمز يولَّد مع الجلسة ويعيش معها لا لكل طلب: التدوير عند كل
 * طلب يكسر الصفحات المفتوحة في تبويبين، ولا يضيف حماية تُذكر ما
 * دام الرمز لا يخرج من الجلسة أصلاً.
 */
async function create(res, userId, { secure }) {
  const id = crypto.randomBytes(32).toString('hex');
  const csrf = crypto.randomBytes(16).toString('hex');

  await redis.set(key(id), JSON.stringify({ userId, csrf }), 'EX', TTL_SECONDS);

  // HttpOnly: لا تقرؤه أي سكربت، فثغرة XSS لا تسرق الجلسة.
  // SameSite=Lax: لا يُرسل مع طلبات POST قادمة من مواقع أخرى —
  //   خط الدفاع الأول ضد CSRF، ورمز CSRF هو الثاني.
  // Secure: لا يُرسل إلا على HTTPS. مطفأ محلياً وإلا لم تعمل
  //   الجلسة على http://localhost أثناء التطوير.
  res.setHeader('Set-Cookie',
    `${COOKIE}=${id}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${TTL_SECONDS}` +
    (secure ? '; Secure' : ''));

  return csrf;
}

/** يرجع { userId, csrf } أو null. */
async function read(req) {
  const id = readCookie(req, COOKIE);
  if (!id) return null;
  const raw = await redis.get(key(id));
  if (!raw) return null;
  try {
    return { id, ...JSON.parse(raw) };
  } catch {
    return null;
  }
}

/** إنهاء الجلسة: تُحذف من Redis أولاً ثم يُمحى الكوكي. */
async function destroy(req, res) {
  const id = readCookie(req, COOKIE);
  if (id) await redis.del(key(id));
  res.setHeader('Set-Cookie', `${COOKIE}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0`);
}

/**
 * إبطال كل جلسات مستخدم — بعد تغيير كلمة السر أو حذف الحساب.
 *
 * SCAN لا KEYS: الثاني يوقف Redis كاملاً حتى ينتهي، وقاعدتنا
 * مشتركة مع مشاريع أخرى على الخادم نفسه.
 */
async function destroyAllForUser(userId) {
  let cursor = '0';
  do {
    const [next, keys] = await redis.scan(cursor, 'MATCH', 'web:sess:*', 'COUNT', 100);
    cursor = next;
    for (const k of keys) {
      const raw = await redis.get(k);
      if (raw && JSON.parse(raw).userId === userId) await redis.del(k);
    }
  } while (cursor !== '0');
}

module.exports = { create, read, destroy, destroyAllForUser, COOKIE };
