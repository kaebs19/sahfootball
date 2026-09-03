// routes/profile — الملف الشخصي: الاسم، الفريق المفضل، الصورة.
// كلها للمستخدم المسجل نفسه (لا يعدل أحد ملف غيره — المعرّف يؤخذ
// من التوكن حصراً، لا من الطلب).
const express = require('express');
const requireAuth = require('../middleware/requireAuth');
const userRepo = require('../repositories/userRepo');
const predictionRepo = require('../repositories/predictionRepo');
const badgeService = require('../services/badgeService');
const { deleteAvatarFile } = require('../utils/avatarFile');
// إعداد multer (الأنواع، الحدّ، الاسم العشوائي) مشترك مع صورة
// المجلس — راجع middleware/imageUpload.
const { upload } = require('../middleware/imageUpload');
const db = require('../config/db');

const router = express.Router();
router.use(requireAuth);

// PUT /api/profile — { displayName?, favoriteTeamId? }
router.put('/', async (req, res) => {
  const { displayName, favoriteTeamId } = req.body || {};
  const changes = {};

  if (displayName !== undefined) {
    const name = String(displayName).trim();
    if (name.length < 2 || name.length > 50) {
      return res.status(400).json({ error: 'الاسم يجب أن يكون بين 2 و 50 حرفاً' });
    }
    changes.displayName = name;
  }

  if (favoriteTeamId !== undefined) {
    if (favoriteTeamId === null) {
      changes.favoriteTeamId = null; // إزالة التفضيل
    } else {
      if (!Number.isInteger(favoriteTeamId)) {
        return res.status(400).json({ error: 'معرّف الفريق غير صالح' });
      }
      // نتحقق أن الفريق موجود عندنا فعلاً — رسالتنا أوضح من خطأ
      // المفتاح الأجنبي الخام، والتطبيق يميز 400 عن عطل 500.
      const { rows } = await db.query('SELECT 1 FROM teams WHERE id = $1', [favoriteTeamId]);
      if (rows.length === 0) {
        return res.status(400).json({ error: 'الفريق غير موجود' });
      }
      changes.favoriteTeamId = favoriteTeamId;
    }
  }

  await userRepo.updateProfile(req.userId, changes);
  const user = await userRepo.findById(req.userId);
  res.json({ user });
});

// GET /api/profile/stats — أرقام تبويب "ملفي": المركز في العرش،
// النقاط، الدقة، السلاسل، وشكل الأداء في آخر الجولات، والأوسمة.
//
// المعرّف من req.userId (أي من التوكن) ولا يقبل معرّفاً في المسار:
// هذه إحصاءات المستخدم عن نفسه، وفتح الباب لقراءة إحصاءات غيره
// قرار منتج مستقل لا أثر جانبي لمسار.
//
// الأوسمة في نفس الرد لا في مسار ثانٍ: الشاشة واحدة وتُرسم دفعة
// واحدة، ومسار منفصل يعني طلبين ودورتي شبكة لرسم صفحة واحدة.
router.get('/stats', async (req, res) => {
  // مصارحة: هذا GET يكتب في القاعدة.
  //
  // المكسب أن من استحق وسماً قبل وجود هذه الميزة (أو بين احتسابين)
  // يراه لحظة فتح الشاشة، لا بعد انتظار احتساب الجولة القادمة —
  // وبلا سكربت تعبئة يعمل بعد كل نشر. الكتابة آمنة التكرار ومقصورة
  // على مستخدم واحد هو صاحب الطلب.
  // والثمن حقيقي ويجب ألا يُنسى: القراءة لم تعد مجانية، فلا تصلح
  // للتخزين المؤقت (cache) ولا لقارئ من نسخة قراءة فقط لو فصلناها
  // يوماً. عندها ينتقل هذا السطر إلى وظيفة دورية ويبقى المسار قراءة
  // خالصة. اليوم: مستخدم واحد، جولتان، ولا وظيفة إضافية تُصان.
  await badgeService.evaluateQuietly(req.userId);

  const [stats, badges] = await Promise.all([
    predictionRepo.profileStats(req.userId),
    badgeService.forUser(req.userId),
  ]);

  res.json({ stats: stats ? { ...stats, badges } : null });
});

// POST /api/profile/avatar — multipart برفع حقل اسمه "avatar"
// upload.single تضع الملف المحفوظ في req.file وتتكفل بالحد والنوع.
router.post('/avatar', upload.single('avatar'), async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: 'أرفق الصورة في حقل avatar' });
  }

  // نحذف القديمة بعد نجاح حفظ الجديدة — بالترتيب المعاكس قد يبقى
  // المستخدم بلا صورة لو فشلت الخطوة الثانية.
  const before = await userRepo.findById(req.userId);
  const avatarUrl = `/uploads/${req.file.filename}`;
  await userRepo.updateProfile(req.userId, { avatarUrl });
  await deleteAvatarFile(before.avatar_url);

  const user = await userRepo.findById(req.userId);
  res.json({ user });
});

// DELETE /api/profile/avatar — إزالة الصورة
router.delete('/avatar', async (req, res) => {
  const before = await userRepo.findById(req.userId);
  await userRepo.updateProfile(req.userId, { avatarUrl: null });
  await deleteAvatarFile(before.avatar_url);
  res.status(204).end();
});

module.exports = router;
