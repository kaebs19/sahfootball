// routes/site — واجهة الموقع العام. بلا مصادقة إطلاقاً:
// كل ما هنا محتوى تسويقي وقانوني يجب أن يقرأه أي زائر (ومراجع
// App Store الذي يفتح رابط سياسة الخصوصية بلا حساب).
//
// المسارات قراءة فقط ما عدا POST /contact، وهو المدخل الكتابي
// العام الوحيد في السيرفر كله — لذلك يأخذ نصيبه من الحراسة أدناه.
const express = require('express');
const siteRepo = require('../repositories/siteRepo');
const siteSettings = require('../services/siteSettings');
const safeMarkdown = require('../utils/safeMarkdown');
const contactThrottle = require('../utils/contactThrottle');

const router = express.Router();

// GET /api/site/settings — اسم الموقع وشعاره وروابطه.
// الحقول الفارغة تعني "غير مُعدّ" ويخفيها الموقع (انظر siteSettings).
router.get('/settings', async (req, res) => {
  const settings = await siteSettings.get();
  res.json({ settings });
});

// GET /api/site/pages — فهرس الصفحات (بلا نصوصها).
router.get('/pages', async (req, res) => {
  const pages = await siteRepo.listPages();
  res.json({ pages });
});

// GET /api/site/pages/:slug — صفحة واحدة.
//
// نرد بالنصّين معاً: body الخام (Markdown) و body_html المُصيَّر.
// السبب أن للمحتوى مستهلكَين مختلفَين: الموقع يريد HTML جاهزاً
// بلا مكتبة تصيير في المتصفح، وتطبيق iOS قد يفضّل النص الخام
// ليرسمه بمكوّناته الأصلية بدل WebView. توليد HTML هنا (لا في
// العميل) يعني أيضاً أن قاعدة الأمان في safeMarkdown تُطبَّق مرة
// واحدة في مكان واحد، لا في كل عميل يُكتب لاحقاً.
router.get('/pages/:slug', async (req, res) => {
  const page = await siteRepo.getPage(String(req.params.slug));
  if (!page) return res.status(404).json({ error: 'الصفحة غير موجودة' });

  res.json({
    page: {
      slug: page.slug,
      title: page.title,
      body: page.body,
      body_html: safeMarkdown.render(page.body),
      updated_at: page.updated_at,
    },
  });
});

// حدود الطول. الرسالة الطويلة جداً ليست رسالة بل هجوم على مساحة
// القاعدة، والقصيرة جداً ("؟") لا يستطيع الدعم فعل شيء بها.
const LIMITS = {
  name: 60,
  email: 160,
  subject: 140,
  messageMin: 10,
  messageMax: 4000,
};
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

// POST /api/site/contact — { name?, email, subject?, message }
router.post('/contact', async (req, res) => {
  // الحد قبل أي عمل: لا تحقق ولا كتابة لمن تجاوز — وإلا صار الرفض
  // نفسه عملاً نقوم به لكل طلب في هجوم إغراق.
  const ip = req.ip || 'unknown';
  await contactThrottle.assertNotFlooding(ip);

  const { name, email, subject, message } = req.body || {};

  const cleanName = typeof name === 'string' ? name.trim() : '';
  const cleanEmail = typeof email === 'string' ? email.trim().toLowerCase() : '';
  const cleanSubject = typeof subject === 'string' ? subject.trim() : '';
  const cleanMessage = typeof message === 'string' ? message.trim() : '';

  // البريد إلزامي رغم أن العمود يقبل NULL: رسالة بلا عنوان للرد
  // تصل الصندوق ولا يستطيع أحد الرد عليها — والعمود يبقى مرناً
  // لمصادر أخرى للرسائل مستقبلاً (نموذج داخل التطبيق مثلاً).
  if (!cleanEmail || !EMAIL_RE.test(cleanEmail) || cleanEmail.length > LIMITS.email) {
    return res.status(400).json({ error: 'أدخل بريداً إلكترونياً صحيحاً' });
  }
  if (cleanMessage.length < LIMITS.messageMin) {
    return res.status(400).json({ error: 'الرسالة قصيرة جداً، اكتب 10 أحرف على الأقل' });
  }
  if (cleanMessage.length > LIMITS.messageMax) {
    return res.status(400).json({ error: 'الرسالة أطول من المسموح (4000 حرف)' });
  }
  if (cleanName.length > LIMITS.name) {
    return res.status(400).json({ error: 'الاسم أطول من المسموح' });
  }
  if (cleanSubject.length > LIMITS.subject) {
    return res.status(400).json({ error: 'الموضوع أطول من المسموح' });
  }

  const saved = await siteRepo.createMessage({
    name: cleanName || null,
    email: cleanEmail,
    subject: cleanSubject || null,
    message: cleanMessage,
    ip,
  });

  // العدّاد يزيد بعد الحفظ الناجح: عطل في القاعدة لا يجوز أن
  // يستهلك من رصيد المستخدم ثم يطلب منه المحاولة لاحقاً.
  await contactThrottle.record(ip);

  // لا نعيد الرسالة المحفوظة ولا معرّفها: لا شيء يفعله الزائر بها،
  // وإرجاع المعرّف يكشف عدد الرسائل الواصلة (BIGSERIAL متسلسل).
  res.status(201).json({ message: 'وصلتنا رسالتك، شكراً لك — سنرد عليك قريباً' });
});

module.exports = router;
