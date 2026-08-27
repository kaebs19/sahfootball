// routes/fixtures — مسارات المباريات. قراءة فقط.
//
// لاحظ تقسيم الأدوار: الـ route يفهم HTTP فقط (بارامترات، رموز حالة،
// JSON) ويفوّض كل شيء آخر للـ repository أو الـ provider.
//
// ملاحظة عن الأخطاء: نستخدم Express 5، وفيه أي Promise مرفوض داخل
// معالج async يصل تلقائياً لمعالج الأخطاء المركزي في app.js —
// لا نحتاج try/catch في كل مسار (في Express 4 كان هذا يتطلب غلافاً).
const express = require('express');
const requireAuth = require('../middleware/requireAuth');
const fixtureRepo = require('../repositories/fixtureRepo');
const predictionRepo = require('../repositories/predictionRepo');
const settingsRepo = require('../repositories/settingsRepo');
const scoringService = require('../services/scoringService');
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

// GET /api/fixtures/live — شاشة "مباشر": ما يحدث الآن + سياقه
//
// محمي بـ requireAuth خلافاً لبقية مسارات هذا الملف، والسبب ليس
// سرية بيانات المباريات (هي عامة) بل أن الرد شخصي: كل مباراة تحمل
// توقع صاحب الطلب وحالته ونقاطه لو انتهت الآن. بلا هوية لا معنى
// لـ my_prediction، ومسار عام يستقبل معرّف مستخدم من العميل هو
// دعوة لقراءة توقعات الآخرين.
//
// ثلاثة أقسام في رد واحد، لأن التبويب لا يمكن أن يكون فارغاً:
// المباريات الجارية هي الأصل، لكنها غير موجودة معظم الوقت،
// فنسنده بأقرب مباراة قادمة وبنتائج اليوم المنتهية.
// وطلب واحد بثلاثة أقسام أفضل من ثلاثة طلبات من الجوال: التبويب
// يُحدَّث كل بضع ثوانٍ، فضرب عدد الطلبات في ثلاثة يضرب استهلاك
// البطارية والشبكة بلا مقابل.
router.get('/live', requireAuth, async (req, res) => {
  // الاستعلامات الثلاثة مستقلة تماماً، فلا معنى لانتظار كل واحد
  // قبل بدء التالي — Promise.all يجعل زمن الرد زمن أبطأها لا مجموعها.
  const [live, nextKickoff, finishedToday] = await Promise.all([
    fixtureRepo.findLive(),
    fixtureRepo.findNextKickoff(),
    fixtureRepo.findFinishedToday(),
  ]);

  const fixtures = [...live, ...(nextKickoff ? [nextKickoff] : []), ...finishedToday];

  // إعدادات النقاط من القاعدة وليست ثوابت: الأدمن يعدّلها من
  // اللوحة، والشارة المباشرة يجب أن تحسب بنفس الأسعار التي
  // ستُدفع فعلاً عند الصافرة.
  const cfg = (await settingsRepo.get('scoring')) ?? scoringService.DEFAULT_SCORING;

  const myPredictions = await predictionRepo.findByUserAndFixtures(
    req.userId,
    fixtures.map((f) => f.id)
  );
  // خريطة بدل البحث بـ find داخل الحلقة: بحث خطي في كل صف يعني
  // مسحاً متكرراً للقائمة كلها، والخريطة تجعلها قراءة واحدة.
  const byFixture = new Map(myPredictions.map((p) => [p.fixture_id, p]));

  // نلحق التوقع بالمباراة. null صريحة لمن لم يتوقع — الحقل موجود
  // دائماً في الرد، فلا يحتاج العميل تمييز "غائب" عن "لا يوجد".
  const decorate = (fixture) => {
    const pred = byFixture.get(fixture.id);
    if (!pred) return { ...fixture, my_prediction: null };

    // "لو انتهت الآن": النتيجة الحالية هي المرجع. قبل الانطلاق
    // تكون الأهداف NULL ونعاملها 0-0 — وهو صحيح حرفياً (لم يُسجَّل
    // شيء بعد) ويبقي أنواع الحقول ثابتة لعميل Dart. على الواجهة
    // ألا ترسم الشارة قبل صافرة البداية: النتيجة لم تبدأ أصلاً.
    const actual = { home: fixture.goals_home ?? 0, away: fixture.goals_away ?? 0 };
    const mine = { home: pred.pred_home, away: pred.pred_away };

    return {
      ...fixture,
      my_prediction: {
        home: mine.home,
        away: mine.away,
        // الاثنان من نفس المصدر (computePoints يستدعي computeState
        // داخلياً)، فلا يمكن أن تظهر شارة "مضبوطة" بنقاط الاتجاه.
        points_if_now: scoringService.computePoints(mine, actual, cfg),
        state: scoringService.computeState(mine, actual),
      },
    };
  };

  res.json({
    live: live.map(decorate),
    next_kickoff: nextKickoff ? decorate(nextKickoff) : null,
    finished_today: finishedToday.map(decorate),
  });
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
