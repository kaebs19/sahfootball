// routes/rules — قواعد اللعبة كما يعمل بها الخادم الآن.
//
// عام بلا تسجيل: القواعد ليست سرّاً، وشاشة التوقّع تحتاجها قبل
// أن يملك الزائر حساباً.
//
// ولماذا مسار أصلاً؟ لأن التطبيق كان يكتب الأرقام في نصّه:
// "نتيجة مضبوطة = 5 · فارق الأهداف = 3 · الفائز = 2". ثم صار
// المقياس 100/75/50 فبقي التطبيق يَعِد بخمس ويمنح مئة — والمستخدم
// لا يرى تناقضاً بل يرى كذباً. والأرقام في app_settings يعدّلها
// الأدمن، فأيّ نصّ مكتوب في عميل يصير كذباً عند أول تعديل.
const express = require('express');
const predictionService = require('../services/predictionService');
const championService = require('../services/championService');

const router = express.Router();

// GET /api/rules
router.get('/', async (req, res) => {
  const [scoring, multipliers, champion] = await Promise.all([
    predictionService.points(),
    predictionService.multipliers(),
    championService.config(),
  ]);
  res.json({ scoring, multipliers, champion });
});

module.exports = router;
