// نقطة دخول السيرفر.
//
// dotenv يجب أن يكون أول سطر: يقرأ .env ويضع القيم في process.env
// قبل أن يُحمَّل أي ملف آخر يعتمد عليها (db.js و redis.js يقرآن
// process.env لحظة تحميلهما).
require('dotenv').config();

const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const logger = require('./utils/logger');
const rateLimiter = require('./utils/rateLimiter');

const app = express();

app.use(helmet());       // ترويسات أمان قياسية (HTTP headers)
app.use(cors());         // نسمح للتطبيق والموقع بالاتصال بنا
app.use(express.json()); // فك JSON في أجسام الطلبات

// مسار فحص الصحة: هل السيرفر حي؟ وكم استهلكنا من حصة API اليوم؟
app.get('/health', async (req, res) => {
  let apiRequestsToday = null;
  try {
    apiRequestsToday = await rateLimiter.usedToday();
  } catch {
    // Redis غير متاح — لا بأس، المسار يبقى يعمل
  }
  res.json({
    status: 'ok',
    useSamples: process.env.USE_SAMPLES === 'true',
    apiRequestsToday,
    apiDailyLimit: rateLimiter.DAILY_LIMIT,
  });
});

app.use('/api/auth', require('./routes/auth'));
app.use('/api/fixtures', require('./routes/fixtures'));
app.use('/api/teams', require('./routes/teams'));
app.use('/api/standings', require('./routes/standings'));
app.use('/api/predictions', require('./routes/predictions'));
app.use('/api/leaderboard', require('./routes/leaderboard'));
app.use('/api/groups', require('./routes/groups'));
app.use('/api/profile', require('./routes/profile'));
// محتوى الموقع التعريفي: عام بلا مصادقة عمداً — صفحة سياسة
// الخصوصية يجب أن تُفتح برابط مباشر بلا حساب (مراجعة App Store
// تفتحها هكذا).
app.use('/api/site', require('./routes/site'));

// الصور المرفوعة تُقدَّم كملفات ثابتة. maxAge: اسم الملف عشوائي
// ويتغير مع كل رفع، فيجوز للمتصفح تخزينه طويلاً بأمان.
//
// crossOriginResourcePolicy: helmet يضع same-origin افتراضياً على
// كل شيء، وهو الصحيح لردود الـ API. لكنه يكسر الصور: لوحة التحكم
// تعمل على منفذ آخر (5173 في التطوير، ونطاق آخر في الإنتاج)،
// فيرفض المتصفح رسم صورة قادمة من أصل مختلف رغم أن الطلب نجح
// بـ 200 — عطل صامت يظهر كصورة مكسورة بلا خطأ في الشبكة.
// الاستثناء محصور بهذا المسار: الأفاتار محتوى عام أصلاً (اسمه
// عشوائي ولا يدل على صاحبه)، وبقية المسارات تبقى مقيّدة.
app.use(
  '/uploads',
  helmet.crossOriginResourcePolicy({ policy: 'cross-origin' }),
  require('express').static(require('path').join(__dirname, '..', 'uploads'), {
    maxAge: '30d',
  })
);
app.use('/api/admin', require('./routes/admin'));

// ── الموقع العام ────────────────────────────────────────────────
//
// يأتي بعد كل مسارات /api عمداً: راوتر الصفحات يلتقط /:slug على
// الجذر، ولو سبقها لابتلع مسارات لا تخصه.
//
// ملفات التصميم من مجلد web/ خارج السيرفر — الموقع أصوله (CSS،
// أيقونة) ثابتة، والسيرفر يصنع الـ HTML وحده. immutable في
// Cache-Control غير مناسب هنا لأن اسم الملف لا يحمل بصمة تتغير
// مع محتواه، فنكتفي بيوم واحد.
app.use(
  '/assets',
  require('express').static(require('path').join(__dirname, '..', '..', 'web', 'assets'), {
    maxAge: '1d',
  })
);
app.use('/', require('./routes/pages'));

// أي مسار لم يلتقطه أحد: صفحة 404 بهوية الموقع للمتصفح، وJSON
// لمن يطلب JSON. بدون هذا يرد Express بصفحة HTML بيضاء افتراضية
// لا تشبه المنتج في شيء.
app.use(async (req, res) => {
  if (req.path.startsWith('/api/')) {
    return res.status(404).json({ error: 'المسار غير موجود' });
  }
  const settings = await require('./services/siteSettings').get().catch(() => null);
  res
    .status(404)
    .type('html')
    .send(require('./services/siteRenderer').renderNotFound(settings ?? {}));
});

// معالج أخطاء مركزي: أي خطأ يُرمى داخل مسار يصل هنا،
// فلا نكرر try/catch في كل مسار. (الوسائط الأربعة مطلوبة
// حتى يتعرف Express عليه كمعالج أخطاء.)
app.use((err, req, res, next) => {
  // نوعان من الأخطاء:
  // 1. مقصودة (err.expose = true، مثل AuthError): رسالتها مكتوبة
  //    للمستخدم أصلاً، نمررها كما هي مع رمز حالتها.
  // 2. أعطال حقيقية: نسجل التفاصيل في اللوق لكن نرد برسالة عامة —
  //    رسائل الأعطال الداخلية قد تكشف بنية النظام لمهاجم.
  if (err.expose && err.status) {
    return res.status(err.status).json({ error: err.message });
  }
  logger.error('[app]', err.message);
  const status = err.code === 'RATE_LIMIT_EXCEEDED' ? 503 : 500;
  const message = status === 503 ? err.message : 'خطأ داخلي في السيرفر';
  res.status(status).json({ error: message });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  logger.info(`Sah Football server listening on port ${PORT}`);
  logger.info(`USE_SAMPLES=${process.env.USE_SAMPLES}`);

  // المزامنة التلقائية. ENABLE_SCHEDULER=false تعطلها — مفيد حين
  // تشغّل أكثر من نسخة سيرفر محلياً (نسخة واحدة فقط يجب أن تزامن)
  // أو حين تريد التحكم اليدوي الكامل أثناء تجربة شيء ما.
  if (process.env.ENABLE_SCHEDULER !== 'false') {
    require('./jobs/scheduler').start();
  }
});
