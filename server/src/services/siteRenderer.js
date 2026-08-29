// siteRenderer — بناء صفحات الموقع العام كنص HTML.
//
// لماذا يُصنع الموقع في السيرفر بدل صفحة ثابتة تجلب المحتوى
// بـ JavaScript؟
//
// سياسة الخصوصية شرط في مراجعة App Store، والمراجع يفتح الرابط
// وقد يقرأه آلياً. صفحة تصل فارغة ثم تملأ نفسها بعد نداء شبكة
// تظهر لأدوات القراءة الآلية — وللزائر على شبكة بطيئة — بلا
// محتوى. الشروط والخصوصية وثائق قانونية: يجب أن تصل مكتوبة في
// أول بايت، لا أن يعتمد ظهورها على نجاح طلب ثانٍ.
//
// ولماذا بلا محرك قوالب (ejs/pug)؟ خمس صفحات لا تبرر تبعية جديدة
// وطبقة تعلّم. دوال تعيد نصاً تكفي، والهروب من HTML صريح في
// esc() بدل أن يكون سلوكاً ضمنياً في محرك قد نظنه يفعله.

const { render: renderMarkdown } = require('../utils/safeMarkdown');

// الهروب من HTML لكل قيمة تدخل الصفحة.
//
// كل نص هنا مصدره قاعدة البيانات (أي: لوحة التحكم)، ولا نص منها
// موثوق بحكم مصدره. لو أفلتنا اسم الموقع بلا هروب لصار حقل نص في
// اللوحة ثغرة XSS على كل زائر.
function esc(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// روابط التواصل: نسمح بـ http/https فقط.
//
// href غير مفلتر ثغرة قائمة بذاتها حتى مع هروب HTML الكامل:
// javascript:alert(1) نص بريء الشكل لكنه ينفَّذ عند الضغط.
function safeUrl(url) {
  const value = String(url ?? '').trim();
  if (!value) return null;
  try {
    const parsed = new URL(value);
    return ['http:', 'https:'].includes(parsed.protocol) ? value : null;
  } catch {
    return null; // ليس رابطاً مكتمل الشكل
  }
}

function safeMailto(email) {
  const value = String(email ?? '').trim();
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value) ? value : null;
}

// شعار العلامة. نفس هندسة ملف الهوية (مربع 512).
// `carve` لون الحفر ويجب أن يساوي لون السطح خلف الدرع — لا لون
// ثالث داخل العلامة أبداً. و`full` يحمل قاعدة "تحت 64 بكسل تُحذف
// الدرجات": الشرط في مكان واحد فلا يُنسى في استدعاء.
function brandMark(size = 28, carve = '#101e17') {
  const full = size >= 64;
  const steps = full
    ? `<g fill="${carve}">
         <rect x="140" y="300" width="58" height="104" rx="10"/>
         <rect x="227" y="250" width="58" height="154" rx="10"/>
         <rect x="314" y="284" width="58" height="120" rx="10"/>
       </g>`
    : '';
  return `<svg width="${size}" height="${size}" viewBox="0 0 512 512" fill="none" aria-hidden="true">
    <path d="M256 40l192 68v168c0 80-88 152-192 192C152 428 64 356 64 276V108z" fill="#F2C14E"/>
    ${steps}
    <path d="M212 236v-40l22 14 22-24 22 24 22-14v40z" fill="${carve}"/>
  </svg>`;
}

const SOCIAL = [
  { key: 'x', label: 'X', icon: 'M18.9 2H22l-7.2 8.3L23 22h-6.6l-5.2-6.8L5.3 22H2.2l7.7-8.8L1.7 2h6.8l4.7 6.2zm-1.1 18h1.8L7.3 3.8H5.4z' },
  { key: 'instagram', label: 'إنستقرام', icon: 'M12 2.2c3.2 0 3.6 0 4.8.07 3.3.15 4.8 1.7 5 5 .06 1.2.07 1.6.07 4.7s0 3.6-.07 4.8c-.15 3.2-1.7 4.8-5 5-1.2.06-1.6.07-4.8.07s-3.6 0-4.8-.07c-3.3-.15-4.8-1.7-5-5C2.2 15.6 2.2 15.2 2.2 12s0-3.6.07-4.8c.15-3.3 1.7-4.8 5-5C8.4 2.2 8.8 2.2 12 2.2zm0 3.4a6.4 6.4 0 100 12.8 6.4 6.4 0 000-12.8zm0 10.5a4.1 4.1 0 110-8.2 4.1 4.1 0 010 8.2zm6.6-10.8a1.5 1.5 0 11-3 0 1.5 1.5 0 013 0z' },
  { key: 'tiktok', label: 'تيك توك', icon: 'M16.6 5.8a4.8 4.8 0 01-1-2.8h-3.2v12.8a2.6 2.6 0 11-2.6-2.6c.27 0 .53.04.78.12V9.9a5.9 5.9 0 00-.78-.05 5.9 5.9 0 105.9 5.9V9.2a8 8 0 004.7 1.5V7.4a4.8 4.8 0 01-3.8-1.6z' },
  { key: 'youtube', label: 'يوتيوب', icon: 'M21.6 7.2a2.5 2.5 0 00-1.8-1.8C18.2 5 12 5 12 5s-6.2 0-7.8.4A2.5 2.5 0 002.4 7.2 26 26 0 002 12a26 26 0 00.4 4.8 2.5 2.5 0 001.8 1.8C5.8 19 12 19 12 19s6.2 0 7.8-.4a2.5 2.5 0 001.8-1.8A26 26 0 0022 12a26 26 0 00-.4-4.8zM10 15V9l5.2 3z' },
  { key: 'snapchat', label: 'سناب شات', icon: 'M12 2c2.8 0 4.7 2 4.8 4.8v1.9c.5.2 1-.3 1.5-.3.4 0 .9.3.9.8 0 .7-1.2 1-1.8 1.3-.3.2-.5.3-.4.7.4 1.4 2 2.9 3.3 3.2.4.1.6.3.6.6 0 .7-1.6 1-2.2 1.1-.2.3-.1 1-.5 1.1-.4.1-1.1-.1-1.9-.1-1.1 0-1.6.2-2.4.8-.7.5-1.3.9-2.4.9s-1.7-.4-2.4-.9c-.8-.6-1.3-.8-2.4-.8-.8 0-1.5.2-1.9.1-.4-.1-.3-.8-.5-1.1-.6-.1-2.2-.4-2.2-1.1 0-.3.2-.5.6-.6 1.3-.3 2.9-1.8 3.3-3.2.1-.4-.1-.5-.4-.7C4.4 10.2 3.2 9.9 3.2 9.2c0-.5.5-.8.9-.8.5 0 1 .5 1.5.3V6.8C5.7 4 7.6 2 10.4 2z' },
  { key: 'linkedin', label: 'لينكدإن', icon: 'M4.98 3.5a2.5 2.5 0 11-.02 5 2.5 2.5 0 01.02-5zM3 9h4v12H3zM10 9h3.8v1.7h.05c.53-1 1.83-2.05 3.77-2.05 4.03 0 4.78 2.65 4.78 6.1V21h-4v-5.4c0-1.3 0-2.96-1.8-2.96s-2.08 1.4-2.08 2.86V21h-4z' },
];

function socialLinks(settings) {
  const items = SOCIAL.map(({ key, label, icon }) => {
    const url = safeUrl(settings?.social?.[key]);
    if (!url) return ''; // حساب غير مضبوط = لا نعرض أيقونة ميتة
    return `<a href="${esc(url)}" title="${esc(label)}" aria-label="${esc(label)}"
               target="_blank" rel="noopener noreferrer">
      <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="${icon}"/></svg>
    </a>`;
  }).filter(Boolean);

  return items.length ? `<div class="social">${items.join('')}</div>` : '';
}

// القائمة: المباريات ثانياً مباشرة بعد الرئيسية.
//
// هي المحتوى الحيّ الوحيد في الموقع، وما يعود إليه الزائر يومياً.
// الصفحات القانونية تبقى في التذييل حيث يبحث عنها من يبحث — ووجودها
// في الشريط العلوي كان يزاحم ما يُستعمل فعلاً بما يُفتح مرة واحدة.
const NAV = [
  { href: '/', label: 'المباريات' },
  { href: '/standings', label: 'الترتيب' },
  { href: '/about', label: 'حول الموقع' },
  { href: '/contact', label: 'اتصل بنا' },
];

/** التخطيط المشترك: ترويسة وتذييل حول أي محتوى. */
function layout({ title, description, body, settings, active, canonicalPath }) {
  const siteName = settings?.siteName || 'ملك التوقعات';
  const fullTitle = title && title !== siteName ? `${title} — ${siteName}` : siteName;
  const contact = safeMailto(settings?.contactEmail);
  const support = safeMailto(settings?.supportEmail);
  const appStore = safeUrl(settings?.appStoreUrl);
  const play = safeUrl(settings?.googlePlayUrl);
  const year = new Date().getFullYear();

  return `<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(fullTitle)}</title>
<meta name="description" content="${esc(description || settings?.description || '')}">
<meta name="theme-color" content="#080f0c">
<meta property="og:title" content="${esc(fullTitle)}">
<meta property="og:description" content="${esc(description || settings?.description || '')}">
<meta property="og:type" content="website">
<meta property="og:locale" content="ar_SA">
${canonicalPath ? `<link rel="canonical" href="${esc(canonicalPath)}">` : ''}
<link rel="icon" href="/assets/favicon.svg" type="image/svg+xml">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Readex+Pro:wght@400;600;700&family=IBM+Plex+Sans+Arabic:wght@400;500;600&display=swap">
<link rel="stylesheet" href="/assets/site.css">
</head>
<body>

<header class="topbar">
  <div class="wrap">
    <a class="brand" href="/">${brandMark(28, '#080f0c')}<span>${esc(siteName)}</span></a>
    <nav class="topnav">
      ${NAV.map((n) =>
        `<a href="${n.href}"${n.href === active ? ' class="active"' : ''}>${esc(n.label)}</a>`
      ).join('')}
    </nav>
  </div>
</header>

<main>${body}</main>

<footer class="footer">
  <div class="wrap">
    <div class="footer-top">
      <div class="about">
        <a class="brand" href="/">${brandMark(26, '#080f0c')}<span>${esc(siteName)}</span></a>
        <p>${esc(settings?.description || settings?.tagline || '')}</p>
        ${socialLinks(settings)}
      </div>

      <div class="foot-links">
        <div class="foot-col">
          <h4>الموقع</h4>
          <a href="/">الرئيسية</a>
          <a href="/about">حول الموقع</a>
          <a href="/contact">اتصل بنا</a>
        </div>
        <div class="foot-col">
          <h4>حسابك</h4>
          <a href="/login">تسجيل الدخول</a>
          <a href="/register">حساب جديد</a>
          <a href="/forgot">استعادة كلمة المرور</a>
        </div>
        <div class="foot-col">
          <h4>قانوني</h4>
          <a href="/privacy">سياسة الخصوصية</a>
          <a href="/terms">شروط الاستخدام</a>
        </div>
        <div class="foot-col">
          <h4>تواصل</h4>
          ${contact ? `<a href="mailto:${esc(contact)}" dir="ltr">${esc(contact)}</a>` : ''}
          ${support && support !== contact
            ? `<a href="mailto:${esc(support)}" dir="ltr">${esc(support)}</a>`
            : ''}
          ${!contact && !support ? '<span>لم يُضبط بريد بعد</span>' : ''}
        </div>
        ${appStore || play ? `<div class="foot-col">
          <h4>التطبيق</h4>
          ${appStore ? `<a href="${esc(appStore)}" target="_blank" rel="noopener noreferrer">App Store</a>` : ''}
          ${play ? `<a href="${esc(play)}" target="_blank" rel="noopener noreferrer">Google Play</a>` : ''}
        </div>` : ''}
      </div>
    </div>

    <div class="footer-bottom">
      <span>© ${year} ${esc(siteName)}. جميع الحقوق محفوظة.</span>
      <span>صُنع في السعودية</span>
    </div>
  </div>
</footer>

</body>
</html>`;
}

// مزايا المنتج ورتبه.
//
// هذه نصوص تسويقية ثابتة في القالب لا في القاعدة، بعكس صفحات
// الخصوصية والشروط وحول الموقع. السبب أنها مقترنة ببنية بصرية
// (بطاقة لكل ميزة، شبكة للرتب) لا يعبّر عنها نص Markdown حر —
// ولأنها تصف ما يفعله التطبيق فعلاً، فتغييرها يرافق تغييره لا
// تحرير نص. لو احتاجها المالك قابلة للتحرير فالخطوة الواضحة
// جدول مستقل بحقول (عنوان، وصف، تصنيف) لا صفحة Markdown.
// المزايا: ما يفعله التطبيق اليوم، لا ما رُسم له.
//
// كانت هذه القائمة تعرض ستاً ولا يعمل منها إلا واحدة: مستشار
// التوقّع والمضاعِف ودرع السلسلة وتوقّع الدقيقة والتحدي ١ ضد ١
// كلها بلا خادم يحسبها. الوعد بما لا يوجد ليس تسويقاً متفائلاً
// بل سبب لمراجعة App Store أن ترفض ("لقطات ووصف لا يطابقان
// التطبيق")، وسبب أوثق لأن يشعر أول مستخدم أنه خُدع.
//
// حين تُبنى أي منها، تعود إلى هنا في سطر واحد.
// الصفحة الرئيسية صارت المباريات نفسها (routes/pages.js).
//
// كانت صفحة تعريفية: عنوان كبير وشعار ووصف وست "مزايا" وسلّم رتب —
// كتيّب يُقرأ مرة واحدة، بينما الزائر يعود يومياً لسؤال واحد:
// "ماذا يُلعب اليوم؟". صار الجواب هو الصفحة، والتعريف في /about
// لمن يريده. (renderHome و FEATURES و RANKS في تاريخ git.)


/** صفحة محتوى (الخصوصية، الشروط، حول الموقع). */
function renderPage(page, settings) {
  const updated = page.updated_at
    ? new Date(page.updated_at).toLocaleDateString('ar-SA', {
        year: 'numeric', month: 'long', day: 'numeric',
      })
    : null;

  const body = `
<div class="page">
  <div class="wrap">
    <h1>${esc(page.title)}</h1>
    ${updated ? `<p class="updated">آخر تحديث: ${esc(updated)}</p>` : ''}
    <div class="prose">${renderMarkdown(page.body)}</div>
  </div>
</div>`;

  return layout({
    title: page.title,
    body,
    settings,
    active: `/${page.slug}`,
  });
}

/** صفحة اتصل بنا: نموذج + بيانات التواصل.
 *
 * النموذج HTML خالص يرسل POST عادياً — لا JavaScript. الصفحة يجب
 * أن تعمل حتى لو تعطّل السكربت أو حجبه المتصفح، فقناة التواصل
 * آخر ما يجوز أن ينكسر.
 */
function renderContact(page, settings, { sent, error, values } = {}) {
  const contact = safeMailto(settings?.contactEmail);
  const support = safeMailto(settings?.supportEmail);
  const v = values || {};

  const body = `
<div class="page">
  <div class="wrap">
    <h1>${esc(page?.title || 'اتصل بنا')}</h1>
    ${page?.body ? `<div class="prose">${renderMarkdown(page.body)}</div>` : ''}

    <div class="contact-grid">
      <div class="card">
        ${sent ? '<div class="note ok">وصلتنا رسالتك. سنرد عليك في أقرب وقت.</div>' : ''}
        ${error ? `<div class="note bad">${esc(error)}</div>` : ''}
        <form method="post" action="/contact">
          <div class="field">
            <label for="name">الاسم</label>
            <input id="name" name="name" maxlength="80" value="${esc(v.name)}" required>
          </div>
          <div class="field">
            <label for="email">البريد الإلكتروني</label>
            <input id="email" name="email" type="email" dir="ltr" maxlength="160"
                   value="${esc(v.email)}" required>
          </div>
          <div class="field">
            <label for="subject">الموضوع</label>
            <input id="subject" name="subject" maxlength="140" value="${esc(v.subject)}">
          </div>
          <div class="field">
            <label for="message">الرسالة</label>
            <textarea id="message" name="message" maxlength="4000" required>${esc(v.message)}</textarea>
          </div>
          <button class="btn btn-primary" type="submit">إرسال</button>
        </form>
      </div>

      <div class="card contact-side">
        <h3 style="margin-bottom:8px">قنوات أخرى</h3>
        ${contact ? `<div class="row"><span class="k">البريد</span>
          <a href="mailto:${esc(contact)}" dir="ltr">${esc(contact)}</a></div>` : ''}
        ${support && support !== contact ? `<div class="row"><span class="k">الدعم</span>
          <a href="mailto:${esc(support)}" dir="ltr">${esc(support)}</a></div>` : ''}
        ${!contact && !support ? '<div class="row"><span class="k">البريد</span><span>لم يُضبط بعد</span></div>' : ''}
        ${socialLinks(settings)}
      </div>
    </div>
  </div>
</div>`;

  return layout({ title: page?.title || 'اتصل بنا', body, settings, active: '/contact' });
}

/**
 * استعادة كلمة المرور — الخطوة الأولى: البريد.
 *
 * لماذا على الموقع أصلاً والتطبيق فيه نفس الشاشة؟ لأن من فقد
 * كلمته قد يكون فقد الوصول للتطبيق نفسه: حذفه، أو بدّل هاتفه، أو
 * خرج من حسابه ولا يتذكر شيئاً. رابط يفتح في أي متصفح هو الطريق
 * الوحيد الذي لا يشترط شيئاً مسبقاً.
 */
function renderForgot(settings, { error, values } = {}) {
  const v = values || {};
  const body = `
<div class="page">
  <div class="wrap auth-wrap">
    <div class="card">
      <h1>استعادة كلمة المرور</h1>
      <p class="section-sub" style="margin:10px 0 22px">
        اكتب بريدك المسجّل ونرسل لك رمزاً من ستة أرقام صالحاً لعشر دقائق.
      </p>
      ${error ? `<div class="note bad">${esc(error)}</div>` : ''}
      <form method="post" action="/forgot">
        <div class="field">
          <label for="email">البريد الإلكتروني</label>
          <input id="email" name="email" type="email" dir="ltr" maxlength="160"
                 autocomplete="email" value="${esc(v.email)}" required>
        </div>
        <button class="btn btn-primary" type="submit">أرسل الرمز</button>
      </form>
      <p class="section-sub" style="margin-top:18px">
        وصلك رمز من قبل؟ <a href="/reset">أدخله هنا</a>.
      </p>
    </div>
  </div>
</div>`;
  return layout({ title: 'استعادة كلمة المرور', body, settings, active: null });
}

/**
 * الخطوة الثانية: الرمز وكلمة السر الجديدة.
 *
 * البريد حقل مستقل لا قيمة مخفية مُمرّرة من الخطوة السابقة: من
 * يفتح بريده على جهاز آخر ويكمل من هناك يجب أن يستطيع ذلك. وأن
 * يكتبه ثانية أهون من أن يعلق في صفحة لا تقبل إلا مساراً واحداً.
 */
function renderReset(settings, { error, values, sent } = {}) {
  const v = values || {};
  const body = `
<div class="page">
  <div class="wrap auth-wrap">
    <div class="card">
      <h1>كلمة مرور جديدة</h1>
      ${sent ? `<div class="note ok">
        إن كان البريد مسجّلاً عندنا فالرمز في طريقه إليه الآن. تحقق من صندوقك
        (ومجلد المهملات أحياناً).
      </div>` : ''}
      ${error ? `<div class="note bad">${esc(error)}</div>` : ''}
      <form method="post" action="/reset">
        <div class="field">
          <label for="email">البريد الإلكتروني</label>
          <input id="email" name="email" type="email" dir="ltr" maxlength="160"
                 autocomplete="email" value="${esc(v.email)}" required>
        </div>
        <div class="field">
          <label for="code">الرمز</label>
          <input id="code" name="code" dir="ltr" inputmode="numeric" pattern="[0-9]{6}"
                 maxlength="6" autocomplete="one-time-code" placeholder="000000" required>
        </div>
        <div class="field">
          <label for="password">كلمة المرور الجديدة</label>
          <input id="password" name="password" type="password" minlength="8"
                 maxlength="200" autocomplete="new-password" required>
        </div>
        <button class="btn btn-primary" type="submit">حفظ كلمة المرور</button>
      </form>
      <p class="section-sub" style="margin-top:18px">
        لم يصلك الرمز أو انتهت صلاحيته؟ <a href="/forgot">اطلب رمزاً جديداً</a>.
      </p>
    </div>
  </div>
</div>`;
  return layout({ title: 'كلمة مرور جديدة', body, settings, active: null });
}

/** بعد النجاح — الوجهة هي التطبيق لا الموقع، والصفحة تقول ذلك صراحة. */
function renderResetDone(settings) {
  const body = `
<div class="page">
  <div class="wrap auth-wrap">
    <div class="card" style="text-align:center">
      <h1>تم تغيير كلمة المرور</h1>
      <p class="section-sub" style="margin:12px 0 24px">
        افتح التطبيق وسجّل الدخول بكلمتك الجديدة.
      </p>
      <a class="btn btn-primary" href="/">العودة للرئيسية</a>
    </div>
  </div>
</div>`;
  return layout({ title: 'تم تغيير كلمة المرور', body, settings, active: null });
}

/** حقل CSRF المخفي — يُوضع في كل نموذج يغيّر شيئاً. */
function csrfField(csrf) {
  return `<input type="hidden" name="_csrf" value="${esc(csrf)}">`;
}

function renderLogin(settings, { error, values } = {}) {
  const v = values || {};
  const body = `
<div class="page">
  <div class="wrap auth-wrap">
    <div class="card">
      <h1>تسجيل الدخول</h1>
      <p class="section-sub" style="margin:10px 0 22px">
        ادخل لإدارة حسابك. التوقّع والمنافسة في التطبيق.
      </p>
      ${error ? `<div class="note bad">${esc(error)}</div>` : ''}
      <form method="post" action="/login">
        <div class="field">
          <label for="email">البريد الإلكتروني</label>
          <input id="email" name="email" type="email" dir="ltr" maxlength="160"
                 autocomplete="email" value="${esc(v.email)}" required>
        </div>
        <div class="field">
          <label for="password">كلمة المرور</label>
          <input id="password" name="password" type="password" maxlength="200"
                 autocomplete="current-password" required>
        </div>
        <button class="btn btn-primary" type="submit">دخول</button>
      </form>
      <p class="section-sub" style="margin-top:18px">
        <a href="/forgot">نسيت كلمة المرور؟</a> · ما عندك حساب؟
        <a href="/register">سجّل الآن</a>
      </p>
    </div>
  </div>
</div>`;
  return layout({ title: 'تسجيل الدخول', body, settings, active: null });
}

function renderRegister(settings, { error, values } = {}) {
  const v = values || {};
  const body = `
<div class="page">
  <div class="wrap auth-wrap">
    <div class="card">
      <h1>حساب جديد</h1>
      <p class="section-sub" style="margin:10px 0 22px">
        أنشئ حسابك هنا ثم حمّل التطبيق وابدأ التوقّع بنفس البيانات.
      </p>
      ${error ? `<div class="note bad">${esc(error)}</div>` : ''}
      <form method="post" action="/register">
        <div class="field">
          <label for="name">الاسم الظاهر</label>
          <input id="name" name="name" maxlength="50" value="${esc(v.name)}" required>
        </div>
        <div class="field">
          <label for="email">البريد الإلكتروني</label>
          <input id="email" name="email" type="email" dir="ltr" maxlength="160"
                 autocomplete="email" value="${esc(v.email)}" required>
        </div>
        <div class="field">
          <label for="password">كلمة المرور</label>
          <input id="password" name="password" type="password" minlength="8"
                 maxlength="200" autocomplete="new-password" required>
        </div>
        <button class="btn btn-primary" type="submit">إنشاء الحساب</button>
      </form>
      <p class="section-sub" style="margin-top:18px">
        عندك حساب؟ <a href="/login">سجّل الدخول</a>
      </p>
    </div>
  </div>
</div>`;
  return layout({ title: 'حساب جديد', body, settings, active: null });
}

/**
 * حسابي — ما يملكه المستخدم على الويب.
 *
 * لا توقّع هنا ولا جداول مباريات: تلك تجربة التطبيق، ونسخة ويب
 * منها تعني واجهتين تتباعدان. الموقع يجيب عن "ماذا في حسابي وكيف
 * أتحكم به" — وهو ما يحتاجه من فقد هاتفه أو أراد حذف حسابه.
 */
function renderAccount(settings, { user, stats, notice, error, csrf }) {
  const rank = stats?.rank ? `${stats.rank} من ${stats.totalPlayers}` : '—';
  const body = `
<div class="page">
  <div class="wrap auth-wrap" style="max-width:560px">
    ${notice ? `<div class="note ok">${esc(notice)}</div>` : ''}
    ${error ? `<div class="note bad">${esc(error)}</div>` : ''}

    <div class="card">
      <h1>${esc(user.display_name || 'حسابي')}</h1>
      <div class="row"><span class="k">البريد</span><span dir="ltr">${esc(user.email)}</span></div>
      <div class="row"><span class="k">النقاط</span><span>${esc(String(stats?.points ?? 0))}</span></div>
      <div class="row"><span class="k">المركز</span><span>${esc(rank)}</span></div>
      <div class="row"><span class="k">التوقعات</span><span>${esc(String(stats?.total ?? 0))}</span></div>
    </div>

    <div class="card" style="margin-top:16px">
      <h3>تغيير كلمة المرور</h3>
      <form method="post" action="/account/password">
        ${csrfField(csrf)}
        <div class="field">
          <label for="current">كلمة المرور الحالية</label>
          <input id="current" name="current" type="password" maxlength="200"
                 autocomplete="current-password" required>
        </div>
        <div class="field">
          <label for="next">الجديدة</label>
          <input id="next" name="next" type="password" minlength="8" maxlength="200"
                 autocomplete="new-password" required>
        </div>
        <button class="btn btn-primary" type="submit">حفظ</button>
      </form>
    </div>

    <div class="card" style="margin-top:16px">
      <h3>حذف الحساب</h3>
      <p class="section-sub" style="margin:8px 0 16px">
        يُحذف حسابك وتوقعاتك ونقاطك نهائياً ولا يمكن التراجع. مجموعاتك
        التي تملكها تنتقل لأقدم عضو فيها.
      </p>
      <form method="post" action="/account/delete"
            onsubmit="return confirm('حذف نهائي بلا تراجع. متأكد؟')">
        ${csrfField(csrf)}
        <div class="field">
          <label for="delpass">أكّد بكلمة المرور</label>
          <input id="delpass" name="password" type="password" maxlength="200"
                 autocomplete="current-password" required>
        </div>
        <button class="btn btn-danger" type="submit">حذف حسابي نهائياً</button>
      </form>
    </div>

    <form method="post" action="/logout" style="margin-top:16px">
      ${csrfField(csrf)}
      <button class="btn" type="submit">تسجيل الخروج</button>
    </form>
  </div>
</div>`;
  return layout({ title: 'حسابي', body, settings, active: null });
}

// ─────────────────────── المباريات ───────────────────────

const WEEKDAYS = ['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
const MONTHS = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

/** اليوم بتوقيت الرياض بصيغة YYYY-MM-DD. */
function riyadhToday() {
  return new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Riyadh' });
}

/** يوم بإزاحة عن يوم معطى، بحساب تقويمي لا بجمع ثوانٍ. */
function shiftDay(day, delta) {
  const d = new Date(`${day}T12:00:00Z`); // منتصف النهار: بعيد عن حدود التوقيت الصيفي
  d.setUTCDate(d.getUTCDate() + delta);
  return d.toISOString().slice(0, 10);
}

/** "السبت 29 أغسطس" — الأرقام غربية دائماً، كما في التطبيق. */
function arabicDate(day, { withWeekday = true } = {}) {
  const [y, m, d] = day.split('-').map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  const parts = [];
  if (withWeekday) parts.push(WEEKDAYS[date.getUTCDay()]);
  parts.push(String(d), MONTHS[m - 1]);
  return parts.join(' ');
}

/** وقت الانطلاق بتوقيت الرياض: "9:00 م". */
function kickoffTime(kickoffAt) {
  return new Date(kickoffAt).toLocaleTimeString('ar-SA-u-nu-latn', {
    timeZone: 'Asia/Riyadh', hour: 'numeric', minute: '2-digit',
  });
}

/**
 * وسط بطاقة المباراة: النتيجة أو الوقت.
 *
 * قبل الانطلاق goals تساوي NULL لا صفراً — وعرض "0 - 0" لمباراة لم
 * تبدأ يجعل القارئ يظنها انتهت بالتعادل. هذا فخ وقعنا فيه من قبل
 * في التطبيق، والحارس هنا هو نفسه: الحالة تحكم لا القيمة.
 */
function fixtureCenter(f) {
  if (f.status === 'live') {
    return `<div class="fx-score num live">${esc(String(f.goals_home ?? 0))} - ${esc(String(f.goals_away ?? 0))}</div>
            <div class="fx-min">${f.elapsed ? esc(String(f.elapsed)) + "'" : 'مباشر'}</div>`;
  }
  if (f.status === 'finished') {
    return `<div class="fx-score num">${esc(String(f.goals_home ?? 0))} - ${esc(String(f.goals_away ?? 0))}</div>
            <div class="fx-min">انتهت</div>`;
  }
  return `<div class="fx-time num">${esc(kickoffTime(f.kickoff_at))}</div>
          <div class="fx-min">${esc(f.status === 'postponed' ? 'مؤجلة' : 'لم تبدأ')}</div>`;
}

/** شعار فريق، أو حرفه الأول حين لا شعار. */
function teamBadge(name, logo) {
  if (logo) {
    return `<img class="fx-logo" src="${esc(logo)}" alt="" loading="lazy" width="30" height="30">`;
  }
  return `<span class="fx-logo fx-logo-fallback">${esc((name || '?').trim().charAt(0))}</span>`;
}

/**
 * صف مباراة واحدة.
 *
 * المضيف على اليمين والضيف على اليسار — الترتيب الطبيعي في واجهة
 * RTL، ونفس ما يفعله التطبيق. الاتجاه يأتي من CSS لا من عكس
 * الحقول، فيبقى ترتيب النتيجة "المضيف - الضيف" سليماً.
 */
function fixtureRow(f) {
  return `
<div class="fx" data-status="${esc(f.status)}">
  <div class="fx-side fx-home">
    ${teamBadge(f.home_team_name, f.home_team_logo)}
    <span class="fx-name">${esc(f.home_team_name)}</span>
  </div>
  <div class="fx-center">${fixtureCenter(f)}</div>
  <div class="fx-side fx-away">
    ${teamBadge(f.away_team_name, f.away_team_logo)}
    <span class="fx-name">${esc(f.away_team_name)}</span>
  </div>
</div>`;
}

/** يجمع المباريات في مجموعات حسب الدوري مع حفظ ترتيبها. */
function groupByLeague(fixtures) {
  const groups = [];
  for (const f of fixtures) {
    const last = groups[groups.length - 1];
    if (last && last.id === f.league_id) last.fixtures.push(f);
    else groups.push({ id: f.league_id, name: f.league_name, logo: f.league_logo, fixtures: [f] });
  }
  return groups;
}

/**
 * شرائح الدوريات — مرشّح أفقي.
 *
 * روابط لا أزرار JavaScript: كل ترشيح صفحة بعنوان خاص يمكن حفظه
 * ومشاركته، ويعمل بلا سكربت. وسياسة المحتوى عندنا تمنع السكربت
 * الخارجي أصلاً، وصفحةُ نتائجٍ تحتاج JS لتعرض قائمة تفشل عند أول
 * عطل فيه.
 */
function leagueChips(leagues, { active, href, all = true }) {
  const chip = (id, label) => {
    const on = String(active || '') === String(id);
    return `<a class="chip${on ? ' active' : ''}" href="${esc(href(id))}">${esc(label)}</a>`;
  };
  return `<nav class="chips">
    ${all ? chip('', 'الكل') : ''}
    ${(leagues || []).map((l) => chip(l.id, l.name_ar || l.name || l.name_en)).join('')}
  </nav>`;
}

/**
 * جدول الترتيب.
 *
 * الفورمة (آخر خمس مباريات) حروف ملوّنة لا نص: "WWDLW" يقرؤها من
 * يعرف الاصطلاح وحده، والدوائر الملوّنة يقرؤها الجميع بنظرة.
 */
function renderStandings(settings, { leagues, league, rows, error }) {
  const current = (leagues || []).find((l) => String(l.id) === String(league));
  const formDots = (form) => (form || '').slice(-5).split('').map((c) => {
    const cls = c === 'W' ? 'w' : c === 'L' ? 'l' : 'd';
    const label = c === 'W' ? 'فوز' : c === 'L' ? 'خسارة' : 'تعادل';
    return `<span class="dot ${cls}" title="${label}"></span>`;
  }).join('');

  const body = `
<div class="page">
  <div class="wrap">
    <div class="section-label">الترتيب</div>
    <h1 class="section-title" style="margin-bottom:18px">${esc(current?.name_ar || current?.name_en || 'جدول الترتيب')}</h1>

    ${leagueChips(leagues, {
      active: league,
      href: (id) => `/standings?league=${id}`,
      // لا شريحة "الكل": الجدول يعرض دورياً واحداً بطبيعته، وشريحة
      // تعد بترتيب موحّد لثماني بطولات لا معنى له.
      all: false,
    })}

    ${error ? `<div class="note bad">${esc(error)}</div>` : ''}
    ${!error && (!rows || rows.length === 0) ? `
      <div class="card" style="text-align:center;padding:40px 20px">
        <h3>لا يوجد ترتيب لهذه البطولة</h3>
        <p class="section-sub" style="margin-top:8px">
          البطولات الإقصائية (كدوري الأبطال في أدواره الأولى) قد لا يكون لها جدول.
        </p>
      </div>` : ''}

    ${rows && rows.length ? `
    <div class="table-wrap">
      <table class="tbl">
        <thead>
          <tr>
            <th class="c">#</th><th>الفريق</th>
            <th class="c">لعب</th><th class="c">فاز</th><th class="c">تعادل</th><th class="c">خسر</th>
            <th class="c">له</th><th class="c">عليه</th><th class="c">الفارق</th>
            <th class="c">نقاط</th><th class="c">آخر ٥</th>
          </tr>
        </thead>
        <tbody>
          ${rows.map((r) => `
          <tr>
            <td class="c num rank">${esc(String(r.rank))}</td>
            <td class="team">
              ${teamBadge(r.team_name, r.logo_url)}
              <span class="fx-name">${esc(r.team_name)}</span>
            </td>
            <td class="c num">${esc(String(r.played))}</td>
            <td class="c num">${esc(String(r.win))}</td>
            <td class="c num">${esc(String(r.draw))}</td>
            <td class="c num">${esc(String(r.lose))}</td>
            <td class="c num">${esc(String(r.goals_for))}</td>
            <td class="c num">${esc(String(r.goals_against))}</td>
            <!-- dir="ltr" على الخلية وحدها: "+9" في فقرة عربية
                 يعيد المتصفح ترتيبها إلى "9+" لأن الإشارة محايدة
                 الاتجاه فتلتحق بما حولها. الرقم وحده لا يكفي —
                 السالب يصير "3-" وهو أسوأ لأنه يبدو صحيحاً. -->
            <td class="c num" dir="ltr">${r.goals_diff > 0 ? '+' : ''}${esc(String(r.goals_diff))}</td>
            <td class="c num pts">${esc(String(r.points))}</td>
            <td class="c form">${formDots(r.form)}</td>
          </tr>`).join('')}
        </tbody>
      </table>
    </div>` : ''}
  </div>
</div>`;

  return layout({
    title: `ترتيب ${current?.name_ar || ''}`.trim(),
    description: 'جداول ترتيب الدوريات الكبرى — نقاط، فارق أهداف، وآخر خمس مباريات.',
    body, settings, active: '/standings',
  });
}

function renderMatches(settings, { day, fixtures, days, leagues, league }) {
  const today = riyadhToday();
  const groups = groupByLeague(fixtures);

  // شريط الأيام: نبني المدى كاملاً لا من الأيام التي فيها مباريات
  // فقط — يوم فارغ يجب أن يبقى قابلاً للفتح، وإلا بدا الشريط وكأنه
  // يقفز فوق أيام بلا سبب مفهوم.
  const counts = new Map(days.map((d) => [d.day, d.count]));
  const strip = [];
  for (let i = -3; i <= 3; i += 1) {
    const d = shiftDay(today, i);
    strip.push({
      day: d,
      label: i === 0 ? 'اليوم' : i === 1 ? 'غداً' : i === -1 ? 'أمس' : arabicDate(d, { withWeekday: false }),
      weekday: WEEKDAYS[new Date(`${d}T12:00:00Z`).getUTCDay()],
      count: counts.get(d) || 0,
      active: d === day,
    });
  }

  const body = `
<div class="page">
  <div class="wrap">
    <div class="section-label">المباريات</div>
    <h1 class="section-title" style="margin-bottom:6px">${esc(arabicDate(day))}</h1>
    <p class="section-sub" style="margin-bottom:22px">
      كل الأوقات بتوقيت الرياض. النتائج تُحدَّث أثناء اللعب.
    </p>

    ${leagueChips(leagues, {
      active: league,
      href: (id) => `/?date=${day}${id ? `&league=${id}` : ''}`,
    })}

    <nav class="daystrip">
      ${strip.map((d) => `
        <a class="day${d.active ? ' active' : ''}" href="/?date=${esc(d.day)}${league ? `&amp;league=${esc(String(league))}` : ''}">
          <span class="dw">${esc(d.weekday)}</span>
          <span class="dl">${esc(d.label)}</span>
          <span class="dc num">${d.count ? esc(String(d.count)) : '—'}</span>
        </a>`).join('')}
    </nav>

    ${groups.length === 0 ? `
      <div class="card" style="text-align:center;padding:44px 20px">
        <h3>لا مباريات في هذا اليوم</h3>
        <p class="section-sub" style="margin-top:8px">اختر يوماً آخر من الشريط أعلاه.</p>
      </div>` : groups.map((g) => `
      <section class="lg">
        <header class="lg-head">
          ${g.logo ? `<img src="${esc(g.logo)}" alt="" width="22" height="22" loading="lazy">` : ''}
          <h2>${esc(g.name)}</h2>
          <a class="lg-link" href="/standings?league=${esc(String(g.id))}">الترتيب</a>
          <span class="lg-count num">${esc(String(g.fixtures.length))}</span>
        </header>
        <div class="lg-body">${g.fixtures.map(fixtureRow).join('')}</div>
      </section>`).join('')}
  </div>
</div>`;

  return layout({
    title: `مباريات ${arabicDate(day)}`,
    description: 'مباريات ونتائج دوري روشن ودوري أبطال أوروبا وآسيا والدوريات الأوروبية الكبرى.',
    body, settings, active: '/matches',
  });
}

/** صفحة 404 بنفس هوية الموقع بدل صفحة Express البيضاء. */
function renderNotFound(settings) {
  const body = `
<div class="page">
  <div class="wrap" style="text-align:center;padding:70px 0">
    <h1>الصفحة غير موجودة</h1>
    <p class="section-sub" style="margin:12px auto 26px">
      الرابط الذي فتحته لا يقود إلى شيء. ربما تغيّر أو كُتب خطأً.
    </p>
    <a class="btn btn-primary" href="/">العودة للرئيسية</a>
  </div>
</div>`;
  return layout({ title: 'الصفحة غير موجودة', body, settings, active: null });
}

module.exports = {
  renderPage, renderContact, renderNotFound,
  renderForgot, renderReset, renderResetDone,
  renderLogin, renderRegister, renderAccount,
  renderMatches, renderStandings, riyadhToday, shiftDay,
  esc,
};
