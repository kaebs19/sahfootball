// routes/leagues — متابعة الدوريات.
//
// كلها تتطلب تسجيل دخول: شاشة الاختيار في التطبيق لا تُبلغ إلا
// بعده، والقائمة بلا "أتابعه؟" لا تفيد شيئاً.
const express = require('express');
const requireAuth = require('../middleware/requireAuth');
const leagueRepo = require('../repositories/leagueRepo');
const championRepo = require('../repositories/championRepo');

const router = express.Router();
router.use(requireAuth);

// GET /api/leagues — دوريات اللعبة، ومعها ما يتابعه صاحب الطلب
router.get('/', async (req, res) => {
  const leagues = (await leagueRepo.findEnabled()).filter((l) => l.in_app);
  const followed = await championRepo.followedIds(req.userId).catch(() => []);

  res.json({
    leagues: leagues.map((l) => ({
      id: l.id,
      name: l.name,
      // من مسارنا لا من العمود: leagues.logo_url فارغ لكل الدوريات
      // (المزوّد لا يُعيده في نداء المباريات الذي نزامن به)، ومسار
      // /logos يخدم النسخة المصغّرة عندنا ويحوّل للمزوّد إن غابت.
      // ولو أرجعنا العمود لعرض التطبيق أيقونةً بديلة إلى الأبد.
      logo_url: `/logos/league-${l.id}.png`,
      season: l.season,
      followed: followed.includes(l.id),
    })),
  });
});

// PUT /api/leagues/followed — { leagueIds: [307, 39] }
//
// القائمة كاملةً لا إضافة/حذف: الحالة النهائية هي ما أرسله
// المستخدم بالضبط، بلا منطقٍ يقرّر ما يُضاف وما يُحذف — وذلك
// المنطق هو ما يخطئ.
router.put('/followed', async (req, res) => {
  const asked = Array.isArray(req.body?.leagueIds) ? req.body.leagueIds : null;
  if (!asked) return res.status(400).json({ error: 'leagueIds مطلوبة كمصفوفة' });

  // نصفّيها بدوريات اللعبة: المفتاح الأجنبي يمنع المعرّف الخيالي،
  // ولا يمنع متابعة دوري يُعرض ولا يُلعب — فتظهر بطاقة بطلٍ لا
  // مباريات تحتها.
  const playable = (await leagueRepo.findEnabled())
    .filter((l) => l.in_app).map((l) => l.id);
  const ids = [...new Set(asked.map(Number).filter((id) => playable.includes(id)))];

  await championRepo.setFollowed(req.userId, ids);
  res.json({ leagueIds: ids });
});

module.exports = router;
