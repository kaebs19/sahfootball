// env — التحقق من الإعدادات قبل أن يبدأ السيرفر باستقبال الطلبات.
//
// لماذا نوقف الإقلاع بدل أن نكتفي بتحذير؟ لأن أخطاء الإعداد في
// الإنتاج صامتة وخطيرة معاً. سيرفر يقلع بـ JWT_SECRET الافتراضي
// يعمل تماماً: يسجّل الدخول ويصدر التوكنات ولا شيء يبدو معطّلاً —
// بينما أي شخص يعرف القيمة الافتراضية يستطيع تزوير توكن لأي حساب،
// ولن تكتشف ذلك أبداً من اللوق. الانهيار عند الإقلاع صاخب ويُصلَح
// في دقيقة؛ الثغرة الصامتة تبقى شهوراً.
//
// القاعدة هنا: ما يكسر الأمان أو يفقد البيانات = توقف. وما يعطّل
// ميزة واحدة = تحذير مكتوب في اللوق كي يبقى مرئياً.
const logger = require('../utils/logger');
const { DRIVER_NAMES, DRIVER_REQUIREMENTS } = require('../services/mailer');
const push = require('../services/pushProvider');

const isProduction = () => process.env.NODE_ENV === 'production';

// قيم .env.example — وجودها في الإنتاج يعني أن أحداً نسخ الملف
// ولم يملأه.
const PLACEHOLDERS = [
  'change-me',
  'user:pass@localhost',
  'your-key-here',
];

function looksLikePlaceholder(value) {
  const v = String(value || '').toLowerCase();
  return PLACEHOLDERS.some((p) => v.includes(p));
}

function check() {
  const errors = [];
  const warnings = [];
  const prod = isProduction();

  // ── ما يوقف الإقلاع ──────────────────────────────────────────

  if (!process.env.DATABASE_URL) {
    errors.push('DATABASE_URL مفقود — لا اتصال بقاعدة البيانات.');
  } else if (prod && looksLikePlaceholder(process.env.DATABASE_URL)) {
    errors.push('DATABASE_URL ما زال قيمة المثال — املأه ببيانات قاعدتك.');
  }

  const secret = process.env.JWT_SECRET || '';
  if (!secret) {
    errors.push('JWT_SECRET مفقود — لا يمكن توقيع توكنات الدخول.');
  } else if (prod && (looksLikePlaceholder(secret) || secret.length < 32)) {
    errors.push(
      'JWT_SECRET ضعيف أو ما زال قيمة المثال. ولّد واحداً جديداً:\n' +
      '        openssl rand -hex 32'
    );
  }

  // مفتاح المزوّد مطلوب إلا في وضع العينات (بيانات محلية للتجربة).
  const useSamples = process.env.USE_SAMPLES === 'true';
  if (!useSamples && !process.env.FOOTBALL_API_KEY) {
    errors.push(
      'FOOTBALL_API_KEY مفقود. اضبطه، أو شغّل بـ USE_SAMPLES=true للتجربة بلا مزوّد.'
    );
  }

  if (prod && useSamples) {
    errors.push(
      'USE_SAMPLES=true في الإنتاج — سيخدم المستخدمين بيانات تجريبية ثابتة بدل المباريات الحقيقية.'
    );
  }

  // البريد: اسم driver مجهول أو مفتاح ناقص لا يظهر إلا حين يطلب
  // مستخدم استعادة كلمته — أي بعد أسابيع من النشر وفي أسوأ لحظة.
  // نمسكه عند الإقلاع بدلاً من ذلك.
  const mailDriver = process.env.MAIL_DRIVER || 'console';
  if (!DRIVER_NAMES.includes(mailDriver)) {
    errors.push(
      `MAIL_DRIVER غير معروف: ${mailDriver}. المتاح: ${DRIVER_NAMES.join('، ')}.`
    );
  } else {
    const missing = (DRIVER_REQUIREMENTS[mailDriver] || [])
      .filter((k) => !process.env[k]);
    if (missing.length) {
      errors.push(
        `MAIL_DRIVER=${mailDriver} يحتاج ${missing.join('، ')} — بدونها لن تُرسل أي رسالة.`
      );
    }
  }

  // الإشعارات: driver مجهول يعني أن كل إشعار سيرمي داخل وظيفة
  // مجدولة — أي فشل صامت في اللوق لا يراه أحد. نمسكه هنا.
  const pushDriver = process.env.PUSH_DRIVER || 'console';
  if (!push.DRIVER_NAMES.includes(pushDriver)) {
    errors.push(
      `PUSH_DRIVER غير معروف: ${pushDriver}. المتاح: ${push.DRIVER_NAMES.join('، ')}.`
    );
  } else if (pushDriver === 'real') {
    // منصة واحدة إعداد مشروع، لا خطأ. لكن ألا تكتمل أي منصة يعني
    // driver حقيقي لا يستطيع الوصول لجهاز واحد على وجه الأرض.
    const apnsReady = push.APNS_KEYS.every((k) => process.env[k]);
    const fcmReady = push.FCM_KEYS.every((k) => process.env[k]);

    if (!apnsReady && !fcmReady) {
      errors.push(
        'PUSH_DRIVER=real بلا إعداد مكتمل لأي منصة. ' +
        `iOS يحتاج ${push.APNS_KEYS.join('، ')}، وأندرويد يحتاج ${push.FCM_KEYS.join('، ')}.`
      );
    } else if (!apnsReady) {
      warnings.push('إعداد APNs ناقص — أجهزة iOS لن يصلها أي إشعار.');
    } else if (!fcmReady) {
      warnings.push('إعداد FCM ناقص — أجهزة أندرويد لن يصلها أي إشعار.');
    }
  }

  // ── ما يستحق تحذيراً فقط ──────────────────────────────────────

  if (prod && mailDriver === 'console') {
    warnings.push(
      'MAIL_DRIVER=console: رموز استعادة كلمة المرور تُطبع في اللوق ولا تصل لأحد. ' +
      'من ينسى كلمته يفقد حسابه.'
    );
  }

  if (prod && pushDriver === 'console') {
    warnings.push(
      'PUSH_DRIVER=console: التذكيرات تُطبع في اللوق ولا تصل لأحد. ' +
      'المستخدم الذي ينسى التوقّع قبل صافرة البداية يفقد الجولة كاملة.'
    );
  }

  // الحدّ الداخلي أقل من حدّ الاشتراك = مزامنة تتوقف عند رقم لا
  // علاقة له بما تدفع. وقع هذا فعلاً: بقي على 100 (خطة مجانية)
  // بعد الترقية إلى Pro، فتوقفت المزامنة يوماً كاملاً برسالة
  // توحي بأن المزوّد رفض بينما هو لم يُسأل.
  if (prod && !process.env.FOOTBALL_DAILY_LIMIT && !useSamples) {
    warnings.push(
      'FOOTBALL_DAILY_LIMIT غير مضبوط — سيُستعمل 100 (حد الخطة المجانية). ' +
      'إن كان اشتراكك أعلى فاضبطه، وإلا توقفت المزامنة عند 100 طلب.'
    );
  }

  if (prod && !process.env.ALERT_EMAIL) {
    warnings.push(
      'ALERT_EMAIL غير مضبوط: لن يصلك تنبيه قبل انتهاء اشتراك مزوّد البيانات ' +
      'ولا عند اقتراب نفاد الحصة. انتهاء الاشتراك عطل صامت — الموقع يعمل ' +
      'والبيانات تتجمّد.'
    );
  }

  if (prod && !process.env.CORS_ORIGINS) {
    warnings.push(
      'CORS_ORIGINS غير مضبوط — الـ API مفتوح لأي أصل. اضبطه بنطاقاتك ' +
      'إن كانت لوحة التحكم تعمل على نطاق منفصل.'
    );
  }

  if (prod && !process.env.TRUST_PROXY) {
    warnings.push(
      'TRUST_PROXY غير مضبوط. خلف بروكسي أو موازن أحمال ستبدو كل الطلبات ' +
      'قادمة من عنوان واحد، فينهار حد سبام نموذج التواصل.'
    );
  }

  if (prod && !process.env.UPLOADS_DIR) {
    warnings.push(
      'UPLOADS_DIR غير مضبوط: الصور تُحفظ داخل مجلد المشروع. على منصات ' +
      'القرص المؤقت تختفي صور المستخدمين مع كل نشر — وجّهه لقرص دائم.'
    );
  }

  return { errors, warnings };
}

/** تُستدعى قبل app.listen. ترمي لو كان الإعداد غير صالح. */
function assertValid() {
  const { errors, warnings } = check();

  for (const w of warnings) logger.warn('[config]', w);

  if (errors.length) {
    logger.error('[config] الإعداد غير صالح — لن يبدأ السيرفر:');
    errors.forEach((e, i) => logger.error(`  ${i + 1}. ${e}`));
    // رمز خروج غير صفري كي تعرف أدوات النشر (systemd، Docker) أن
    // الإقلاع فشل فلا تبقي حاوية ميتة تبدو حية.
    process.exit(1);
  }

  logger.info(`[config] البيئة: ${process.env.NODE_ENV || 'development'}`);
}

module.exports = { assertValid, check, isProduction };
