// appleStore — التحقّق من معاملات App Store (StoreKit 2) في الخادم.
//
// الفكرة في سطر: التطبيق لا يرسل «إيصالاً» بالمعنى القديم، بل معاملة
// موقّعة من آبل (JWS) هي نفسها التي أعطاها StoreKit للجهاز. آبل توقّعها
// بسلسلة شهادات تنتهي عند شهادة جذر عامة، فنستطيع التحقّق منها هنا
// بلا اتصال بخوادم آبل وبلا مفتاح API — كما يُتحقّق من توقيع جواز
// سفر بمعرفة ختم الجهة المُصدِرة لا بالاتصال بها.
//
// ما الذي يمنع التزوير إذاً؟ ثلاثة أشياء تُفحص كلها هنا:
//   1) التوقيع صحيح وسلسلته تنتهي عند جذر آبل (المكتبة الرسمية).
//   2) المعاملة لتطبيقنا نحن: bundleId وappAppleId في داخلها.
//   3) لم تُسترَدّ (revocationDate) ولم ينتهِ اشتراكها إن كانت اشتراكاً.
// ومعرّف المعاملة فريد عند آبل، وقيد UNIQUE في دفتر المشتريات يمنع
// منحها مرتين (راجع purchaseRepo).
//
// بيئتان لا واحدة: مشتريات المراجِع في آبل ومشتريات الاختبار تأتي
// من Sandbox بتوقيع مختلف عن الإنتاج. الرفض بحجة «ليست إنتاجاً» كان
// سيُسقط التطبيق في المراجعة نفسها، فنجرّب الإنتاج ثم Sandbox.
const fs = require('fs');
const path = require('path');
const {
  SignedDataVerifier,
  Environment,
  VerificationException,
} = require('@apple/app-store-server-library');
const logger = require('../utils/logger');

class AppleStoreError extends Error {
  constructor(status, message, code) {
    super(message);
    this.status = status;
    this.expose = true;
    this.code = code;
  }
}

/** شهادات جذر آبل العامة، محمّلة مرة واحدة. */
let rootCerts = null;
function loadRootCerts() {
  if (rootCerts) return rootCerts;
  const dir = path.join(__dirname, '..', '..', 'certs', 'apple');
  const files = fs.existsSync(dir)
    ? fs.readdirSync(dir).filter((f) => f.endsWith('.cer'))
    : [];
  if (files.length === 0) {
    throw new AppleStoreError(503, 'التحقّق من App Store غير مهيّأ', 'APPLE_IAP_NOT_CONFIGURED');
  }
  rootCerts = files.map((f) => fs.readFileSync(path.join(dir, f)));
  return rootCerts;
}

function bundleId() {
  return process.env.APPLE_BUNDLE_ID || 'com.sahfootball.app';
}

/** معرّف التطبيق الرقمي في App Store Connect — تطلبه آبل لبيئة الإنتاج. */
function appAppleId() {
  const raw = process.env.APPLE_APP_ID;
  return raw ? Number(raw) : undefined;
}

/** المُحقِّقان، يُبنيان عند أول استعمال. */
const verifiers = {};
function verifierFor(env) {
  if (!verifiers[env]) {
    // enableOnlineChecks=false: التحقّق من سلسلة الشهادات محلياً دون
    // سؤال آبل عن إلغائها (OCSP). كافٍ لمعاملة StoreKit 2 بحسب توثيق
    // المكتبة، ولا يجعل الشراء رهينة انقطاع شبكة نحو آبل.
    verifiers[env] = new SignedDataVerifier(
      loadRootCerts(), false, env, bundleId(),
      env === Environment.PRODUCTION ? appAppleId() : undefined,
    );
  }
  return verifiers[env];
}

/**
 * يتحقّق من معاملة موقّعة ويرجع خلاصتها.
 *
 * يرجع { transactionId, originalTransactionId, productId, expiresAt,
 * environment, type }. يرمي AppleStoreError برسالة عربية تصلح للعرض.
 */
async function verifyTransaction(signedTransaction) {
  if (!signedTransaction || typeof signedTransaction !== 'string') {
    throw new AppleStoreError(400, 'إيصال App Store مفقود', 'APPLE_RECEIPT_MISSING');
  }

  let payload = null;
  let environment = null;
  let lastError = null;
  for (const env of [Environment.PRODUCTION, Environment.SANDBOX]) {
    try {
      payload = await verifierFor(env).verifyAndDecodeTransaction(signedTransaction);
      environment = env;
      break;
    } catch (err) {
      lastError = err;
      // بيئة غير مطابقة = جرّب التالية؛ أي فشل آخر نُبقيه لنبلّغ عنه.
    }
  }
  if (!payload) {
    const status = lastError instanceof VerificationException ? lastError.status : 'unknown';
    logger.warn(`[apple] معاملة مرفوضة (${status}): ${lastError?.message || ''}`);
    throw new AppleStoreError(400, 'إيصال App Store غير صالح', 'APPLE_RECEIPT_INVALID');
  }

  if (payload.bundleId && payload.bundleId !== bundleId()) {
    throw new AppleStoreError(400, 'الإيصال لتطبيق آخر', 'APPLE_RECEIPT_INVALID');
  }
  if (payload.revocationDate) {
    throw new AppleStoreError(400, 'هذه العملية مستردَّة', 'APPLE_RECEIPT_REVOKED');
  }

  const expiresAt = payload.expiresDate ? new Date(payload.expiresDate) : null;
  if (expiresAt && expiresAt.getTime() < Date.now()) {
    throw new AppleStoreError(400, 'انتهى هذا الاشتراك', 'APPLE_SUBSCRIPTION_EXPIRED');
  }

  if (environment === Environment.SANDBOX) {
    logger.info(`[apple] معاملة Sandbox ${payload.transactionId} (${payload.productId})`);
  }

  return {
    transactionId: String(payload.transactionId),
    originalTransactionId: String(payload.originalTransactionId || payload.transactionId),
    productId: payload.productId,
    expiresAt,
    environment,
    type: payload.type,
  };
}

module.exports = { verifyTransaction, AppleStoreError };
