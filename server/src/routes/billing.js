// routes/billing — التاج الذهبي: ما يُباع، وما يملكه اللاعب.
//
// الشراء نفسه لا يتم هنا: المتجر (آبل أو جوجل) يقبض المال ويصدر
// إيصالاً، وهذا المسار يتحقّق من الإيصال ويمنح. أي مسار "امنحني
// التاج" بلا إيصال يعني تاجاً مجانياً لمن يعرف كتابة curl، ولهذا
// المنح اليدوي محصورٌ بالأدمن في routes/admin.
const express = require('express');
const requireAuth = require('../middleware/requireAuth');
const premiumService = require('../services/premiumService');
const purchaseRepo = require('../repositories/purchaseRepo');
const storeService = require('../services/storeService');

const router = express.Router();

function fail(res, err) {
  if (err.status && err.expose) {
    return res.status(err.status).json({ error: err.message, code: err.code ?? null });
  }
  throw err;
}

// GET /api/billing/products — عام: صفحة الشراء تُعرض للضيف أيضاً،
// وهي أقوى سبب لإنشاء حساب.
router.get('/products', async (req, res) => {
  res.json(await premiumService.products());
});

router.use(requireAuth);

// GET /api/billing/me — امتيازاتي الآن.
router.get('/me', async (req, res) => {
  res.json({ entitlements: await premiumService.forUser(req.userId) });
});

// GET /api/billing/purchases — سجلّي.
router.get('/purchases', async (req, res) => {
  res.json({ purchases: await purchaseRepo.findMine(req.userId) });
});

// POST /api/billing/verify — { platform, product_id, receipt }
//
// العميل يرسل ما أعطاه إياه المتجر بعد نجاح الدفع، والخادم يتحقّق
// ثم يمنح. التحقّق في الخادم لا في العميل: إيصالٌ يقبله الهاتفُ
// وحده يستطيع أي أحد تزويره، والمنح مقابل نصّ لم يره المتجر هو
// نفسه المنح المجاني.
router.post('/verify', async (req, res) => {
  try {
    const { platform, product_id: productId, receipt } = req.body || {};
    const result = await storeService.verifyAndGrant({
      userId: req.userId, platform, productId, receipt,
    });
    res.json(result);
  } catch (err) { fail(res, err); }
});

// POST /api/billing/restore — استعادة المشتريات.
//
// شرط من آبل لا خيار: كل تطبيق يبيع اشتراكاً يجب أن يوفّر زرّ
// استعادة، وإلا رُفض في المراجعة. وهو مفيد فعلاً — من بدّل هاتفه
// يستعيد تاجه بلا دعم فني.
router.post('/restore', async (req, res) => {
  try {
    const result = await storeService.restore({
      userId: req.userId,
      platform: req.body?.platform,
      receipt: req.body?.receipt,
    });
    res.json(result);
  } catch (err) { fail(res, err); }
});

module.exports = router;
