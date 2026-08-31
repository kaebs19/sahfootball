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

const env = require('./config/env');
const path = require('path');

// نتحقق من الإعداد قبل بناء التطبيق: لا معنى لتركيب المسارات ثم
// اكتشاف أن قاعدة البيانات غير مضبوطة.
env.assertValid();

const app = express();

// خلف بروكسي (nginx، Cloudflare، موازن أحمال) يصل كل طلب من عنوان
// البروكسي لا من عنوان الزائر، ما لم نخبر Express أن يثق بترويسة
// X-Forwarded-For. أثره العملي: حدّ سبام نموذج التواصل يعدّ بعنوان
// واحد للجميع فيقفل الباب على كل الزوار بعد ثلاث رسائل.
//
// ولا نفعّله افتراضياً: الثقة بالترويسة بلا بروكسي أمامك تعني أن أي
// زائر يستطيع انتحال عنوانه وتجاوز الحدود. القيمة تصف طبقات البروكسي
// فعلاً — عادةً 1، أو 'loopback' لبروكسي على نفس الجهاز.
if (process.env.TRUST_PROXY) {
  const value = process.env.TRUST_PROXY;
  app.set('trust proxy', /^\d+$/.test(value) ? Number(value) : value);
}

// ترويسات أمان قياسية، بتعديل واحد على سياسة المحتوى (CSP).
//
// الافتراضي img-src 'self' data:‎ يحجب كل صورة خارجية، وشعارات
// الفرق والدوريات تأتي من media.api-sports.io — فكانت تظهر
// مكسورة على الموقع بلا خطأ في الشبكة، والسبب لا يُرى إلا في
// وحدة تحكم المتصفح.
//
// نوسّع img-src وحده وبمضيف واحد محدد، لا بـ * ولا بتعطيل CSP:
// السياسة الافتراضية هي ما يمنع حقن سكربت من نجاحه، وإسقاطها
// كلها لأجل صور خطأ لا يتناسب مع سببه.
//
// وfonts.googleapis يُسمح له أصلاً في الافتراضي لأن الخطوط تُحمَّل
// كـ stylesheet — أبقيناها صريحة كي لا يكسرها تشديد لاحق.
app.use(helmet({
  contentSecurityPolicy: {
    useDefaults: true,
    directives: {
      'img-src': ["'self'", 'data:', 'https://media.api-sports.io'],
      'font-src': ["'self'", 'https://fonts.gstatic.com'],
      'style-src': ["'self'", "'unsafe-inline'", 'https://fonts.googleapis.com'],
    },
  },
}));

// CORS: قائمة بيضاء من CORS_ORIGINS بدل الفتح للجميع.
//
// تطبيق الجوال لا يتأثر بهذا إطلاقاً — CORS قاعدة متصفح لا شبكة.
// المعني هنا لوحة التحكم لو نُشرت على نطاق منفصل. وحين تُخدم
// اللوحة من نفس السيرفر (الوضع الافتراضي أدناه) فالأصل واحد ولا
// حاجة لـ CORS أصلاً.
const corsOrigins = (process.env.CORS_ORIGINS || '')
  .split(',')
  .map((o) => o.trim())
  .filter(Boolean);

app.use(cors(corsOrigins.length ? { origin: corsOrigins, credentials: false } : {}));

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
app.use('/api/rules', require('./routes/rules'));
app.use('/api/leagues', require('./routes/leagues'));
app.use('/api/champion', require('./routes/champion'));
app.use('/api/predictions', require('./routes/predictions'));
app.use('/api/leaderboard', require('./routes/leaderboard'));
app.use('/api/groups', require('./routes/groups'));
app.use('/api/profile', require('./routes/profile'));
app.use('/api/notifications', require('./routes/notifications'));
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
  require('express').static(require('./utils/avatarFile').UPLOADS_DIR, {
    maxAge: '30d',
  })
);
// شعارات الفرق والدوريات، مخدومة من عندنا.
//
// طلبها من media.api-sports.io مباشرة كان يعمل، لكنه يربط سرعة
// الموقع بخادم طرف ثالث: بطؤه بطؤنا، وانقطاعه صفحة بلا شعارات.
// خمسون شعاراً في صفحة تعني خمسين طلباً لخادم غيرنا عند كل زيارة.
//
// وحين لا يوجد الملف نحوّل للمزوّد بدل أن نرد 404: فريق أُضيف بعد
// آخر تشغيل لـ cache-logos يظهر شعاره من المصدر ويُنزَّل في الدورة
// التالية — تدهور لطيف بدل صورة مكسورة.
app.use('/logos', (req, res, next) => {
  const m = /^\/(team|league)-(\d+)\.png$/.exec(req.path);
  if (!m) return next();

  // من web/assets/logos لا من مجلد الرفع: هذه أصول ثابتة تعيش في
  // المستودع كـ site.css تماماً — مصغّرة إلى 64px مسبقاً (6 كيلوبايت
  // بدل 90)، فلا يحتاج أي خادم أداة تصغير ولا تنزيلاً عند النشر.
  const file = require('path').join(
    __dirname, '..', '..', 'web', 'assets', 'logos', `${m[1]}-${m[2]}.png`
  );

  res.sendFile(file, {
    maxAge: '30d',
    headers: { 'Cross-Origin-Resource-Policy': 'cross-origin' },
  }, (err) => {
    if (!err) return;
    const kind = m[1] === 'team' ? 'teams' : 'leagues';
    res.redirect(302, `https://media.api-sports.io/football/${kind}/${m[2]}.png`);
  });
});

app.use('/api/admin', require('./routes/admin'));

// ── الموقع العام ────────────────────────────────────────────────
//
// يأتي بعد كل مسارات /api عمداً: راوتر الصفحات يلتقط /:slug على
// الجذر، ولو سبقها لابتلع مسارات لا تخصه.
//
// ملفات التصميم من مجلد web/ خارج السيرفر — الموقع أصوله (CSS،
// أيقونة، شعارات) ثابتة، والسيرفر يصنع الـ HTML وحده.
//
// سنة كاملة الآن لا يوم واحد: الرابط يحمل بصمة محتوى الملف
// (?v=… من siteRenderer)، فتغيّر المحتوى يغيّر العنوان ويُبطل
// الكاش من نفسه.
//
// كان يوماً واحداً بلا بصمة، وهذا ما كسر الموقع فعلاً: Cloudflare
// خدم CSS قديماً بعد النشر (cf-cache-status: HIT، age: 6002)
// فظهرت الصفحة بلا تنسيق، بينما الملف على الخادم صحيح تماماً.
app.use(
  '/assets',
  require('express').static(require('path').join(__dirname, '..', '..', 'web', 'assets'), {
    maxAge: '365d',
  })
);
// ── ملفات التحقّق من ملكية النطاق ───────────────────────────────
//
// جهات خارجية تثبت ملكيتك للنطاق بطلب ملف على مسار ثابت من الجذر.
// آبل تفعل هذا عند إعداد "الدخول بحساب Apple" للويب.
//
// كاش قصير لا 365 يوماً كالأصول: هذه الملفات تتغيّر حين تتغيّر
// الإعدادات لا حين ننشر، وليس لها بصمة في اسمها تكسر الكاش. وملفٌ
// قديم مخبّأ هنا يعني فشل تحقّق لا يُفسَّر.
app.use(
  '/.well-known',
  require('express').static(require('path').join(__dirname, '..', '..', 'web', '.well-known'), {
    maxAge: '5m',
    // آبل تقرأ الملف نصاً؛ الامتداد .txt يكفي، وهذا يضمن ألا
    // يُخمَّن نوعٌ آخر لملف بلا امتداد.
    setHeaders: (res) => res.type('text/plain'),
  })
);

// ── لوحة التحكم ─────────────────────────────────────────────────
//
// تُخدم من نفس السيرفر تحت /admin بدل نشرها على نطاق منفصل. المكسب
// ليس توفير استضافة بل أن الأصل يصبح واحداً: لا CORS، ولا ترويسة
// CORP تكسر الصور، ولا نطاق ثانٍ بشهادة TLS خاصة به. وحدة نشر واحدة.
//
// SPA fallback: التطبيق يستخدم توجيهاً على جانب المتصفح، فطلب
// /admin/users مباشرةً (أو بعد تحديث الصفحة) يصل السيرفر كمسار لا
// ملف له. نرد index.html ويتولى الراوتر الباقي — وبدونه كل تحديث
// صفحة داخل اللوحة يعطي 404.
const ADMIN_DIST = process.env.ADMIN_DIST
  ? path.resolve(process.env.ADMIN_DIST)
  : path.join(__dirname, '..', '..', 'admin', 'dist');

if (require('fs').existsSync(path.join(ADMIN_DIST, 'index.html'))) {
  app.use('/admin', require('express').static(ADMIN_DIST, { maxAge: '1h' }));
  app.get('/admin/*splat', (req, res) => {
    res.sendFile(path.join(ADMIN_DIST, 'index.html'));
  });
  logger.info(`[admin] لوحة التحكم تُخدم من ${ADMIN_DIST} على /admin`);
} else {
  // غيابها ليس خطأً: في التطوير تعمل اللوحة على خادم Vite منفصل،
  // وقد تُنشر على نطاق مستقل. نقولها في اللوق كي لا يبحث أحد عنها.
  logger.warn('[admin] لا توجد نسخة مبنية من اللوحة — شغّل: npm run build داخل admin/');
}

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
const server = app.listen(PORT, () => {
  logger.info(`ملك التوقعات — السيرفر يعمل على المنفذ ${PORT}`);
  logger.info(`USE_SAMPLES=${process.env.USE_SAMPLES}`);

  // المزامنة التلقائية. ENABLE_SCHEDULER=false تعطلها — مفيد حين
  // تشغّل أكثر من نسخة سيرفر (نسخة واحدة فقط يجب أن تزامن، وإلا
  // تضاعفت الطلبات على حصة المزوّد) أو حين تريد التحكم اليدوي.
  if (process.env.ENABLE_SCHEDULER !== 'false') {
    require('./jobs/scheduler').start();
    // الإشعارات تتبع نفس العلم: هي أيضاً وظيفة دورية يجب ألا تعمل
    // في أكثر من نسخة سيرفر — نسختان تعنيان إشعارين لكل مستخدم،
    // لأن سجل الإرسال يُكتب بعد الإرسال لا قبله.
    require('./jobs/notifier').start();
    // مراقبة الاشتراك والحصة. تتبع نفس العلم لأنها ترسل بريداً:
    // نسختان تعنيان تنبيهين — وإن كان قفل Redis يمنع أغلب ذلك.
    require('./jobs/planWatch').start();
  }
});

// إطفاء لطيف.
//
// عند النشر يرسل مدير العمليات (systemd، Docker) إشارة SIGTERM ثم
// ينتظر قليلاً قبل القتل. بلا معالج لها ينتهي السيرفر فوراً وتُقطع
// الطلبات الجارية في منتصفها — مستخدم يحفظ توقعه لحظة النشر يرى
// خطأ شبكة. هنا نتوقف عن قبول اتصالات جديدة، ننهي ما بدأ، ثم نغلق
// القاعدة و Redis.
//
// والمهلة القصوى ضرورية: اتصال معلّق (طلب طويل، عميل لا يغلق) كان
// سيمنع الخروج إلى الأبد، فيقتلنا مدير العمليات قسراً بعد مهلته —
// وهو ما أردنا تجنّبه أصلاً.
let shuttingDown = false;

async function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  logger.info(`[shutdown] وصلت ${signal} — إيقاف لطيف…`);

  const force = setTimeout(() => {
    logger.error('[shutdown] تجاوز المهلة — خروج قسري');
    process.exit(1);
  }, 10000);
  force.unref();

  server.close(async () => {
    try {
      await require('./config/db').pool.end();
      await require('./config/redis').quit();
    } catch (err) {
      logger.error('[shutdown]', err.message);
    }
    logger.info('[shutdown] تم');
    process.exit(0);
  });
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
