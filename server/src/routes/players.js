// routes/players — اللاعبون كما يراهم غيرهم.
//
// «ملفي» (routes/profile) يجيب «من أنا؟» لصاحب التوكن وحده. هذا
// المسار يجيب «من هذا؟» عن أي لاعب: صفّ في العرش أو عضو في مجلس
// يُضغط فيُفتح ملفه — نقاطه ومركزه ودقّته وحصيلته في كل دوري.
//
// عام بلا توكن، كالعرش نفسه: الضيف الذي يتصفّح الترتيب يستحق أن
// يعرف من يتصدّره، وصفحة /player/:id على الموقع عامة أصلاً — فما
// يُنشر هناك لا معنى لحجبه هنا.
//
// ما لا يخرج من هنا أهم مما يخرج: لا بريد ولا تاريخ تسجيل ولا
// دوريات يتابعها. الاسم والصورة والأرقام فقط — كل حقل يُضاف إلى
// هذا الرد يصير منشوراً لكل من عرف المعرّف.
const express = require('express');
const requireAuth = require('../middleware/requireAuth');
const userRepo = require('../repositories/userRepo');
const predictionRepo = require('../repositories/predictionRepo');
const badgeService = require('../services/badgeService');
const { isUuid } = require('../services/groupService');

const router = express.Router();

// GET /api/players/search?q= — للمسجّلين: إضافة عضو إلى مجلس.
// قبل /:id، وإلا التُقطت كلمة search معرّفاً.
//
// محمي بالتوكن عمداً رغم أن الملف نفسه عام: البحث يعدّد
// المستخدمين، والملف يعرض واحداً معروفاً سلفاً — والفرق بينهما هو
// الفرق بين «من هذا؟» و«من عندكم؟».
router.get('/search', requireAuth, async (req, res) => {
  const q = String(req.query.q || '').trim();
  if (q.length < 2) return res.json({ players: [] });
  const players = await userRepo.searchPublic(q, 10);
  res.json({ players });
});

// GET /api/players/:id — ملف لاعب عام
router.get('/:id', async (req, res) => {
  const id = String(req.params.id || '');
  if (!isUuid(id)) return res.status(404).json({ error: 'اللاعب غير موجود' });

  const player = await userRepo.findById(id);
  if (!player) return res.status(404).json({ error: 'اللاعب غير موجود' });

  const [stats, badges] = await Promise.all([
    predictionRepo.profileStats(id),
    badgeService.forUser(id),
  ]);

  // الحقول تُنتقى بالاسم لا بالنسخ: profileStats يحمل followed لكل
  // دوري وهي خيار شخصي لا شأن لغير صاحبه به، فتُسقَط هنا.
  res.json({
    player: {
      id: player.id,
      display_name: player.display_name || 'مشجع',
      avatar_url: player.avatar_url,
      favorite_team: stats?.favorite_team ?? null,
    },
    stats: stats && {
      rank: stats.rank,
      total_competitors: stats.total_competitors,
      total_points: stats.total_points,
      predictions_count: stats.predictions_count,
      settled_predictions: stats.settled_predictions,
      accuracy: stats.accuracy,
      longest_streak: stats.longest_streak,
      current_streak: stats.current_streak,
      recent_form: stats.recent_form,
      by_league: stats.by_league.map(({ followed, ...league }) => league),
    },
    badges,
  });
});

module.exports = router;
