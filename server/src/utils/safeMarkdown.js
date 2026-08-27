// safeMarkdown — يحوّل نص Markdown الذي يكتبه الأدمن إلى HTML آمن.
//
// ── لماذا هذا الملف موجود أصلاً ─────────────────────────────────
// نصوص صفحات الموقع (site_pages.body) يكتبها الأدمن من اللوحة،
// ويقرأها كل زائر للموقع العام. هذا بالضبط تعريف "XSS مخزّن":
// لو تسرّب HTML خام من محرّر اللوحة إلى الصفحة، فحساب أدمن واحد
// مخترق (أو أدمن غاضب) يزرع <script> يعمل في متصفح كل زائر —
// يسرق جلساتهم ويعيد توجيههم. الحاجز الوحيد بين الحالتين هو هذا
// الملف، ولذلك هو صغير ومغلق عمداً: لا يفهم إلا ما نسمح به.
//
// ── الترتيب هو الأمان ───────────────────────────────────────────
// نهرب HTML أولاً على النص كله، ثم نبني وسوماً فوق النص المهرَّب.
// عكس الترتيب (بناء ثم تهريب) يهرب الوسوم التي أنشأناها نحن
// فتظهر كنص، ويجبرك على "تهريب انتقائي" — وهناك يعود الثغرة
// بالضبط. أي تعديل مستقبلي يجب أن يحافظ على هذا الترتيب.
//
// ولماذا بلا مكتبة (marked / markdown-it)؟ المكتبات العامة تدعم
// HTML الخام داخل Markdown افتراضياً (هذا جزء من مواصفة Markdown)،
// فتحتاج معها منقّياً ثانياً (DOMPurify) وإعدادات صحيحة. المجموعة
// التي نحتاجها هنا صغيرة ومعروفة، وكتابتها تُبقي سطح الهجوم كله
// في ملف واحد يمكن قراءته كاملاً.

// المجموعة المدعومة عمداً — لا أكثر:
// عناوين # إلى ###، فقرات، **عريض**، *مائل*، قوائم مرقّمة وغير
// مرقّمة، روابط [نص](رابط)، وخط فاصل ---.
// غير المدعوم (اقتباسات، جداول، صور، كتل كود، قوائم متداخلة)
// يظهر كنص عادي — تدهور مرئي لا مفاجأة أمنية.

// الخطوة الأولى دائماً. & أولاً وإلا حوّلنا & الخاصة بالكيانات
// التي أنشأناها نحن في الأسطر التالية (&lt; تصير &amp;lt;).
// نهرب ' و " أيضاً وليس < > فقط: قيمة الرابط تُكتب داخل خاصية
// href محاطة بعلامتي اقتباس، وعلامة اقتباس غير مهرَّبة داخلها
// تكسر الخاصية وتسمح بإضافة onclick بجانبها.
function escapeHtml(text) {
  return String(text)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// البروتوكولات المسموحة في href.
//
// لماذا لا يكفي تهريب HTML؟ لأن المتصفح ينفّذ محتوى href كشيفرة
// إن كان بروتوكوله javascript: — بلا أي وسم <script> وبلا أي
// رمز يحتاج تهريباً. الرابط [اضغط](javascript:alert(1)) نصه
// كله أحرف عادية تمر من escapeHtml سليمة، ثم يصير:
//   <a href="javascript:alert(1)">اضغط</a>
// وهي شيفرة تعمل بضغطة. وكذلك data:text/html,... الذي يفتح
// صفحة كاملة يكتبها المهاجم على أصلنا. فحص البروتوكول ليس
// تشدداً زائداً بل هو الحاجز الوحيد في هذا المسار تحديداً.
const SAFE_PROTOCOLS = ['http:', 'https:', 'mailto:'];

function safeHref(rawUrl) {
  // إزالة كل المسافات وأحرف التحكم قبل الفحص. المتصفحات تتجاهل
  // هذه الأحرف داخل الرابط، فـ "java\tscript:alert(1)" ينفَّذ
  // عندها بينما يمر من فحص ساذج يقارن البداية كما هي.
  const url = rawUrl.replace(/[\u0000- ]/g, '').trim();
  if (!url) return null;

  // روابط داخلية نسبية تبدأ بـ / — الصفحات تشير لبعضها
  // ([الشروط](/terms)) وليس لها بروتوكول أصلاً.
  // شرط الحرف الثاني مهم: // ليس مساراً داخلياً بل رابط "موروث
  // البروتوكول" (//evil.com) يخرج من موقعنا كلياً.
  if (url.startsWith('/') && !url.startsWith('//')) return url;

  // new URL يفكّ الرابط بنفس قواعد المتصفح بدل تخمينها بتعبير
  // نمطي، ويرمي خطأ على ما ليس رابطاً مطلقاً — وهو رفض مقبول.
  try {
    const parsed = new URL(url);
    return SAFE_PROTOCOLS.includes(parsed.protocol) ? url : null;
  } catch {
    return null;
  }
}

// التنسيقات داخل السطر. تُطبَّق على نص مهرَّب مسبقاً.
// العريض قبل المائل: ** يجب أن تُلتقط قبل أن يبتلع تعبير * نجمة
// واحدة منها فتتحول **نص** إلى <em>*نص*</em>.
function emphasis(text) {
  return text
    .replace(/\*\*([^*\n]+)\*\*/g, '<strong>$1</strong>')
    .replace(/\*([^*\n]+)\*/g, '<em>$1</em>');
}

// علامة نائبة للروابط أثناء معالجة السطر.
// السبب: لو أنشأنا وسم <a href="..."> ثم مرّرنا الناتج على
// emphasis، فرابط يحتوي نجمتين (شائع في روابط الحملات) يتحول
// جزء من href إلى <em> — تخريب صامت. نخزّن الوسم جانباً ونضع
// مكانه علامة لا يمكن أن ترد في النص (حرف NUL مُزال من المدخل
// في render قبل أي شيء).
const MARK = '\u0000';
const LINK_RE = /\[([^\]\n]*)\]\(([^)\s]*)\)/g;

function inline(text) {
  const links = [];

  const withPlaceholders = text.replace(LINK_RE, (match, label, url) => {
    const href = safeHref(url);
    const inner = emphasis(label);
    // رابط مرفوض: نُبقي النص ونُسقط الرابط. الإسقاط الصامت مقصود —
    // إظهار الرابط المرفوض كنص يمنح المهاجم منصة لعرض ما كتبه.
    if (href === null) {
      links.push(inner);
    } else if (href.startsWith('http')) {
      // rel="noopener noreferrer" على الروابط الخارجية: بدون
      // noopener تحصل الصفحة المفتوحة على مرجع لنافذتنا وتستطيع
      // إعادة توجيهها (tabnabbing).
      links.push(`<a href="${href}" target="_blank" rel="noopener noreferrer nofollow">${inner}</a>`);
    } else {
      links.push(`<a href="${href}">${inner}</a>`);
    }
    return `${MARK}${links.length - 1}${MARK}`;
  });

  return emphasis(withPlaceholders).replace(
    new RegExp(`${MARK}(\\d+)${MARK}`, 'g'),
    (m, i) => links[Number(i)]
  );
}

function render(markdown) {
  if (typeof markdown !== 'string' || markdown.trim() === '') return '';

  // 1) تهريب كل HTML — قبل أي تحليل. حرف NUL يُزال هنا لأننا
  //    نستعمله علامة نائبة داخلياً، ولا معنى له في نص مكتوب.
  const escaped = escapeHtml(markdown.replace(/\u0000/g, ''));

  // 2) التحويل فوق النص المهرَّب فقط.
  const lines = escaped.replace(/\r\n?/g, '\n').split('\n');
  const html = [];

  let paragraph = [];   // أسطر الفقرة الجارية
  let listType = null;  // 'ul' أو 'ol' أو null

  const flushParagraph = () => {
    if (paragraph.length === 0) return;
    // <br /> بين أسطر الفقرة وليس دمجها بمسافة (سلوك Markdown
    // القياسي): الأدمن يكتب في مربع نص عادي لا في محرّر Markdown،
    // فسطر جديد عنده يعني سطراً جديداً في الصفحة. مخالفة المواصفة
    // هنا تخدم من يكتب فعلاً.
    html.push(`<p>${paragraph.map(inline).join('<br />')}</p>`);
    paragraph = [];
  };

  const flushList = () => {
    if (listType) {
      html.push(`</${listType}>`);
      listType = null;
    }
  };

  for (const line of lines) {
    const trimmed = line.trim();

    if (trimmed === '') {
      flushParagraph();
      flushList();
      continue;
    }

    // خط فاصل: ثلاث شرطات فأكثر وحدها في السطر.
    if (/^-{3,}$/.test(trimmed)) {
      flushParagraph();
      flushList();
      html.push('<hr />');
      continue;
    }

    // عنوان: من # إلى ### فقط. المسافة بعد الشباك مشترطة حتى لا
    // يتحول وسم مثل #الهلال إلى عنوان.
    const heading = /^(#{1,3})\s+(.*)$/.exec(trimmed);
    if (heading) {
      flushParagraph();
      flushList();
      const level = heading[1].length;
      html.push(`<h${level}>${inline(heading[2].trim())}</h${level}>`);
      continue;
    }

    // قائمة غير مرقّمة: - أو *
    const bullet = /^[-*]\s+(.*)$/.exec(trimmed);
    if (bullet) {
      flushParagraph();
      if (listType !== 'ul') {
        flushList();
        html.push('<ul>');
        listType = 'ul';
      }
      html.push(`<li>${inline(bullet[1].trim())}</li>`);
      continue;
    }

    // قائمة مرقّمة: 1. 2. ...
    const numbered = /^\d+[.)]\s+(.*)$/.exec(trimmed);
    if (numbered) {
      flushParagraph();
      if (listType !== 'ol') {
        flushList();
        html.push('<ol>');
        listType = 'ol';
      }
      html.push(`<li>${inline(numbered[1].trim())}</li>`);
      continue;
    }

    // سطر عادي: يُضم للفقرة الجارية.
    // سطر يتبع قائمة مباشرة بلا سطر فارغ يُنهي القائمة — لا ندعم
    // الأسطر المتابعة داخل عنصر قائمة.
    flushList();
    paragraph.push(trimmed);
  }

  flushParagraph();
  flushList();

  return html.join('\n');
}

module.exports = { render, escapeHtml };
