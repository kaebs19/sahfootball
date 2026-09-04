// routes/notifications — تسجيل جهاز المستخدم وتفضيلات الإشعارات.
//
// كلها للمستخدم المسجّل نفسه: معرّفه يؤخذ من التوكن حصراً، فلا
// يستطيع أحد ربط جهازه بحساب غيره ولا قراءة تفضيلات سواه.
const express = require('express');
const requireAuth = require('../middleware/requireAuth');
const notificationRepo = require('../repositories/notificationRepo');

const router = express.Router();
router.use(requireAuth);

const PLATFORMS = ['ios', 'android'];

// حد أعلى لطول التوكن: توكن APNs 64 حرفاً وتوكن FCM ~160، وهذا
// الحد يترك هامشاً واسعاً ويمنع في الوقت نفسه أن يملأ أحد الجدول
// بنص بحجم ميغابايت.
const MAX_TOKEN_LENGTH = 512;

// POST /api/notifications/token — { token, platform }
// يُنادى بعد أن يمنح المستخدم الإذن، وعند كل إقلاع بعدها: النظام
// قد يغيّر التوكن في أي وقت (استعادة نسخة احتياطية، تحديث نظام)،
// والتطبيق لا يعرف متى، فيرسله دائماً ونحن نتعامل مع التكرار.
router.post('/token', async (req, res) => {
  const { token, platform } = req.body || {};

  if (typeof token !== 'string' || !token.trim() || token.length > MAX_TOKEN_LENGTH) {
    return res.status(400).json({ error: 'توكن الجهاز غير صالح' });
  }
  if (!PLATFORMS.includes(platform)) {
    return res.status(400).json({ error: 'المنصة غير مدعومة' });
  }

  await notificationRepo.registerToken({
    token: token.trim(),
    userId: req.userId,
    platform,
  });
  res.status(204).end();
});

// DELETE /api/notifications/token — { token }
// عند الخروج من الحساب. بدونه يبقى الجهاز مربوطاً بالحساب السابق
// فتصل إشعاراته لمن يستخدم الهاتف بعده.
router.delete('/token', async (req, res) => {
  const { token } = req.body || {};
  if (typeof token !== 'string' || !token.trim()) {
    return res.status(400).json({ error: 'توكن الجهاز غير صالح' });
  }
  await notificationRepo.removeToken(token.trim());
  res.status(204).end();
});

// GET /api/notifications/prefs
router.get('/prefs', async (req, res) => {
  const prefs = await notificationRepo.getPrefs(req.userId);
  res.json({
    reminders: prefs.notify_reminders,
    results: prefs.notify_results,
    live: prefs.notify_live,
  });
});

// PUT /api/notifications/prefs — { reminders?, results? }
// الحقل المحذوف يبقى على حاله (COALESCE في الاستعلام)، فتستطيع
// الشاشة إرسال ما تغيّر وحده.
router.put('/prefs', async (req, res) => {
  const { reminders, results, live } = req.body || {};

  for (const [name, value] of [['reminders', reminders], ['results', results], ['live', live]]) {
    if (value !== undefined && typeof value !== 'boolean') {
      return res.status(400).json({ error: `${name} يجب أن تكون true أو false` });
    }
  }

  const prefs = await notificationRepo.updatePrefs(req.userId, {
    reminders: reminders ?? undefined,
    results: results ?? undefined,
    live: live ?? undefined,
  });
  res.json({
    reminders: prefs.notify_reminders,
    results: prefs.notify_results,
    live: prefs.notify_live,
  });
});

// ── النشاط الحيّ (iOS Live Activity) ──────────────────────────────
//
// التطبيق يبدأ النشاط ويستلم توكنه من النظام ثم يسلّمه هنا، والسيرفر
// يحدّثه مع كل هدف (راجع liveActivityService). fixtureId فارغ يعني
// توكن «بدء بالدفع» يصلح لأي مباراة قادمة.

// POST /api/notifications/live-activity — { token, fixtureId? }
router.post('/live-activity', async (req, res) => {
  const { token, fixtureId } = req.body || {};
  if (typeof token !== 'string' || !token.trim() || token.length > MAX_TOKEN_LENGTH) {
    return res.status(400).json({ error: 'توكن النشاط غير صالح' });
  }
  const id = fixtureId == null ? null : Number(fixtureId);
  if (id !== null && !Number.isInteger(id)) {
    return res.status(400).json({ error: 'fixtureId يجب أن يكون رقماً' });
  }
  await notificationRepo.registerActivityToken({
    token: token.trim(),
    userId: req.userId,
    fixtureId: id,
  });
  res.status(204).end();
});

// DELETE /api/notifications/live-activity — { token } أو بلا جسم = كلها
router.delete('/live-activity', async (req, res) => {
  const { token } = req.body || {};
  if (typeof token === 'string' && token.trim()) {
    await notificationRepo.removeActivityToken(token.trim());
  } else {
    await notificationRepo.removeActivityTokensForUser(req.userId);
  }
  res.status(204).end();
});

module.exports = router;
