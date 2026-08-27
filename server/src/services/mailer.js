// mailer — طبقة عزل للبريد الإلكتروني، بنفس فلسفة footballProvider:
// بقية المشروع يستدعي sendMail() ولا يعرف من يرسل فعلياً.
//
// الآن عندنا driver واحد: console (يطبع الرسالة في اللوق) — يكفي
// تماماً للتطوير. عند اختيار مزود حقيقي (Resend / Amazon SES /
// Mailgun...) نضيف driver ثانياً هنا ونغيّر MAIL_DRIVER في .env،
// وصفر تعديلات في بقية المشروع.
const logger = require('../utils/logger');

async function sendMail({ to, subject, text }) {
  const driver = process.env.MAIL_DRIVER || 'console';

  if (driver === 'console') {
    logger.info(`[mailer] ── mail to: ${to} ──`);
    logger.info(`[mailer] subject: ${subject}`);
    logger.info(`[mailer] ${text}`);
    return;
  }

  // أي driver غير معروف = خطأ إعداد صريح، أفضل من فشل صامت
  // يجعل المستخدم ينتظر بريداً لن يصل.
  throw new Error(`Unknown MAIL_DRIVER: ${driver}`);
}

module.exports = { sendMail };
