// routes/predictions — توقعات المستخدم. كلها محمية بتسجيل الدخول.
const express = require('express');
const requireAuth = require('../middleware/requireAuth');
const predictionRepo = require('../repositories/predictionRepo');
const predictionService = require('../services/predictionService');

const router = express.Router();

// POST /api/predictions — { fixtureId, home, away, multiplier? }
//
// القواعد كلها في predictionService: الموقع يستدعيها أيضاً، ونسختان
// منها تنحرفان عند أول تعديل. والخطأ يصعد كما هو — معالج الأخطاء
// في app.js يعرف AuthError/PredictionError (status + expose).
router.post('/', requireAuth, async (req, res) => {
  const { fixtureId, home, away, multiplier } = req.body || {};

  // multiplier غائب = "لا تلمسه" لا "أرجعه إلى 1". هذا يحفظ
  // مضاعِفاً وُضع من الموقع حين يعدّل صاحبه توقّعه من التطبيق —
  // ويبقي النسخ القديمة من التطبيق (التي لا ترسله) عاملةً كما هي.
  const prediction = await predictionService.submit({
    userId: req.userId, fixtureId, home, away,
    multiplier: multiplier === undefined ? null : multiplier,
  });

  // multiplierDenied يعلَّم على الصف حين تنفد الحصة: التوقّع نجح
  // والأداة وحدها لم تُطبَّق، فرمي خطأ هنا يمحو توقّعاً صحيحاً.
  res.status(201).json({
    prediction,
    multiplierDenied: prediction?.multiplierDenied ?? null,
  });
});

// GET /api/predictions/multiplier/:fixtureId — حالة الأداة لهذه المباراة
//
// مسار مستقل لا حقل في المباراة: الحالة تُقرأ عند فتح شيت التوقّع
// وحده، وحملُها مع كل مباراة في قائمة اليوم يعني عشرين استعلام
// عدّ لا يُعرض منها شيء.
router.get('/multiplier/:fixtureId', requireAuth, async (req, res) => {
  const fixtureId = Number(req.params.fixtureId);
  if (!Number.isInteger(fixtureId)) {
    return res.status(400).json({ error: 'معرّف المباراة غير صالح' });
  }

  const fixtureRepo = require('../repositories/fixtureRepo');
  const fixture = await fixtureRepo.findById(fixtureId);
  if (!fixture) return res.status(404).json({ error: 'المباراة غير موجودة' });

  const mine = (await predictionRepo
    .findByUserAndFixtures(req.userId, [fixtureId]))[0] || null;

  res.json({ multiplier: await predictionService.multiplierState(req.userId, fixture, mine) });
});

// GET /api/predictions/mine — توقعاتي مع نتائجها ونقاطها
router.get('/mine', requireAuth, async (req, res) => {
  const predictions = await predictionRepo.findMine(req.userId);
  res.json({ predictions });
});

module.exports = router;
