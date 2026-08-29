// السكربت الوحيد في الموقع، ومن نطاقنا (script-src 'self').
//
// كل شيء آخر يعمل بلا JavaScript عمداً: الترشيح روابط، والثيم كوكي،
// والنماذج ترسل بالطريقة التقليدية. وهذا الملف تحسين لا شرط —
// بدونه تبقى الصفحة كاملة وقابلة للاستعمال:
//   • الأقسام تظهر كلها متتابعة بدل تبويبات.
//   • العدّاد يبقى نصاً ثابتاً ("بعد 17 ساعة و29 دقيقة").
//   • حقول النتيجة تُكتب بلوحة المفاتيح.
(function () {
  'use strict';

  // ── 1) أزرار + و− ─────────────────────────────────────────────
  //
  // بلا سكربت كانت كل ضغطة رحلة كاملة إلى الخادم وعودة، أي أربع
  // رحلات لكتابة 2-1.
  var MIN = 0;
  var MAX = 99;

  document.addEventListener('click', function (e) {
    var btn = e.target.closest('.step');
    if (!btn) return;

    // الزر type="button" في الـ HTML، ونمنع الإرسال هنا أيضاً:
    // متصفح قديم قد يعامله كزر إرسال داخل نموذج.
    e.preventDefault();

    var input = btn.parentNode.querySelector('input[type="number"]');
    if (!input) return;

    var next = parseInt(input.value, 10) + (btn.dataset.step === 'up' ? 1 : -1);
    if (isNaN(next)) next = MIN;
    input.value = String(Math.min(MAX, Math.max(MIN, next)));
    input.dispatchEvent(new Event('input', { bubbles: true }));
  });

  // ── 1ب) الاتجاه المشتقّ ───────────────────────────────────────
  //
  // "فوز القادسية" يتحدّث مع الأرقام. الخادم يرسله محسوباً من
  // التوقّع المحفوظ، وهذا يبقيه صحيحاً أثناء التعديل — بدونه يبقى
  // النص يقول "تعادل" بينما المستخدم رفع رقماً لتوّه.
  var rows = document.querySelector('.trs');
  var pick = document.querySelector('[data-pick]');

  if (rows && pick) {
    var refresh = function () {
      var rh = rows.querySelector('input[name="home"]').value.trim();
      var ra = rows.querySelector('input[name="away"]').value.trim();

      // فارغان معاً = لا توقّع بعد. وفارغ واحد يُعامل صفراً — وهو
      // بالضبط ما سيحفظه الخادم، فما يراه المستخدم هو ما يُحفظ.
      if (rh === '' && ra === '') { pick.textContent = ''; return; }

      var h = rh === '' ? 0 : parseInt(rh, 10);
      var a = ra === '' ? 0 : parseInt(ra, 10);
      if (isNaN(h) || isNaN(a)) { pick.textContent = ''; return; }

      pick.textContent = h > a ? 'فوز ' + rows.dataset.home
        : h < a ? 'فوز ' + rows.dataset.away
        : 'تعادل';
    };

    rows.addEventListener('input', refresh);
    refresh();
  }

  // ── 2) العدّاد التنازلي ───────────────────────────────────────
  //
  // "بعد 17 ساعة و29 دقيقة" جواب صحيح لكنه ساكن. العدّاد المتحرك
  // يقول الشيء نفسه ويضيف إحساس الاقتراب — وهو ما يدفع للتوقّع
  // قبل الإقفال.
  var cd = document.querySelector('.mh-cd[data-kickoff]');
  if (cd) {
    var at = new Date(cd.dataset.kickoff).getTime();

    var pad = function (n) { return n < 10 ? '0' + n : String(n); };

    var tick = function () {
      var left = Math.floor((at - Date.now()) / 1000);
      if (left <= 0) {
        // انطلقت بينما الصفحة مفتوحة. لا نعيد التحميل تلقائياً —
        // قد يكون المستخدم يكتب توقّعه — بل نقول له ما حدث.
        cd.textContent = 'انطلقت';
        cd.classList.add('done');
        clearInterval(timer);
        return;
      }
      var d = Math.floor(left / 86400);
      var h = Math.floor((left % 86400) / 3600);
      var m = Math.floor((left % 3600) / 60);
      var sec = left % 60;

      // فوق يوم: الثواني ضجيج. من ينتظر ثلاثة أيام لا يعنيه رقم
      // يتغير كل ثانية.
      cd.textContent = d > 0
        ? d + ' ي ' + pad(h) + ':' + pad(m)
        : pad(h) + ':' + pad(m) + ':' + pad(sec);
    };

    tick();
    var timer = setInterval(tick, 1000);
  }

  // ── 3) تبويبات صفحة المباراة ─────────────────────────────────
  //
  // الخادم يرسل الأقسام كلها متتابعة، والسكربت يطويها في تبويبات.
  // العكس (إرسال قسم واحد وجلب البقية) كان سيجعل الصفحة بلا محتوى
  // لمن يعطّل JavaScript، ويكلّف رحلة لكل تبويب.
  var nav = document.querySelector('.tabs');
  var panels = [].slice.call(document.querySelectorAll('[data-tab]'));

  if (nav && panels.length > 1) {
    nav.hidden = false;

    var show = function (i) {
      panels.forEach(function (p, j) { p.hidden = j !== i; });
      [].forEach.call(nav.children, function (b, j) {
        b.classList.toggle('on', j === i);
        b.setAttribute('aria-selected', j === i ? 'true' : 'false');
      });
    };

    panels.forEach(function (panel, i) {
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'tab';
      btn.setAttribute('role', 'tab');
      btn.textContent = panel.dataset.tab;
      btn.addEventListener('click', function () { show(i); });
      nav.appendChild(btn);

      // عنوان القسم صار اسم التبويب — تكراره داخله ضجيج.
      var h2 = panel.querySelector('h2');
      if (h2) h2.hidden = true;
    });

    show(0);
  }
})();
