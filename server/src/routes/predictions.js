// routes/predictions — توقعات المستخدم. كلها محمية بتسجيل الدخول.
const express = require('express');
const requireAuth = require('../middleware/requireAuth');
const predictionRepo = require('../repositories/predictionRepo');
const predictionService = require('../services/predictionService');

const router = express.Router();

// POST /api/predictions — { fixtureId, home, away }
//
// القواعد كلها في predictionService: الموقع يستدعيها أيضاً، ونسختان
// منها تنحرفان عند أول تعديل. والخطأ يصعد كما هو — معالج الأخطاء
// في app.js يعرف AuthError/PredictionError (status + expose).
router.post('/', requireAuth, async (req, res) => {
  const { fixtureId, home, away } = req.body || {};
  const prediction = await predictionService.submit({
    userId: req.userId, fixtureId, home, away,
  });
  res.status(201).json({ prediction });
});

// GET /api/predictions/mine — توقعاتي مع نتائجها ونقاطها
router.get('/mine', requireAuth, async (req, res) => {
  const predictions = await predictionRepo.findMine(req.userId);
  res.json({ predictions });
});

module.exports = router;
