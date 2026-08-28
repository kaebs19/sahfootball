// mailer — طبقة عزل للبريد الإلكتروني، بنفس فلسفة footballProvider:
// بقية المشروع يستدعي sendMail() ولا يعرف من يرسل فعلياً.
//
// عندنا ثلاثة drivers:
//   console  — يطبع الرسالة في اللوق ولا يرسل شيئاً. للتطوير فقط.
//   resend   — https://resend.com   (مفتاح واحد، أبسط تشغيل)
//   mailgun  — https://mailgun.com  (نطاق + مفتاح)
//
// المزوّدان الحقيقيان يعملان عبر HTTP API لا عبر SMTP، ولهذا لم
// نضف أي حزمة جديدة: fetch مدمج في Node 20. SMTP كان سيجرّ
// nodemailer وإعداد منافذ وTLS مقابل نفس النتيجة.
//
// إضافة مزوّد رابع = دالة واحدة هنا + سطر في DRIVERS، وصفر تعديلات
// في بقية المشروع.
const logger = require('../utils/logger');

// مهلة صارمة: بدون هذا يظل طلب استعادة كلمة السر معلقاً حتى تنتهي
// مهلة الـ socket الافتراضية (دقائق)، والمستخدم ينظر لشاشة محمّلة.
const TIMEOUT_MS = 10000;

// اسم المرسل الافتراضي. from يجب أن يكون نطاقاً موثّقاً عند المزوّد،
// وإلا رفض الرسالة — ولهذا هو إعداد إلزامي لا قيمة مكتوبة هنا.
const fromAddress = () => process.env.MAIL_FROM;

/** نداء HTTP موحّد: مهلة + رسالة خطأ تحمل رد المزوّد. */
async function post(url, { headers, body }) {
  let res;
  try {
    res = await fetch(url, {
      method: 'POST',
      headers,
      body,
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch (err) {
    // انقطاع شبكة أو تجاوز المهلة — ليس رفضاً من المزوّد.
    throw new Error(`تعذّر الوصول لمزوّد البريد: ${err.message}`);
  }

  if (!res.ok) {
    // نص الرد يحمل سبب الرفض الحقيقي (نطاق غير موثّق، مفتاح خاطئ،
    // حد يومي). بدونه يبقى الخطأ رقماً بلا معنى.
    const detail = await res.text().catch(() => '');
    throw new Error(`مزوّد البريد رفض الرسالة (${res.status}): ${detail.slice(0, 300)}`);
  }
}

const DRIVERS = {
  console({ to, subject, text }) {
    logger.info(`[mailer] ── mail to: ${to} ──`);
    logger.info(`[mailer] subject: ${subject}`);
    logger.info(`[mailer] ${text}`);
  },

  async resend({ to, subject, text, html }) {
    await post('https://api.resend.com/emails', {
      headers: {
        Authorization: `Bearer ${process.env.RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ from: fromAddress(), to: [to], subject, text, html }),
    });
  },

  async mailgun({ to, subject, text, html }) {
    const domain = process.env.MAILGUN_DOMAIN;
    // المنطقة الأوروبية نطاق مختلف تماماً؛ حساب أُنشئ في الاتحاد
    // الأوروبي يرد 401 على النطاق الأمريكي وكأن المفتاح خاطئ.
    const host = process.env.MAILGUN_REGION === 'eu'
      ? 'api.eu.mailgun.net'
      : 'api.mailgun.net';

    const form = new URLSearchParams({ from: fromAddress(), to, subject, text });
    if (html) form.set('html', html);

    await post(`https://${host}/v3/${domain}/messages`, {
      headers: {
        // Mailgun يستخدم Basic auth باسم ثابت "api".
        Authorization: `Basic ${Buffer.from(`api:${process.env.MAILGUN_API_KEY}`).toString('base64')}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: form,
    });
  },
};

/** أسماء الـ drivers المعروفة — يستعملها env.js في فحص الإقلاع. */
const DRIVER_NAMES = Object.keys(DRIVERS);

/** الإعدادات الإلزامية لكل driver حقيقي، لفحص الإقلاع. */
const DRIVER_REQUIREMENTS = {
  resend: ['RESEND_API_KEY', 'MAIL_FROM'],
  mailgun: ['MAILGUN_API_KEY', 'MAILGUN_DOMAIN', 'MAIL_FROM'],
};

/**
 * إرسال رسالة. text إلزامي (نسخة نصية دائماً — بعض العملاء لا
 * يعرضون HTML، وغيابها يرفع تصنيف السبام)، html اختياري.
 */
async function sendMail({ to, subject, text, html }) {
  const name = process.env.MAIL_DRIVER || 'console';
  const driver = DRIVERS[name];

  // أي driver غير معروف = خطأ إعداد صريح، أفضل من فشل صامت يجعل
  // المستخدم ينتظر بريداً لن يصل. (env.js يمسك هذا عند الإقلاع،
  // وهذا السطر يحمي من تغيير المتغيّر أثناء التشغيل.)
  if (!driver) {
    throw new Error(`MAIL_DRIVER غير معروف: ${name}. المتاح: ${DRIVER_NAMES.join(', ')}`);
  }

  await driver({ to, subject, text, html });

  if (name !== 'console') {
    // بلا عنوان المستقبل ولا محتوى الرسالة: اللوق ليس مكاناً لرموز
    // الاستعادة ولا لبريدات المستخدمين.
    logger.info(`[mailer] أُرسلت رسالة عبر ${name}`);
  }
}

module.exports = { sendMail, DRIVER_NAMES, DRIVER_REQUIREMENTS };
