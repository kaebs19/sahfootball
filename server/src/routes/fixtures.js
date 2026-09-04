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
const matchDetailService = require('../services/matchDetailService');
const liveRefresh = require('../services/liveRefresh');
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
//
// ?leagues=307,39 اختياري: شاشة المباريات تعرض دوريات المستخدم لا
// كل الدوريات، والتصفية هنا لا في التطبيق — أقرب عشرين مباراة
// عالمياً قد لا تحوي مباراة واحدة من الدوري المطلوب.
router.get('/upcoming', async (req, res) => {
  const asked = String(req.query.leagues || '')
    .split(',')
    .filter((s) => /^\d+$/.test(s))
    .map(Number);
  const fixtures = await fixtureRepo.findUpcoming(20, asked.length ? asked : null);
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
/**
 * يلحق توقّع صاحب الطلب بكل مباراة: `my_prediction` موجودة دائماً
 * في الرد (null لمن لم يتوقّع) فلا يحتاج العميل تمييز «غائب» عن
 * «لا يوجد». مشتركة بين «مباشر» وشاشة المباراة كي يستحيل أن تقول
 * القائمة «مضبوط» والشاشة «فارق الأهداف» عن نفس التوقّع.
 */
async function withMyPredictions(userId, fixtures) {
  // إعدادات النقاط من القاعدة وليست ثوابت: الأدمن يعدّلها من
  // اللوحة، والشارة المباشرة يجب أن تحسب بنفس الأسعار التي
  // ستُدفع فعلاً عند الصافرة.
  const cfg = (await settingsRepo.get('scoring')) ?? scoringService.DEFAULT_SCORING;

  const mine = await predictionRepo.findByUserAndFixtures(
    userId,
    fixtures.map((f) => f.id)
  );
  // خريطة بدل البحث بـ find داخل الحلقة: بحث خطي في كل صف يعني
  // مسحاً متكرراً للقائمة كلها، والخريطة تجعلها قراءة واحدة.
  const byFixture = new Map(mine.map((p) => [p.fixture_id, p]));

  return fixtures.map((fixture) => {
    const pred = byFixture.get(fixture.id);
    if (!pred) return { ...fixture, my_prediction: null };

    // "لو انتهت الآن": النتيجة الحالية هي المرجع. قبل الانطلاق
    // تكون الأهداف NULL ونعاملها 0-0 — وهو صحيح حرفياً (لم يُسجَّل
    // شيء بعد) ويبقي أنواع الحقول ثابتة لعميل Dart. على الواجهة
    // ألا ترسم الشارة قبل صافرة البداية: النتيجة لم تبدأ أصلاً.
    const actual = { home: fixture.goals_home ?? 0, away: fixture.goals_away ?? 0 };
    const guess = { home: pred.pred_home, away: pred.pred_away };

    return {
      ...fixture,
      my_prediction: {
        home: guess.home,
        away: guess.away,
        // الاثنان من نفس المصدر (computePoints يستدعي computeState
        // داخلياً)، فلا يمكن أن تظهر شارة "مضبوطة" بنقاط الاتجاه.
        points_if_now: scoringService.computePoints(guess, actual, cfg),
        state: scoringService.computeState(guess, actual),
      },
    };
  });
}

router.get('/live', requireAuth, async (req, res) => {
  // الاستعلامات الثلاثة مستقلة تماماً، فلا معنى لانتظار كل واحد
  // قبل بدء التالي — Promise.all يجعل زمن الرد زمن أبطأها لا مجموعها.
  const [liveStale, nextKickoff, finishedToday] = await Promise.all([
    fixtureRepo.findLive(),
    fixtureRepo.findNextKickoff(),
    fixtureRepo.findFinishedToday(),
  ]);

  // الطلب نفسه يُنعش الجارية من المزوّد (راجع liveRefresh): من فتح
  // الشاشة يرى نتيجة عمرها ثوانٍ لا دقائق، ومن لم يفتحها لا يكلّف
  // شيئاً. ونعيد القراءة بعده لأن مباراة قد تكون انتهت للتو.
  const live = await liveRefresh.refresh(liveStale, () => fixtureRepo.findLive());

  const fixtures = [...live, ...(nextKickoff ? [nextKickoff] : []), ...finishedToday];
  const decorated = await withMyPredictions(req.userId, fixtures);
  const byId = new Map(decorated.map((f) => [f.id, f]));

  res.json({
    live: live.map((f) => byId.get(f.id)),
    next_kickoff: nextKickoff ? byId.get(nextKickoff.id) : null,
    finished_today: finishedToday.map((f) => byId.get(f.id)),
  });
});

// GET /api/fixtures/:id/match — شاشة المباراة: ترويسة حيّة وأحداث
// وإحصاءات وتشكيلة ومواجهات، مع توقّع صاحب الطلب.
//
// محمي كـ /live ولنفس السبب: الرد شخصي. أما التفاصيل نفسها فعامة،
// وصفحة /match/:id على الموقع تعرضها بلا حساب.
//
// قبل '/:id' لا لأن Express سيخلط بينهما (لن يفعل — المسار أطول)
// بل كي يُقرأ الملف من العام إلى الخاص.
router.get('/:id/match', requireAuth, async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) {
    return res.status(400).json({ error: 'fixture id must be an integer' });
  }

  const stale = await fixtureRepo.findByIdDetail(id);
  if (!stale) return res.status(404).json({ error: 'fixture not found' });

  // إنعاش عند الطلب كما في /live، ثم التفاصيل على الصفّ الطازج:
  // شاشة تعرض هدفاً في الخط الزمني ونتيجة لا تحويه تناقضٌ يراه
  // المستخدم قبل أن نراه نحن.
  const fixture = await liveRefresh.refresh([stale], () => fixtureRepo.findByIdDetail(id))
    .then((rows) => rows[0] ?? stale);

  const [details, [decorated]] = await Promise.all([
    matchDetailService.get(fixture),
    withMyPredictions(req.userId, [fixture]),
  ]);

  res.json({ fixture: decorated, ...details });
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
