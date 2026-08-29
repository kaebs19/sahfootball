// السكربت الوحيد في الموقع، ومن نطاقنا (script-src 'self').
//
// كل شيء آخر يعمل بلا JavaScript عمداً: الترشيح روابط، والثيم كوكي،
// والنماذج ترسل بالطريقة التقليدية. هذا الملف استثناء واحد لسبب
// واحد: أزرار + و− للنتيجة.
//
// بلا سكربت كان كل ضغط على + رحلة كاملة إلى الخادم وعودة — أربع
// ضغطات لكتابة 2-1 تعني أربع رحلات وأربع إعادات رسم. والحقول
// تبقى قابلة للكتابة كما هي، فمن يعطّل JavaScript لا يفقد شيئاً
// سوى الزرّين.
(function () {
  'use strict';

  var MIN = 0;
  var MAX = 99;

  function clamp(n) {
    if (isNaN(n)) return MIN;
    return Math.min(MAX, Math.max(MIN, n));
  }

  document.addEventListener('click', function (e) {
    var btn = e.target.closest('.step');
    if (!btn) return;

    // الزر type="button" في الـ HTML، لكن نمنع الإرسال صراحةً أيضاً:
    // متصفح قديم قد يعامله كزر إرسال داخل نموذج.
    e.preventDefault();

    var field = btn.closest('.pf-team');
    var input = field && field.querySelector('input[type="number"]');
    if (!input) return;

    var delta = btn.dataset.step === 'up' ? 1 : -1;
    input.value = String(clamp(parseInt(input.value, 10) + delta));

    // input لا change: بعض المتصفحات لا تطلق change إلا عند فقد
    // التركيز، وقد نستمع إليه لاحقاً.
    input.dispatchEvent(new Event('input', { bubbles: true }));
  });
})();
