// pushProvider — طبقة عزل الإشعارات، نسخة طبق الأصل من فلسفة
// mailer وfootballProvider: بقية المشروع ينادي send() ولا يعرف
// من أوصل الرسالة.
//
// ثلاثة drivers:
//   console — يطبع في اللوق ولا يرسل. للتطوير، وهو الافتراضي.
//   apns    — أجهزة iOS مباشرة من آبل.
//   fcm     — أجهزة أندرويد عبر Firebase Cloud Messaging (HTTP v1).
//
// لماذا APNs مباشرة بدل تمرير iOS أيضاً عبر Firebase؟ لأن FCM في
// النهاية يسلّم رسائل iOS إلى APNs بنفس مفتاح p8 الذي نرفعه إليه —
// فالوسيط لا يضيف قدرة، بل يضيف حساباً ثالثاً وملف إعدادات في
// التطبيق وحزمة native ثقيلة، ويأخذ صلاحية الإرسال لمستخدمينا.
// أندرويد لا خيار فيه: لا سبيل للوصول لجهاز أندرويد إلا عبر FCM.
//
// وبلا أي حزمة جديدة، تماماً كقرار mailer مع nodemailer:
// APNs يحتاج HTTP/2 وهو في node:http2 المدمج، وتوقيع ES256/RS256
// في jsonwebtoken الموجود أصلاً للتوكنات، والباقي fetch.
const http2 = require('node:http2');
const fs = require('node:fs');
const jwt = require('jsonwebtoken');
const logger = require('../utils/logger');

const TIMEOUT_MS = 10000;

// ── نتيجة الإرسال ────────────────────────────────────────────────
//
// لا نرمي استثناءً عند رفض توكن واحد. الفرق جوهري: فشل الشبكة
// يعني "أعد المحاولة لاحقاً"، أما توكن ميت (حذف المستخدم التطبيق)
// فيعني "احذف هذا الصف" — ولو عاملناهما سواء لبقيت التوكنات
// الميتة تُستدعى إلى الأبد، ولنمت مع كل تثبيت وحذف.
// لذلك ترجع كل دالة إرسال: 'ok' أو 'gone' أو ترمي لما عدا ذلك.
const OK = 'ok';
const GONE = 'gone';

// ── APNs ─────────────────────────────────────────────────────────
//
// المصادقة بتوكن (مفتاح p8) لا بشهادة: الشهادة تنتهي سنوياً وتوقف
// الإشعارات فجأة في يوم لا يخطر ببالك، ومفتاح p8 لا ينتهي.
//
// آبل ترفض توكن أقدم من ساعة وترفض أيضاً من يولّد توكناً جديداً
// لكل رسالة (TooManyProviderTokenUpdates). فالتخزين المؤقت هنا
// شرط تشغيل لا تحسين أداء.
const APNS_TOKEN_TTL_MS = 50 * 60 * 1000;
let apnsToken = null;
let apnsTokenAt = 0;

function apnsAuthToken() {
  const now = Date.now();
  if (apnsToken && now - apnsTokenAt < APNS_TOKEN_TTL_MS) return apnsToken;

  // المفتاح يُقرأ من مسار ملف لا من متغيّر بيئة يحمل محتواه:
  // محتوى p8 متعدد الأسطر، وحشره في .env يفسده بصمت (الأسطر
  // الجديدة تصير \n حرفية فيفشل التوقيع برسالة غامضة).
  const key = fs.readFileSync(process.env.APNS_KEY_PATH, 'utf8');

  apnsToken = jwt.sign({}, key, {
    algorithm: 'ES256',
    issuer: process.env.APNS_TEAM_ID,
    keyid: process.env.APNS_KEY_ID,
  });
  apnsTokenAt = now;
  return apnsToken;
}

// المضيف: بناء التطوير (Xcode مباشرة، والمحاكي) يصدر توكنات لبيئة
// الاختبار فقط، وإرسالها إلى المضيف الإنتاجي يرد BadDeviceToken.
// خلط البيئتين هو أشهر سبب لـ"الإشعارات لا تصل" ولا يظهر إلا هنا.
const apnsHost = () => (process.env.APNS_PRODUCTION === 'true'
  ? 'https://api.push.apple.com'
  : 'https://api.sandbox.push.apple.com');

function apnsSend({ token, title, body, data }) {
  return new Promise((resolve, reject) => {
    const client = http2.connect(apnsHost());
    // بدون هذا يبقى الاتصال معلقاً لو لم ترد آبل أبداً.
    client.setTimeout(TIMEOUT_MS, () => {
      client.destroy();
      reject(new Error('APNs: انتهت المهلة'));
    });
    client.on('error', reject);

    const payload = JSON.stringify({
      aps: {
        alert: { title, body },
        sound: 'default',
        // الشارة الحمراء على أيقونة التطبيق. لا نحسب عدداً حقيقياً
        // (يتطلب مزامنة "المقروء" مع كل جهاز)؛ 1 تكفي لتقول
        // "يوجد جديد" وتختفي حين يفتح التطبيق.
        badge: 1,
      },
      ...data,
    });

    const req = client.request({
      ':method': 'POST',
      ':path': `/3/device/${token}`,
      authorization: `bearer ${apnsAuthToken()}`,
      'apns-topic': process.env.APNS_BUNDLE_ID,
      // alert وليس background: هذه إشعارات يراها المستخدم.
      'apns-push-type': 'alert',
      // 10 = فوري. (5 = موفّر طاقة، وتؤجله آبل — لا يصلح لتذكير
      // مربوط بصافرة بداية.)
      'apns-priority': '10',
    });

    let status = 0;
    let raw = '';
    req.on('response', (headers) => { status = headers[':status']; });
    req.setEncoding('utf8');
    req.on('data', (chunk) => { raw += chunk; });
    req.on('end', () => {
      client.close();
      if (status === 200) return resolve(OK);

      // 410 = الجهاز لم يعد مسجلاً. و400 مع BadDeviceToken تعني
      // نفس الشيء عملياً (توكن من بيئة أخرى أو مشوّه): كلاهما
      // لن ينجح أبداً مهما أعدنا المحاولة.
      const reason = (() => { try { return JSON.parse(raw).reason; } catch { return ''; } })();
      if (status === 410 || reason === 'BadDeviceToken' || reason === 'Unregistered') {
        return resolve(GONE);
      }
      reject(new Error(`APNs رفض الإشعار (${status}): ${reason || raw.slice(0, 200)}`));
    });
    req.on('error', reject);

    req.end(payload);
  });
}

// ── FCM (HTTP v1) ────────────────────────────────────────────────
//
// النسخة القديمة (مفتاح خادم واحد في ترويسة) أوقفتها جوجل. الحالية
// تتطلب توكن OAuth2 من حساب خدمة — أي توقيع JWT ثم تبديله بتوكن،
// وهو ما تفعله دالتان أدناه بدل حزمة googleapis كاملة (عشرات
// الميغابايت من أجل نداءين).
const FCM_TOKEN_TTL_MS = 50 * 60 * 1000;
let fcmToken = null;
let fcmTokenAt = 0;
let fcmAccount = null;

function serviceAccount() {
  if (!fcmAccount) {
    fcmAccount = JSON.parse(fs.readFileSync(process.env.FCM_SERVICE_ACCOUNT_PATH, 'utf8'));
  }
  return fcmAccount;
}

async function fcmAccessToken() {
  const now = Date.now();
  if (fcmToken && now - fcmTokenAt < FCM_TOKEN_TTL_MS) return fcmToken;

  const account = serviceAccount();
  const assertion = jwt.sign(
    {
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: account.token_uri,
    },
    account.private_key,
    { algorithm: 'RS256', issuer: account.client_email, expiresIn: '1h' }
  );

  const res = await fetch(account.token_uri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });

  if (!res.ok) {
    const detail = await res.text().catch(() => '');
    throw new Error(`تعذّر الحصول على توكن FCM (${res.status}): ${detail.slice(0, 200)}`);
  }

  fcmToken = (await res.json()).access_token;
  fcmTokenAt = now;
  return fcmToken;
}

async function fcmSend({ token, title, body, data }) {
  const account = serviceAccount();
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${await fcmAccessToken()}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          // FCM يقبل قيم data نصوصاً فقط — رقم هنا يرد 400
          // برسالة عن نوع الحقل لا عن سببه الحقيقي.
          data: Object.fromEntries(
            Object.entries(data || {}).map(([k, v]) => [k, String(v)])
          ),
          android: { priority: 'high', notification: { sound: 'default' } },
        },
      }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    }
  );

  if (res.ok) return OK;

  const detail = await res.text().catch(() => '');
  // UNREGISTERED = التطبيق حُذف. INVALID_ARGUMENT على حقل التوكن
  // يعني توكناً من مشروع Firebase آخر — ميت هنا للأبد أيضاً.
  if (res.status === 404 || (res.status === 400 && detail.includes('registration token'))) {
    return GONE;
  }
  throw new Error(`FCM رفض الإشعار (${res.status}): ${detail.slice(0, 200)}`);
}

// ── الـ drivers ──────────────────────────────────────────────────

const DRIVERS = {
  console({ token, platform, title, body }) {
    logger.info(`[push] ── ${platform} ${token.slice(0, 12)}… ──`);
    logger.info(`[push] ${title}`);
    logger.info(`[push] ${body}`);
    return OK;
  },

  // driver واحد للمنصتين: المنصة تُقرأ من صف الجهاز لا من الإعداد،
  // لأن نفس السيرفر يخدم iOS وأندرويد في نفس اللحظة.
  real(message) {
    return message.platform === 'ios' ? apnsSend(message) : fcmSend(message);
  },
};

const DRIVER_NAMES = ['console', 'real'];

// APNs وFCM يُطلبان معاً في driver "real"، لكن مشروعاً ينشر على
// منصة واحدة لا يملك مفاتيح الأخرى. لذلك الشرط هنا: على الأقل
// واحدة منهما مكتملة، والناقصة تصير تحذيراً في env.js لا خطأ.
const APNS_KEYS = ['APNS_KEY_PATH', 'APNS_KEY_ID', 'APNS_TEAM_ID', 'APNS_BUNDLE_ID'];
const FCM_KEYS = ['FCM_SERVICE_ACCOUNT_PATH'];

/**
 * إرسال إشعار واحد لجهاز واحد.
 * يرجع 'ok' أو 'gone' (توكن ميت يجب حذفه)، ويرمي عند خطأ عابر.
 */
async function send({ token, platform, title, body, data }) {
  const name = process.env.PUSH_DRIVER || 'console';
  const driver = DRIVERS[name];
  if (!driver) {
    throw new Error(`PUSH_DRIVER غير معروف: ${name}. المتاح: ${DRIVER_NAMES.join(', ')}`);
  }
  return driver({ token, platform, title, body, data });
}

module.exports = { send, OK, GONE, DRIVER_NAMES, APNS_KEYS, FCM_KEYS };
