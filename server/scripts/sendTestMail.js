// sendTestMail — هل إعداد البريد يعمل فعلاً؟
//
// أخطاء البريد كلها من نوع واحد: تبدو ناجحة عندك وتفشل عند
// المستخدم. النطاق غير موثّق، المفتاح لبيئة أخرى، حساب Mailgun
// أوروبي على نطاق أمريكي — لا شيء من ذلك يظهر حتى ينسى أحدهم
// كلمة سره. هذا السكربت يجعل الفشل يحدث الآن، وأنت تنظر.
//
//   node scripts/sendTestMail.js you@example.com
//
// يستعمل نفس mailer الذي تستعمله الاستعادة، فما ينجح هنا ينجح هناك.
require('dotenv').config();

const { sendMail } = require('../src/services/mailer');
const { testMail } = require('../src/services/mailTemplates');

const to = process.argv[2];

if (!to) {
  console.error('\nالاستخدام: node scripts/sendTestMail.js <بريدك>\n');
  process.exit(1);
}

const driver = process.env.MAIL_DRIVER || 'console';

(async () => {
  console.log(`\nالـ driver: ${driver}` + (driver === 'console'
    ? '  ← يطبع فقط ولا يرسل. اضبط MAIL_DRIVER لاختبار الإرسال الحقيقي.'
    : `\nمن: ${process.env.MAIL_FROM}\nإلى: ${to}\n`));

  try {
    await sendMail({ to, ...testMail() });
    console.log('\nتم الإرسال بلا خطأ.');
    if (driver !== 'console') {
      // "قبِلها المزوّد" ليست "وصلت". الرفض بعد القبول يظهر في
      // لوحة المزوّد فقط، والوصول للبريد الوارد يحتاج عيناً بشرية.
      console.log('افحص بريدك (ومجلد السبام). إن لم تصل خلال دقائق، راجع سجل المزوّد.\n');
    }
  } catch (err) {
    console.error(`\nفشل الإرسال: ${err.message}\n`);
    process.exit(1);
  }
})();
