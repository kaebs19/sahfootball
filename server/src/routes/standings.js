// routes/standings — جدول الترتيب.
//
// الترتيب لا يُخزَّن في قاعدة البيانات (بيانات مشتقة، انظر شرح
// standingsMapper). كل الخطوات (مزود ← mapper ← دمج الأسماء
// العربية) في standingsService لأن لوحة التحكم تحتاجها أيضاً.
const express = require('express');
const standingsService = require('../services/standingsService');

const router = express.Router();

// GET /api/standings — الدوري الافتراضي من .env (سلوك التطبيق الحالي).
router.get('/', async (req, res) => {
  const standings = await standingsService.getStandings();
  res.json({ standings });
});

module.exports = router;
