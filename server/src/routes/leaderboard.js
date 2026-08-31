// routes/leaderboard — لوحة الصدارة. عامة (بلا تسجيل دخول):
// شاشة الصدارة تصلح كإغراء للتسجيل في التطبيق.
const express = require('express');
const predictionRepo = require('../repositories/predictionRepo');

const router = express.Router();

// GET /api/leaderboard
router.get('/', async (req, res) => {
  // ?league= اختياري: العرش العام يقيس النشاط بقدر ما يقيس
  // الإتقان — من يلعب في ستة دوريات يجمع أكثر ممّن يتقن واحداً.
  // وتحديد الدوري يُعيد المقارنة إلى ما يقارَن.
  const asked = String(req.query.league || '');
  const league = /^\d+$/.test(asked) ? Number(asked) : null;

  const leaderboard = await predictionRepo.leaderboard(50, league);
  // نضيف الترتيب هنا وليس في SQL — مع تساوي النقاط يتساوى المركز
  // منطقياً، لكن للنسخة الأولى الترتيب التسلسلي البسيط يكفي.
  res.json({
    leaderboard: leaderboard.map((row, i) => ({ rank: i + 1, ...row })),
  });
});

module.exports = router;
