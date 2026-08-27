// Logger بسيط جداً فوق console.
//
// لماذا لم نستخدم مكتبة مثل winston أو pino؟
// في هذه المرحلة لا نحتاج ملفات log ولا شحن السجلات لخدمة خارجية.
// غلاف بسيط يوحّد الشكل (وقت + مستوى) يكفي، ولأن كل المشروع يستدعي
// logger.* وليس console.* مباشرة، يمكننا استبدال التنفيذ لاحقاً
// بمكتبة حقيقية دون تعديل أي ملف آخر — نفس فكرة طبقة العزل.

function ts() {
  return new Date().toISOString();
}

module.exports = {
  info: (...args) => console.log(ts(), '[INFO]', ...args),
  warn: (...args) => console.warn(ts(), '[WARN]', ...args),
  error: (...args) => console.error(ts(), '[ERROR]', ...args),
};
