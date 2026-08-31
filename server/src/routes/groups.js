// routes/groups — المجالس (الدوريات الخاصة). كلها تتطلب تسجيل دخول.
//
// القواعد كلها في groupService: للمجالس بابان الآن (التطبيق
// والموقع)، ونسخُها هنا يعني أن أول تعديل عليها يُنسى في أحدهما.
// هذا الملف واجهة JSON فوق تلك القواعد لا أكثر.
const express = require('express');
const requireAuth = require('../middleware/requireAuth');
const groupRepo = require('../repositories/groupRepo');
const groupService = require('../services/groupService');

const router = express.Router();
router.use(requireAuth);

/** يحوّل خطأ الخدمة إلى رد JSON، أو يعيد رميه إن لم يكن متوقّعاً. */
function fail(res, err) {
  if (err.status && err.expose) return res.status(err.status).json({ error: err.message });
  throw err;
}

// POST /api/groups — { name } — إنشاء مجلس
router.post('/', async (req, res) => {
  try {
    const group = await groupService.create({ ownerId: req.userId, name: req.body?.name });
    res.status(201).json({ group });
  } catch (err) { fail(res, err); }
});

// POST /api/groups/join — { code } — انضمام برمز الدعوة
router.post('/join', async (req, res) => {
  try {
    const { group, already } = await groupService.join({
      userId: req.userId, code: req.body?.code,
    });
    // التطبيق يعتمد 409 للعضو القائم منذ نسخته الأولى، فنُبقيه:
    // الخدمة ترجع already بدل الرمي كي يقرّر كل باب بنفسه، والويب
    // يقرأها ترحيباً لا خطأً.
    if (already) return res.status(409).json({ error: 'أنت عضو في هذا المجلس بالفعل' });
    res.status(201).json({ group: { id: group.id, name: group.name } });
  } catch (err) { fail(res, err); }
});

// GET /api/groups/mine — مجالسي
router.get('/mine', async (req, res) => {
  const groups = await groupRepo.findMine(req.userId);
  res.json({ groups });
});

// GET /api/groups/:id — تفاصيل المجلس + ترتيب أعضائه (للأعضاء فقط)
router.get('/:id', async (req, res) => {
  try {
    const { group, members } = await groupService.view({
      userId: req.userId, groupId: req.params.id,
    });
    res.json({
      group,
      leaderboard: members.map((row, i) => ({ rank: i + 1, ...row })),
    });
  } catch (err) { fail(res, err); }
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
  try {
    await groupService.leave({ userId: req.userId, groupId: req.params.id });
    res.status(204).end();
  } catch (err) { fail(res, err); }
});

// DELETE /api/groups/:id — حذف المجلس (للمالك فقط)
router.delete('/:id', async (req, res) => {
  try {
    await groupService.remove({ userId: req.userId, groupId: req.params.id });
    res.status(204).end();
  } catch (err) { fail(res, err); }
});

module.exports = router;
