// routes/leaderboard — لوحة الصدارة. عامة (بلا تسجيل دخول):
// شاشة الصدارة تصلح كإغراء للتسجيل في التطبيق.
const express = require('express');
const predictionRepo = require('../repositories/predictionRepo');

const router = express.Router();

// GET /api/leaderboard
router.get('/', async (req, res) => {
  const leaderboard = await predictionRepo.leaderboard();
  // نضيف الترتيب هنا وليس في SQL — مع تساوي النقاط يتساوى المركز
  // منطقياً، لكن للنسخة الأولى الترتيب التسلسلي البسيط يكفي.
  res.json({
    leaderboard: leaderboard.map((row, i) => ({ rank: i + 1, ...row })),
  });
});

module.exports = router;
