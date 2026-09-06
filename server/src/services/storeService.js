// storeService — الجسر بين متجر التطبيقات ودفتر مشترياتنا.
//
// بسائقين، كـ mailer.js و pushProvider.js تماماً:
//   STORE_DRIVER=console  — للتطوير: يقبل أي إيصال ويمنح. يرفض
//                           العمل في الإنتاج رفضاً قاطعاً.
//   STORE_DRIVER=store    — الحقيقي: يتحقّق من الإيصال عند آبل أو
//                           جوجل قبل المنح.
//
// لماذا السائق الوهمي أصلاً؟ لأن المشتريات داخل التطبيق لا تعمل
// على المحاكي ولا قبل إنشاء المنتجات في App Store Connect، وبلا
// طريقة لتشغيل المسار كاملاً محلياً تبقى كل شاشات الاشتراك
// غير مجرّبة حتى يوم النشر — وهو أسوأ يوم لاكتشاف خطأ في الدفع.
//
// والحارس الذي يجعل هذا آمناً: `assertDriverAllowed` أدناه. سائق
// يقبل أي نصّ كإيصال في الإنتاج = تاج مجاني لكل من يعرف curl،
// فالرفض هنا صريح ويقع عند الإقلاع لا عند أول محاولة شراء.
const premiumService = require('./premiumService');
const appleStore = require('./appleStore');
const logger = require('../utils/logger');

class StoreError extends Error {
  constructor(status, message, code = null) {
    super(message);
    this.status = status;
    this.expose = true;
    this.code = code;
  }
}

const driver = () => (process.env.STORE_DRIVER || 'console').toLowerCase();
const isProduction = () => process.env.NODE_ENV === 'production';

/**
 * الحارس: لا سائق وهمي في الإنتاج أبداً.
 *
 * يُنادى في كل عملية منح لا عند الإقلاع وحده — متغيّرات البيئة
 * تتبدّل بإعادة تشغيل، ونشرٌ ينسى STORE_DRIVER يجب أن يُغلق باب
 * الشراء لا أن يفتحه على مصراعيه.
 */
function assertDriverAllowed() {
  if (driver() === 'console' && isProduction()) {
    logger.error('[store] STORE_DRIVER=console في الإنتاج — رُفض الشراء');
    throw new StoreError(503, 'الشراء غير متاح الآن', 'STORE_NOT_CONFIGURED');
  }
}

/** أي منتج هذا؟ يرجع { kind, quantity } أو null. */
async function resolveProduct(productId) {
  const cfg = await premiumService.config();
  if (productId === cfg.crown.product_id) {
    return { kind: 'crown', quantity: 1 };
  }
  if (productId === cfg.multiplier_pack.product_id) {
    return { kind: 'multiplier', quantity: cfg.multiplier_pack.size || 1 };
  }
  if (cfg.shield_pack && productId === cfg.shield_pack.product_id) {
    return { kind: 'shield', quantity: cfg.shield_pack.size || 1 };
  }
  return null;
}

/**
 * التحقّق من الإيصال ومنح ما يترتّب عليه.
 *
 * المعرّف الفريد للمعاملة هو ما يمنع المنح المكرّر، وهو يأتي من
 * المتجر لا منّا: نفس الإيصال المُعاد إرساله يحمل نفس المعرّف
 * فيصطدم بقيد UNIQUE في دفتر المشتريات ويُهمَل (راجع purchaseRepo).
 */
async function verifyAndGrant({ userId, platform, productId, receipt }) {
  assertDriverAllowed();

  const cfg = await premiumService.config();
  if (!cfg.enabled) throw new StoreError(503, 'الشراء متوقّف مؤقتاً', 'STORE_DISABLED');

  const product = await resolveProduct(productId);
  if (!product) throw new StoreError(400, 'منتج غير معروف');

  const verified = await verifyReceipt({ platform, productId, receipt });
  // المتجر يقول ماذا اشترى فعلاً؛ لو خالف ما ادّعاه العميل نصدّق المتجر
  // ونرفض: العميل لا يختار المنتج، الإيصال يحدّده.
  if (verified.productId && verified.productId !== productId) {
    throw new StoreError(400, 'الإيصال لمنتج آخر', 'RECEIPT_PRODUCT_MISMATCH');
  }

  const { already, entitlements } = await premiumService.grant({
    userId,
    kind: product.kind,
    quantity: product.quantity,
    platform: verified.platform,
    externalId: verified.transactionId,
    until: verified.expiresAt || null,
  });

  logger.info(`[store] ${already ? 'إيصال مكرّر' : 'منح'} ${product.kind} للمستخدم ${userId}`);
  return { ok: true, already, entitlements };
}

/**
 * الاستعادة: نفس مسار التحقّق، ونتيجته "ما تملكه الآن".
 *
 * لا نمنح شيئاً جديداً هنا بالضرورة — الإيصال المستعاد غالباً
 * مسجّل سلفاً فيُهمَل، وترجع الامتيازات كما هي. وهذا هو السلوك
 * الصحيح: الاستعادة تصحيح حالة لا عملية شراء.
 */
async function restore({ userId, platform, receipt }) {
  assertDriverAllowed();
  if (!receipt) {
    // بلا إيصال: نرجع ما عندنا. من اشترى بحسابه ودخل من جهاز آخر
    // يجد تاجه لأن الاشتراك على الحساب لا على الجهاز.
    return { ok: true, restored: false, entitlements: await premiumService.forUser(userId) };
  }
  const cfg = await premiumService.config();
  const verified = await verifyReceipt({
    platform, productId: cfg.crown.product_id, receipt,
  });
  // المُستعاد قد يكون أي منتج: الإيصال يقول أيّها، ونمنح بحسبه.
  const product = await resolveProduct(verified.productId || cfg.crown.product_id);
  if (!product) throw new StoreError(400, 'منتج غير معروف');
  const { entitlements } = await premiumService.grant({
    userId, kind: product.kind, quantity: product.quantity,
    platform: verified.platform, externalId: verified.transactionId,
    until: verified.expiresAt || null,
  });
  return { ok: true, restored: true, entitlements };
}

/**
 * التحقّق الفعلي من الإيصال.
 * يرجع { platform, transactionId, productId?, expiresAt? }.
 *
 * آبل (منذ 2026-09-07): الإيصال هو معاملة StoreKit 2 الموقّعة (JWS)،
 * ويتحقّق منها appleStore محلياً بشهادات جذر آبل — بلا مفتاح API.
 * جوجل: لم يُكتب بعد عمداً، ولا يجوز أن يُكتب تخميناً؛ حتى يصل حساب
 * الخدمة يبقى الرفض صريحاً ومكتوباً فيه ما ينقص.
 */
async function verifyReceipt({ platform, productId, receipt }) {
  const plat = String(platform || '').toLowerCase();

  if (driver() === 'console') {
    // التطوير: نقبل ونشتقّ معرّفاً ثابتاً من الإيصال كي يبقى تكرار
    // نفس الإيصال مكرّراً (وهو ما نريد اختباره أصلاً).
    const id = `console:${plat || 'dev'}:${productId}:${String(receipt || 'no-receipt').slice(0, 60)}`;
    logger.warn(`[store] سائق التطوير قبل إيصالاً بلا تحقّق (${id})`);
    return { platform: plat || 'manual', transactionId: id };
  }

  if (plat === 'apple') {
    try {
      const t = await appleStore.verifyTransaction(receipt);
      return {
        platform: 'apple',
        transactionId: `apple:${t.transactionId}`,
        productId: t.productId,
        expiresAt: t.expiresAt,
      };
    } catch (err) {
      if (err instanceof appleStore.AppleStoreError) {
        throw new StoreError(err.status, err.message, err.code);
      }
      throw err;
    }
  }

  if (plat === 'google') {
    if (!process.env.GOOGLE_PLAY_SERVICE_ACCOUNT) {
      throw new StoreError(503,
        'الشراء عبر Google Play غير مفعّل بعد',
        'GOOGLE_IAP_NOT_CONFIGURED');
    }
    throw new StoreError(503, 'التحقّق من إيصال جوجل غير مكتمل', 'GOOGLE_IAP_NOT_CONFIGURED');
  }

  throw new StoreError(400, 'منصّة شراء غير معروفة');
}

module.exports = { verifyAndGrant, restore, resolveProduct, StoreError };
