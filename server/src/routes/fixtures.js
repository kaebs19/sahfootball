// routes/fixtures — مسارات المباريات. قراءة فقط.
//
// لاحظ تقسيم الأدوار: الـ route يفهم HTTP فقط (بارامترات، رموز حالة،
// JSON) ويفوّض كل شيء آخر للـ repository أو الـ provider.
//
// ملاحظة عن الأخطاء: نستخدم Express 5، وفيه أي Promise مرفوض داخل
// معالج async يصل تلقائياً لمعالج الأخطاء المركزي في app.js —
// لا نحتاج try/catch في كل مسار (في Express 4 كان هذا يتطلب غلافاً).
const express = require('express');
const fixtureRepo = require('../repositories/fixtureRepo');
const footballProvider = require('../services/footballProvider');
const { mapEvent } = require('../mappers/fixtureMapper');

const router = express.Router();

// GET /api/fixtures?date=YYYY-MM-DD  — مباريات يوم محدد (بتوقيت الرياض)
router.get('/', async (req, res) => {
  const { date } = req.query;

  // تحقق صارم من الشكل قبل تمريره للقاعدة: رسالة خطأ واضحة
  // للمطور خير من خطأ SQL غامض.
  if (!date || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    return res.status(400).json({ error: 'query param "date" is required, format YYYY-MM-DD' });
  }

  const fixtures = await fixtureRepo.findByDate(date);
  res.json({ date, fixtures });
});

// GET /api/fixtures/upcoming — المباريات القادمة
// مهم: هذا المسار قبل '/:id' — لو جاء بعده لالتقط Express كلمة
// "upcoming" على أنها id. ترتيب تعريف المسارات في Express له معنى.
router.get('/upcoming', async (req, res) => {
  const fixtures = await fixtureRepo.findUpcoming();
  res.json({ fixtures });
});

// GET /api/fixtures/:id — مباراة واحدة
router.get('/:id', async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) {
    return res.status(400).json({ error: 'fixture id must be an integer' });
  }

  const fixture = await fixtureRepo.findById(id);
  if (!fixture) {
    return res.status(404).json({ error: 'fixture not found' });
  }
  res.json({ fixture });
});

// GET /api/fixtures/:id/events — أحداث المباراة (أهداف، بطاقات...)
//
// استراتيجية الجلب هنا مختلفة عن بقية المسارات، وتستحق الشرح:
// الأحداث لا تُجلب في مزامنة الموسم (ستكلف طلباً لكل مباراة —
// تحرق الحصة). بدلها نجلبها "عند الطلب": أول من يطلب أحداث مباراة
// يحرّك جلبها من المزود (خلف كاش 60 ثانية في الـ provider)، نخزنها
// في القاعدة، ونرد. الطلبات التالية خلال دقيقة تضرب كاش المزود
// فلا تكلف شيئاً. ولو فشل المزود (انقطاع، نفاد حصة) نرد بآخر
// نسخة مخزنة عندنا بدل خطأ — تدهور لطيف.
router.get('/:id/events', async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) {
    return res.status(400).json({ error: 'fixture id must be an integer' });
  }

  const fixture = await fixtureRepo.findById(id);
  if (!fixture) {
    return res.status(404).json({ error: 'fixture not found' });
  }

  let stale = false;
  try {
    const rawEvents = await footballProvider.getFixtureEvents(id);
    const events = rawEvents.map((e) => mapEvent(e, id));
    await fixtureRepo.replaceEvents(id, events);
  } catch (err) {
    // نكتفي بما في القاعدة ونعلم العميل أن البيانات قد تكون قديمة
    stale = true;
  }

  const events = await fixtureRepo.findEvents(id);
  res.json({ fixture_id: id, stale, events });
});

module.exports = router;
