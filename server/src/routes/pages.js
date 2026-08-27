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

// بقية الصفحات المنشورة
router.get('/:slug', async (req, res, next) => {
  const { slug } = req.params;
  if (!PUBLIC_SLUGS.has(slug)) return next();

  const [settings, page] = await Promise.all([loadSettings(), siteRepo.getPage(slug)]);
  if (!page) return next();

  res.type('html').send(renderer.renderPage(page, settings));
});

module.exports = router;
