// routes/profile — الملف الشخصي: الاسم، الفريق المفضل، الصورة.
// كلها للمستخدم المسجل نفسه (لا يعدل أحد ملف غيره — المعرّف يؤخذ
// من التوكن حصراً، لا من الطلب).
const crypto = require('crypto');
const express = require('express');
const multer = require('multer');
const requireAuth = require('../middleware/requireAuth');
const userRepo = require('../repositories/userRepo');
const { UPLOADS_DIR, deleteAvatarFile } = require('../utils/avatarFile');
const db = require('../config/db');

const router = express.Router();
router.use(requireAuth);

// إعداد multer (معالج الملفات المرفوعة في Express):
// - الامتداد يُشتق من نوع الملف الفعلي (mimetype) لا من اسمه —
//   اسم الملف يكتبه العميل ولا نثق به.
// - اسم عشوائي بالكامل: لا معرّف مستخدم في الاسم (خصوصية: رابط
//   الصورة عام، ولا يجب أن يدل على صاحبه) ولا اسم أصلي (حقن مسارات).
const EXT_BY_MIME = { 'image/jpeg': '.jpg', 'image/png': '.png', 'image/webp': '.webp' };

const upload = multer({
  storage: multer.diskStorage({
    destination: UPLOADS_DIR,
    filename: (req, file, cb) => {
      cb(null, crypto.randomBytes(16).toString('hex') + EXT_BY_MIME[file.mimetype]);
    },
  }),
  limits: { fileSize: 2 * 1024 * 1024 }, // 2MB — كافية لصورة شخصية
  fileFilter: (req, file, cb) => {
    if (EXT_BY_MIME[file.mimetype]) return cb(null, true);
    const err = new Error('نوع الملف غير مدعوم — jpeg أو png أو webp فقط');
    err.status = 400;
    err.expose = true;
    cb(err);
  },
});

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
