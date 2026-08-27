// routes/predictions — توقعات المستخدم. كلها محمية بتسجيل الدخول.
const express = require('express');
const requireAuth = require('../middleware/requireAuth');
const predictionRepo = require('../repositories/predictionRepo');
const fixtureRepo = require('../repositories/fixtureRepo');

const router = express.Router();

// POST /api/predictions — { fixtureId, home, away }
// إنشاء أو تعديل — نفس المسار للاثنين (UPSERT). التعديل مسموح
// حتى لحظة الانطلاق حرفياً.
router.post('/', requireAuth, async (req, res) => {
  const { fixtureId, home, away } = req.body || {};

  // Number.isInteger ترفض "2" النصية و 2.5 و null دفعة واحدة.
  if (!Number.isInteger(fixtureId) ||
      !Number.isInteger(home) || !Number.isInteger(away) ||
      home < 0 || home > 99 || away < 0 || away > 99) {
    return res.status(400).json({ error: 'fixtureId و home و away أعداد صحيحة مطلوبة (0-99)' });
  }

  const fixture = await fixtureRepo.findById(fixtureId);
  if (!fixture) {
    return res.status(404).json({ error: 'المباراة غير موجودة' });
  }

  // القاعدة الذهبية للنزاهة: لا توقع بعد الانطلاق.
  // نفحص الحالة والوقت معاً: الحالة قد تتأخر 30 ثانية (دورة الكاش)
  // عن الواقع، لكن kickoff_at لا يكذب.
  if (fixture.status !== 'scheduled' || new Date(fixture.kickoff_at) <= new Date()) {
    return res.status(409).json({ error: 'أُغلق التوقع — المباراة انطلقت أو انتهت' });
  }

  const prediction = await predictionRepo.upsert({
    userId: req.userId,
    fixtureId,
    predHome: home,
    predAway: away,
  });
  res.status(201).json({ prediction });
});

// GET /api/predictions/mine — توقعاتي مع نتائجها ونقاطها
router.get('/mine', requireAuth, async (req, res) => {
  const predictions = await predictionRepo.findMine(req.userId);
  res.json({ predictions });
});

module.exports = router;
