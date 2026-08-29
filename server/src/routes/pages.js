// routes/pages — الموقع العام كصفحات HTML.
//
// هذا الراوتر يخدم البشر بالمتصفح، بعكس بقية المسارات التي تخدم
// التطبيق والـ لوحة بـ JSON. لذلك يعيش على الجذر (/, /privacy…)
// لا تحت /api، والروابط تبقى قصيرة صالحة للنشر:
// malikaltawaquat.com/privacy لا .../api/site/pages/privacy.
//
// كل محتواه من قاعدة البيانات (site_pages و app_settings)، فتعديل
// كلمة من لوحة التحكم يظهر في الطلب التالي بلا إعادة بناء ولا نشر.
const express = require('express');
const siteRepo = require('../repositories/siteRepo');
const siteSettings = require('../services/siteSettings');
const renderer = require('../services/siteRenderer');
const authService = require('../services/authService');
const logger = require('../utils/logger');

const router = express.Router();

// النموذج في صفحة "اتصل بنا" يرسل بترميز النماذج التقليدي، لا JSON.
// express.json() المركّب في app.js لا يفكّه، فنضيف المفكّك هنا
// ومحصوراً بهذا الراوتر — لا داعي لأن تفهم مسارات الـ API صيغة
// نماذج المتصفح.
router.use(express.urlencoded({ extended: false }));

// الصفحات التي لها مسار عام. أي slug آخر في القاعدة يبقى غير
// منشور — قائمة بيضاء صريحة كي لا يصبح إدخال صف في الجدول نشراً
// لصفحة على الموقع بلا قصد.
const PUBLIC_SLUGS = new Set(['privacy', 'terms', 'about', 'contact']);

// siteSettings.get لا settingsRepo.get('site') مباشرة: الأولى تدمج
// القيم الافتراضية فوق المخزَّن، فحقل يُضاف للإعدادات لاحقاً لا يصل
// القالب كـ undefined ويطبع "undefined" في صفحة يراها الزوار.
async function loadSettings() {
  // فشل قراءة الإعدادات يجب ألا يُسقط الموقع: نرجع كائناً فارغاً
  // فيعرض المُصيّر القيم الافتراضية ويخفي ما لم يُضبط.
  try {
    return (await siteSettings.get()) ?? {};
  } catch (err) {
    logger.error('[pages] settings load failed:', err.message);
    return {};
  }
}

// الصفحة الرئيسية
router.get('/', async (req, res) => {
  const settings = await loadSettings();
  res.type('html').send(renderer.renderHome(settings));
});

// صفحة اتصل بنا — قبل /:slug لأن لها معالجاً خاصاً (نموذج + POST)
router.get('/contact', async (req, res) => {
  const [settings, page] = await Promise.all([
    loadSettings(),
    siteRepo.getPage('contact'),
  ]);
  res.type('html').send(
    renderer.renderContact(page, settings, { sent: req.query.sent === '1' })
  );
});

// استقبال رسالة تواصل.
//
// بعد النجاح نحوّل بـ 303 بدل عرض الصفحة مباشرة (نمط
// POST/Redirect/GET): بدونه يبقى الطلب من نوع POST في سجل
// المتصفح، فتحديث الصفحة يعيد إرسال الرسالة نفسها ويكرّرها في
// صندوق الإدارة.
router.post('/contact', async (req, res) => {
  const { name, email, subject, message } = req.body || {};
  const values = {
    name: String(name || '').trim(),
    email: String(email || '').trim(),
    subject: String(subject || '').trim(),
    message: String(message || '').trim(),
  };

  const settings = await loadSettings();
  const page = await siteRepo.getPage('contact');

  const fail = (error) =>
    res.status(400).type('html').send(
      renderer.renderContact(page, settings, { error, values })
    );

  if (values.message.length < 10) {
    return fail('اكتب رسالة لا تقل عن عشرة أحرف.');
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(values.email)) {
    return fail('أدخل بريداً إلكترونياً صحيحاً كي نتمكن من الرد عليك.');
  }

  try {
    await siteRepo.createMessage({
      ...values,
      ip: req.ip,
    });
  } catch (err) {
    logger.error('[pages] contact save failed:', err.message);
    return res
      .status(503)
      .type('html')
      .send(renderer.renderContact(page, settings, {
        error: 'تعذّر إرسال رسالتك الآن. جرّب بعد قليل أو راسلنا بالبريد مباشرة.',
        values,
      }));
  }

  res.redirect(303, '/contact?sent=1');
});

// ─────────────────── استعادة كلمة المرور ───────────────────
//
// نفس منطق /api/auth/forgot-password تماماً، بواجهة HTML بدل JSON.
// المنطق كله في authService: الصفحة هنا نموذج ورسائل، ولا تعرف
// شيئاً عن الرموز ولا Redis ولا التجزئة.

router.get('/forgot', async (req, res) => {
  res.type('html').send(renderer.renderForgot(await loadSettings()));
});

router.post('/forgot', async (req, res) => {
  const email = String(req.body?.email || '').trim();
  const settings = await loadSettings();

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return res.status(400).type('html').send(
      renderer.renderForgot(settings, {
        error: 'أدخل بريداً إلكترونياً صحيحاً.',
        values: { email },
      })
    );
  }

  try {
    await authService.forgotPassword(email);
  } catch (err) {
    // فشل المزوّد (حد يومي، انقطاع). authService يمسح الرمز حين
    // يفشل الإرسال، فلا يبقى المستخدم ينتظر بريداً لن يصل.
    logger.error('[pages] forgot-password failed:', err.message);
    return res.status(503).type('html').send(
      renderer.renderForgot(settings, {
        error: 'تعذّر إرسال الرمز الآن. جرّب بعد قليل.',
        values: { email },
      })
    );
  }

  // تحويل 303 (POST/Redirect/GET): تحديث الصفحة بعده لا يعيد
  // إرسال رمز جديد. ونمرر البريد في الرابط لملء الحقل التالي —
  // بريد صاحب الطلب نفسه ولا سر فيه بالنسبة له، والرمز وحده هو
  // السر ولا يمر هنا أبداً.
  res.redirect(303, `/reset?sent=1&email=${encodeURIComponent(email)}`);
});

router.get('/reset', async (req, res) => {
  res.type('html').send(
    renderer.renderReset(await loadSettings(), {
      sent: req.query.sent === '1',
      values: { email: String(req.query.email || '') },
    })
  );
});

router.post('/reset', async (req, res) => {
  const email = String(req.body?.email || '').trim();
  const code = String(req.body?.code || '').trim();
  const password = String(req.body?.password || '');
  const settings = await loadSettings();

  const fail = (error, status = 400) =>
    res.status(status).type('html').send(
      renderer.renderReset(settings, { error, values: { email } })
    );

  if (!email || !/^[0-9]{6}$/.test(code)) {
    return fail('تحقق من البريد ومن الرمز — الرمز ستة أرقام.');
  }
  if (password.length < 8) {
    return fail('كلمة المرور يجب ألا تقل عن ثمانية أحرف.');
  }

  // الخدمة ترمي AuthError برسالة موحّدة عمداً ("الرمز غير صحيح أو
  // منتهي الصلاحية") ولا تفرّق بين رمز خاطئ ورمز منتهٍ وبريد غير
  // مسجّل — لأن التفريق يحوّل هذه الصفحة إلى أداة تكشف أي البريدات
  // لها حساب. نعرض رسالتها كما هي ولا نضيف تفصيلاً من عندنا.
  //
  // ولا نستعمل التوكنات التي ترجعها (تسجّل الدخول تلقائياً): لا
  // جلسة على الموقع، والوجهة هي التطبيق. إصدارها هنا بلا ضرر —
  // تنتهي صلاحيتها بلا استعمال.
  try {
    await authService.resetPassword({ email, code, newPassword: password });
  } catch (err) {
    if (err.status && err.expose) return fail(err.message, err.status);
    logger.error('[pages] reset-password failed:', err.message);
    return fail('تعذّر تغيير كلمة المرور الآن. جرّب بعد قليل.', 503);
  }

  res.type('html').send(renderer.renderResetDone(settings));
});

// بقية الصفحات المنشورة
router.get('/:slug', async (req, res, next) => {
  const { slug } = req.params;
  if (!PUBLIC_SLUGS.has(slug)) return next();

  const [settings, page] = await Promise.all([loadSettings(), siteRepo.getPage(slug)]);
  if (!page) return next();

  res.type('html').send(renderer.renderPage(page, settings));
});

module.exports = router;
