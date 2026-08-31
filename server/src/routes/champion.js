// routes/champion — رهان البطل للتطبيق.
//
// القواعد كلها في championService: الموقع يستدعيها أيضاً، ونسختان
// منها تنحرفان عند أول تعديل على التسعير — وهو أكثر ما يُعدَّل في
// هذه الميزة.
const express = require('express');
const requireAuth = require('../middleware/requireAuth');
const leagueRepo = require('../repositories/leagueRepo');
const championService = require('../services/championService');

const router = express.Router();
router.use(requireAuth);

// GET /api/champion — بطاقة لكل دوري يتابعه: أنديته، سعر اليوم، ورهانه
router.get('/', async (req, res) => {
  const cards = await championService.cards(req.userId);

  // الشعارات من مسارنا لا من أعمدة القاعدة: عمود الدوري فارغ
  // أصلاً، وشعارات الأندية عند المزوّد بحجمها الكامل بينما /logos
  // يخدم نسخة 64 بكسل مخزّنة عندنا. الموقع يفعل هذا بنفسه
  // (localLogo)، والتطبيق كان يقرأ العمود الخام.
  res.json({
    cards: cards.map((c) => ({
      ...c,
      league: { ...c.league, logo_url: `/logos/league-${c.league.id}.png` },
      teams: c.teams.map((t) => ({ ...t, logo_url: `/logos/team-${t.id}.png` })),
    })),
  });
});

// POST /api/champion — { leagueId, teamId }
router.post('/', async (req, res) => {
  const leagueId = Number(req.body?.leagueId);
  const teamId = Number(req.body?.teamId);
  if (!Number.isInteger(leagueId) || !Number.isInteger(teamId)) {
    return res.status(400).json({ error: 'معرّفان غير صالحين' });
  }

  // الموسم من القاعدة لا من الطلب: لو أرسله العميل لأمكن الرهان
  // على موسم ماضٍ انتهى بطله — ألف نقطة مضمونة.
  const league = (await leagueRepo.findEnabled())
    .find((l) => l.id === leagueId && l.in_app);
  if (!league) return res.status(404).json({ error: 'الدوري غير موجود' });

  const pick = await championService.pick({
    userId: req.userId, leagueId, season: league.season, teamId,
  });
  if (!pick) return res.status(409).json({ error: 'سُوّي هذا الرهان فلا يُغيَّر' });

  res.status(201).json({ pick });
});

module.exports = router;
