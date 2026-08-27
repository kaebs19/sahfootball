// avatarFile — مكان واحد يعرف أين تسكن الصور المرفوعة وكيف تُحذف.
//
// لماذا مِلف مستقل؟ الحذف يجري الآن من مكانين: المستخدم يغيّر صورته
// (routes/profile) والأدمن يزيل صورة مسيئة أو يحذف حساباً كاملاً
// (routes/admin). نسخ الدالة في الملفين يعني أن أي تشديد أمني
// مستقبلاً قد يُطبَّق على نسخة وينسى الأخرى — وهذه بالذات دالة
// تحذف ملفات من القرص، أسوأ مكان لتفرّع نسختين.
const fs = require('fs/promises');
const path = require('path');

const UPLOADS_DIR = path.join(__dirname, '..', '..', 'uploads');

// حذف ملف صورة من القرص. أخطاؤه تُبتلع عمداً: ملف مفقود أصلاً
// لا يجب أن يفشل عملية المستخدم أو الأدمن الحالية.
async function deleteAvatarFile(avatarUrl) {
  if (!avatarUrl || !avatarUrl.startsWith('/uploads/')) return;
  // basename يقص أي مسار ويبقي اسم الملف فقط — حتى لو خُزّن في
  // القاعدة شيء غريب مثل "/uploads/../../.env" لا نحذف خارج مجلد
  // uploads أبداً.
  const filePath = path.join(UPLOADS_DIR, path.basename(avatarUrl));
  await fs.unlink(filePath).catch(() => {});
}

module.exports = { UPLOADS_DIR, deleteAvatarFile };
