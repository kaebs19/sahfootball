// routes/groups — القروبات (الدوريات الخاصة). كلها تتطلب تسجيل دخول.
const crypto = require('crypto');
const express = require('express');
const requireAuth = require('../middleware/requireAuth');
const groupRepo = require('../repositories/groupRepo');

const router = express.Router();
router.use(requireAuth);

// حدود منطقية تمنع العبث (حسابات تنشئ آلاف القروبات).
const MAX_GROUPS_OWNED = 10;
const MAX_MEMBERS = 100;

// رمز الدعوة: 6 أحرف من أبجدية بلا حروف ملتبسة (لا O/0 ولا I/1/L) —
// الرمز سيُملى شفهياً ويُنسخ من واتساب، والالتباس عدو التجربة.
// 28^6 ≈ 480 مليون احتمال: التصادم نادر (نعيد المحاولة لو حدث)
// والتخمين العشوائي غير عملي.
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
function generateCode() {
  let code = '';
  for (let i = 0; i < 6; i++) {
    code += CODE_ALPHABET[crypto.randomInt(CODE_ALPHABET.length)];
  }
  return code;
}

// POST /api/groups — { name } — إنشاء قروب
router.post('/', async (req, res) => {
  const name = String(req.body?.name || '').trim();
  if (name.length < 2 || name.length > 50) {
    return res.status(400).json({ error: 'اسم القروب يجب أن يكون بين 2 و 50 حرفاً' });
  }

  if (await groupRepo.countOwnedBy(req.userId) >= MAX_GROUPS_OWNED) {
    return res.status(400).json({ error: `الحد الأقصى ${MAX_GROUPS_OWNED} قروبات لكل مستخدم` });
  }

  // حلقة التصادم: لو صادف الرمز المولد رمزاً موجوداً (قيد UNIQUE
  // يرفضه) نولّد غيره. 5 محاولات أكثر من كافية إحصائياً.
  for (let attempt = 0; attempt < 5; attempt++) {
    try {
      const group = await groupRepo.create({
        name,
        inviteCode: generateCode(),
        ownerId: req.userId,
      });
      return res.status(201).json({ group });
    } catch (err) {
      // 23505 = رمز خطأ PostgreSQL الثابت لانتهاك قيد UNIQUE
      if (err.code !== '23505') throw err;
    }
  }
  throw new Error('failed to generate a unique invite code');
});

// POST /api/groups/join — { code } — انضمام برمز الدعوة
router.post('/join', async (req, res) => {
  // نطبّع الرمز: مسافات وحروف صغيرة من النسخ واللصق لا تفشل الانضمام.
  const code = String(req.body?.code || '').trim().toUpperCase();

  const group = await groupRepo.findByCode(code);
  if (!group) {
    return res.status(404).json({ error: 'رمز الدعوة غير صحيح' });
  }
  if (await groupRepo.isMember(group.id, req.userId)) {
    return res.status(409).json({ error: 'أنت عضو في هذا القروب بالفعل' });
  }
  if (await groupRepo.memberCount(group.id) >= MAX_MEMBERS) {
    return res.status(409).json({ error: 'القروب ممتلئ' });
  }

  await groupRepo.addMember(group.id, req.userId);
  res.status(201).json({ group: { id: group.id, name: group.name } });
});

// GET /api/groups/mine — قروباتي
router.get('/mine', async (req, res) => {
  const groups = await groupRepo.findMine(req.userId);
  res.json({ groups });
});

// GET /api/groups/:id — تفاصيل القروب + ترتيب أعضائه.
// للأعضاء فقط: القروبات خاصة، ومعرفة الـ id لا تكفي للاطلاع.
router.get('/:id', async (req, res) => {
  const { id } = req.params;

  if (!(await groupRepo.isMember(id, req.userId).catch(() => false))) {
    // 404 وليس 403: لغير العضو، وجود القروب نفسه معلومة لا نؤكدها.
    return res.status(404).json({ error: 'القروب غير موجود' });
  }

  const group = await groupRepo.findById(id);
  const leaderboard = await groupRepo.leaderboard(id);
  res.json({
    group,
    leaderboard: leaderboard.map((row, i) => ({ rank: i + 1, ...row })),
  });
});

// GET /api/groups/:id/fixtures/:fixtureId/predictions
// توقعات أعضاء القروب على مباراة — الميزة الاجتماعية الأساسية:
// "ماذا توقع أصحابي؟"
//
// قاعدة الكشف شرطان معاً:
//
// 1) أن يكون باب التوقع قد أُغلق — شرط مطابق حرفياً لشرط القفل في
//    routes/predictions.js، فلا فجوة زمنية بين "أغلق" و"انكشف"،
//    وإلا نسخ الأعضاء توقعات بعضهم.
//
// 2) أن يكون الطالب نفسه قد توقّع تلك المباراة. من لم يشارك لا يرى
//    ما اختاره غيره: التوقع ثمن الاطلاع، وبدون هذا الشرط يصير
//    المجلس مكاناً يُتفرَّج فيه بلا مخاطرة — وهي أسرع طريقة لقتل
//    المنافسة. الشرط في السيرفر لا في الواجهة، لأن ما يُرسل يُقرأ
//    مهما فعلت الواجهة به.
router.get('/:id/fixtures/:fixtureId/predictions', async (req, res) => {
  const { id } = req.params;
  const fixtureId = Number(req.params.fixtureId);
  if (!Number.isInteger(fixtureId)) {
    return res.status(400).json({ error: 'معرّف المباراة غير صالح' });
  }

  if (!(await groupRepo.isMember(id, req.userId).catch(() => false))) {
    return res.status(404).json({ error: 'القروب غير موجود' });
  }

  const fixtureRepo = require('../repositories/fixtureRepo');
  const fixture = await fixtureRepo.findById(fixtureId);
  if (!fixture) return res.status(404).json({ error: 'المباراة غير موجودة' });

  const locked =
    fixture.status !== 'scheduled' || new Date(fixture.kickoff_at) <= new Date();

  const rows = await groupRepo.fixturePredictions(id, fixtureId);

  const mine = rows.find((r) => r.user_id === req.userId);
  const viewerPredicted = Boolean(mine && mine.pred_home !== null);
  const revealed = locked && viewerPredicted;
  const predictions = rows.map((r) => {
    const predicted = r.pred_home !== null;
    if (!revealed) {
      // قبل الكشف: نقول فقط من توقع ومن لا — يكفي لإثارة الحماس
      // ("8 من 10 توقعوا!") دون كشف المحتوى.
      return { user_id: r.user_id, display_name: r.display_name, avatar_url: r.avatar_url, predicted };
    }
    return {
      user_id: r.user_id,
      display_name: r.display_name,
      avatar_url: r.avatar_url,
      predicted,
      pred_home: r.pred_home,
      pred_away: r.pred_away,
      points: r.points, // null = لم يُحتسب بعد (المباراة جارية)
    };
  });

  // viewer_predicted و locked ينزلان مع الرد كي تعرف الواجهة سبب
  // الإخفاء: "المباراة لم تبدأ" و"لم تتوقّع أنت" رسالتان مختلفتان،
  // والثانية فيها فعل يفعله المستخدم الآن.
  res.json({ fixture, revealed, locked, viewer_predicted: viewerPredicted, predictions });
});

// POST /api/groups/:id/leave — مغادرة
router.post('/:id/leave', async (req, res) => {
  const { id } = req.params;
  const group = await groupRepo.findById(id).catch(() => null);
  if (!group || !(await groupRepo.isMember(id, req.userId))) {
    return res.status(404).json({ error: 'القروب غير موجود' });
  }
  // المالك لا يغادر: قروب بلا مالك لا أحد يستطيع حذفه أو إدارته.
  // خياره هو الحذف الكامل (المسار التالي).
  if (group.owner_id === req.userId) {
    return res.status(400).json({ error: 'مالك القروب لا يغادره — يمكنه حذفه' });
  }
  await groupRepo.removeMember(id, req.userId);
  res.status(204).end();
});

// DELETE /api/groups/:id — حذف القروب (للمالك فقط)
router.delete('/:id', async (req, res) => {
  const group = await groupRepo.findById(req.params.id).catch(() => null);
  if (!group) return res.status(404).json({ error: 'القروب غير موجود' });
  if (group.owner_id !== req.userId) {
    return res.status(403).json({ error: 'حذف القروب لمالكه فقط' });
  }
  await groupRepo.remove(group.id);
  res.status(204).end();
});

module.exports = router;
