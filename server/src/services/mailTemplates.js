// mailTemplates — نص الرسائل ومظهرها، في مكان واحد.
//
// لماذا ملف مستقل عن mailer؟ لأنهما يتغيّران لسببين مختلفين:
// mailer يتغيّر حين نبدّل المزوّد، وهذا الملف يتغيّر حين نبدّل
// الصياغة أو الهوية. كل دالة هنا ترجع { subject, text, html }
// جاهزة لتمريرها إلى sendMail كما هي.
//
// قواعد HTML البريد تختلف عن الويب: لا ملفات CSS خارجية ولا
// خطوط محمّلة ولا flex/grid موثوقة. لذلك كل شيء inline، والتخطيط
// بجداول، والخطوط عائلات نظام. الوضع الداكن هو الهوية الوحيدة
// (لا ثيم فاتح)، فنكتب الألوان صراحة بدل الاعتماد على العميل.

const APP_NAME = 'ملك التوقعات';

// نسخة من tokens الهوية — مكرّرة هنا عمداً: قوالب البريد لا تستطيع
// قراءة theme.css، وربطها بملف CSS يوهم بمصدر واحد غير موجود.
const C = {
  bg: '#0A0A0A',
  surface: '#161616',
  text: '#F5F5F5',
  muted: '#A1A1A1',
  faint: '#6B6B6B',
};

// نص المعاينة الذي تعرضه العملاء بجانب العنوان. مخفي في الجسم.
function preheader(text) {
  return `<div style="display:none;max-height:0;overflow:hidden;opacity:0">${text}</div>`;
}

/** الإطار المشترك: خلفية، بطاقة، تذييل. */
function layout({ preview, body }) {
  return `<!doctype html>
<html lang="ar" dir="rtl">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width"></head>
<body style="margin:0;padding:0;background:${C.bg}">
${preheader(preview)}
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:${C.bg};padding:32px 16px">
  <tr><td align="center">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background:${C.surface};border-radius:16px;padding:32px">
      <tr><td style="font-family:'IBM Plex Sans Arabic',-apple-system,'Segoe UI',Tahoma,sans-serif;color:${C.text};font-size:16px;line-height:1.9;text-align:right">
        <div style="font-size:18px;font-weight:700;padding-bottom:20px">${APP_NAME}</div>
        ${body}
      </td></tr>
    </table>
    <div style="font-family:'IBM Plex Sans Arabic',-apple-system,'Segoe UI',Tahoma,sans-serif;color:${C.faint};font-size:12px;padding-top:20px;text-align:center">
      ${APP_NAME}
    </div>
  </td></tr>
</table>
</body></html>`;
}

/**
 * رمز استعادة كلمة السر.
 * الرمز يظهر في العنوان أيضاً: يقرؤه المستخدم من الإشعار دون فتح
 * الرسالة — وهو ما تفعله كل التطبيقات لأنه يقلّل خطوة كاملة.
 */
function resetCode({ code, ttlMinutes }) {
  const text =
    `رمز استعادة كلمة السر: ${code}\n` +
    `صالح لمدة ${ttlMinutes} دقائق.\n` +
    `إن لم تطلب الاستعادة تجاهل هذه الرسالة — لم يتغيّر شيء في حسابك.`;

  const body = `
        <div style="padding-bottom:8px">رمز استعادة كلمة السر:</div>
        <div style="font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:34px;letter-spacing:8px;font-weight:700;color:${C.text};direction:ltr;text-align:center;padding:16px 0">${code}</div>
        <div style="color:${C.muted};font-size:14px">صالح لمدة ${ttlMinutes} دقائق.</div>
        <div style="color:${C.muted};font-size:14px;padding-top:12px">إن لم تطلب الاستعادة تجاهل هذه الرسالة — لم يتغيّر شيء في حسابك.</div>`;

  return {
    subject: `${code} رمز استعادة كلمة السر — ${APP_NAME}`,
    text,
    html: layout({ preview: `رمزك صالح لمدة ${ttlMinutes} دقائق`, body }),
  };
}

/** رسالة تجربة — يستعملها scripts/sendTestMail.js للتحقق من الإعداد. */
/**
 * تنبيه إداري: الاشتراك أو الحصة.
 *
 * لا يذهب لمستخدم بل لمالك الموقع، ولذلك لغته مباشرة بلا ترحيب:
 * من يقرأ هذه الرسالة يريد أن يعرف في ثانية ماذا ينتهي ومتى وماذا
 * يفعل — لا أن يُشكر على استخدامه التطبيق.
 */
function providerAlert({ title, lines, action }) {
  const body = `
    <h1 style="margin:0 0 14px;font-size:19px">${title}</h1>
    ${lines.map((l) => `<p style="margin:0 0 8px">${l}</p>`).join('')}
    ${action ? `<p style="margin:18px 0 0"><strong>${action}</strong></p>` : ''}
  `;
  const text = [title, '', ...lines, '', action || ''].join('\n');
  return { html: layout({ preview: title, body }), text };
}

function testMail() {
  const text = `إعداد البريد يعمل. أُرسلت هذه الرسالة من سيرفر ${APP_NAME} للتحقق فقط.`;
  return {
    subject: `رسالة تجربة — ${APP_NAME}`,
    text,
    html: layout({
      preview: 'إعداد البريد يعمل',
      body: `<div>${text}</div>`,
    }),
  };
}

module.exports = { resetCode, testMail, providerAlert, APP_NAME };
