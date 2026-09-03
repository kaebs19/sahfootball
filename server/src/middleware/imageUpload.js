// imageUpload — معالج رفع صورة واحدة (multer) بإعدادات موحّدة.
//
// كان داخل routes/profile للصورة الشخصية. حين صار للمجلس صورة أيضاً
// نُقل هنا: نسختان من قائمة الأنواع والحدّ الأقصى تتباعدان عند أول
// تشديد — وهذا بالذات إعداد أمني (ما يُقبل على القرص)، أسوأ مكان
// لنسختين.
//
// - الامتداد يُشتق من نوع الملف الفعلي (mimetype) لا من اسمه —
//   اسم الملف يكتبه العميل ولا نثق به.
// - اسم عشوائي بالكامل: لا معرّف مستخدم أو مجلس في الاسم (خصوصية:
//   رابط الصورة عام، ولا يجب أن يدل على صاحبه) ولا اسم أصلي (حقن
//   مسارات).
const crypto = require('crypto');
const multer = require('multer');
const { UPLOADS_DIR } = require('../utils/avatarFile');

const EXT_BY_MIME = { 'image/jpeg': '.jpg', 'image/png': '.png', 'image/webp': '.webp' };

const upload = multer({
  storage: multer.diskStorage({
    destination: UPLOADS_DIR,
    filename: (req, file, cb) => {
      cb(null, crypto.randomBytes(16).toString('hex') + EXT_BY_MIME[file.mimetype]);
    },
  }),
  limits: { fileSize: 2 * 1024 * 1024 }, // 2MB — كافية لصورة مربّعة
  fileFilter: (req, file, cb) => {
    if (EXT_BY_MIME[file.mimetype]) return cb(null, true);
    const err = new Error('نوع الملف غير مدعوم — jpeg أو png أو webp فقط');
    err.status = 400;
    err.expose = true;
    cb(err);
  },
});

module.exports = { upload, EXT_BY_MIME };
