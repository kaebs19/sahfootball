// routes/auth — طبقة HTTP للمصادقة. رقيقة عمداً:
// كل المنطق في authService، وهنا فقط استخراج المدخلات وتشكيل الرد.
const express = require('express');
const authService = require('../services/authService');
const requireAuth = require('../middleware/requireAuth');
const throttle = require('../utils/authThrottle');

const router = express.Router();

// POST /api/auth/register — { email, password, displayName? }
router.post('/register', async (req, res) => {
  const { email, password, displayName } = req.body || {};
  const result = await authService.register({ email, password, displayName });
  // 201 = Created: اصطلاح REST لإنشاء مورد جديد بنجاح.
  res.status(201).json(result);
});

// POST /api/auth/login — { email, password }
router.post('/login', async (req, res) => {
  const { email, password } = req.body || {};
  const id = String(email || '').trim().toLowerCase();

  await throttle.assertNotLocked('login', id);
  try {
    const result = await authService.login({ email, password });
    await throttle.clear('login', id);
    res.json(result);
  } catch (err) {
    // نسجل الفشل فقط لو كان خطأ بيانات دخول (401) — عطل داخلي
    // في السيرفر يجب ألا يحسب على المستخدم.
    if (err.status === 401) await throttle.recordFailure('login', id);
    throw err;
  }
});

// POST /api/auth/apple — { identityToken, displayName? }
// identityToken من AuthenticationServices في iOS.
// displayName يُرسل في أول تفويض فقط (Apple لا تكرره) — انظر authService.
router.post('/apple', async (req, res) => {
  const { identityToken, displayName } = req.body || {};
  const result = await authService.loginWithApple({ identityToken, displayName });
  res.json(result);
});

// POST /api/auth/refresh — { refreshToken }
router.post('/refresh', async (req, res) => {
  const result = await authService.refresh(req.body?.refreshToken);
  res.json(result);
});

// POST /api/auth/logout — { refreshToken }
router.post('/logout', async (req, res) => {
  await authService.logout(req.body?.refreshToken);
  // 204 = No Content: تم، ولا شيء نقوله. الخروج ينجح دائماً.
  res.status(204).end();
});

// GET /api/auth/me — من أنا؟ (محمي)
// أبسط مسار محمي: تطبيق iOS يستدعيه عند الإقلاع للتحقق من صلاحية
// الجلسة المخزنة وجلب بيانات المستخدم المحدثة.
router.get('/me', requireAuth, async (req, res) => {
  const userRepo = require('../repositories/userRepo');
  const user = await userRepo.findById(req.userId);
  if (!user) return res.status(401).json({ error: 'الحساب لم يعد موجوداً' });
  res.json({ user });
});

// POST /api/auth/change-password — { currentPassword, newPassword } (محمي)
router.post('/change-password', requireAuth, async (req, res) => {
  const { currentPassword, newPassword } = req.body || {};
  const tokens = await authService.changePassword(req.userId, { currentPassword, newPassword });
  res.json(tokens);
});

// PUT /api/auth/email — { newEmail, currentPassword } (محمي)
//
// PUT وليس POST: العملية تضع قيمة نهائية لمورد قائم (بريد الحساب)،
// وتكرارها بنفس الجسم لا يضيف شيئاً — بخلاف change-password التي
// تولّد جلسات جديدة في كل مرة.
router.put('/email', requireAuth, async (req, res) => {
  const { newEmail, currentPassword } = req.body || {};
  const result = await authService.changeEmail(req.userId, { newEmail, currentPassword });
  res.json(result);
});

// POST /api/auth/forgot-password — { email }
router.post('/forgot-password', async (req, res) => {
  const id = String(req.body?.email || '').trim().toLowerCase();

  // الحد هنا يمنع إغراق بريد شخص بالرسائل، ويحد من محاولات
  // اكتشاف البريدات المسجلة عبر قياس الأزمنة.
  await throttle.assertNotLocked('forgot', id);
  await throttle.recordFailure('forgot', id); // كل طلب يُحسب، ناجحاً أو لا

  await authService.forgotPassword(req.body?.email);
  // نفس الرد دائماً — وُجد البريد أم لا (انظر شرح authService).
  res.json({ message: 'إن كان البريد مسجلاً لدينا فسيصلك رمز الاستعادة' });
});

// POST /api/auth/reset-password — { email, code, newPassword }
router.post('/reset-password', async (req, res) => {
  const { email, code, newPassword } = req.body || {};
  const result = await authService.resetPassword({ email, code, newPassword });
  res.json(result);
});

module.exports = router;
