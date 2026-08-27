// routes/teams — قائمة الفرق. قراءة فقط، من قاعدة البيانات
// (المزامنة هي من تجلب من المزود، وليس هذا المسار).
const express = require('express');
const teamRepo = require('../repositories/teamRepo');

const router = express.Router();

// GET /api/teams
router.get('/', async (req, res) => {
  const teams = await teamRepo.findAll();
  res.json({ teams });
});

module.exports = router;
