// planWatch — يراقب اشتراك مزوّد البيانات وحصته اليومية.
//
// لماذا وظيفة أصلاً؟ لأن انتهاء الاشتراك عطل صامت من أسوأ نوع:
// السيرفر يعمل، والموقع يفتح، والصفحات تُعرض — لكن المزامنة تتوقف
// فتتجمّد المباريات على آخر يوم نُقل. لا خطأ في اللوق يقرؤه أحد،
// ولا صفحة بيضاء تلفت النظر. يكتشفه المستخدم قبل المالك.
//
// ونفس المنطق للحصة: تجاوزها يعني توقف المزامنة حتى منتصف الليل،
// وهو ما يحدث فعلاً حين يُضاف دوري جديد بلا حساب.
const provider = require('../services/footballProvider');
const { sendMail } = require('../services/mailer');
const { providerAlert } = require('../services/mailTemplates');
const redis = require('../config/redis');
const logger = require('../utils/logger');

// عتبات التنبيه بالأيام. أربع مرات لا مرة واحدة: تنبيه واحد قبل
// أسبوعين يُقرأ ويُنسى، والتذكير المتصاعد يصل في وقت يستطيع فيه
// المالك أن يتصرف فعلاً.
const DAY_THRESHOLDS = [14, 7, 3, 1];

// نسبة استهلاك الحصة التي تستدعي تنبيهاً.
const QUOTA_RATIO = 0.85;

const TICK_MS = 6 * 3600 * 1000; // أربع مرات يومياً

/**
 * وجهة التنبيه — إعداد صريح لا مشتق.
 *
 * لا نستعمل MAIL_FROM بديلاً: قيمته no-reply@ وهو عنوان لا يُقرأ
 * بطبيعته. تنبيه يصل إلى صندوق لا يفتحه أحد أسوأ من ألا يُرسل،
 * لأنه يعطي إحساساً كاذباً بأن المراقبة تعمل.
 */
const recipient = () => process.env.ALERT_EMAIL || null;

/**
 * يمنع تكرار نفس التنبيه.
 *
 * المفتاح يحمل سبب التنبيه لا تاريخه: عتبة "٧ أيام" لاشتراك ينتهي
 * في 2026-09-27 تُرسل مرة واحدة مهما تكرر الفحص. وحين يُجدَّد
 * الاشتراك يتغير تاريخ الانتهاء فيتغير المفتاح، وتعود العتبات
 * صالحة للدورة القادمة تلقائياً — بلا تنظيف يدوي.
 */
async function once(key, ttlSeconds, fn) {
  // NX: لا يكتب إن كان المفتاح موجوداً. الفحص والكتابة في أمر واحد
  // فلا يتسلل تنبيهان من نسختي سيرفر تفحصان في نفس اللحظة.
  const first = await redis.set(`alert:${key}`, '1', 'EX', ttlSeconds, 'NX');
  if (!first) return false;
  await fn();
  return true;
}

async function check() {
  const to = recipient();
  if (!to) {
    logger.warn('[planWatch] ALERT_EMAIL غير مضبوط — لا وجهة للتنبيه');
    return;
  }

  const status = await provider.getStatus();

  // ── انتهاء الاشتراك ──────────────────────────────────────────
  if (status.endsAt) {
    const endsAt = new Date(status.endsAt);
    const daysLeft = Math.ceil((endsAt - Date.now()) / 86400000);
    const hit = DAY_THRESHOLDS.find((t) => daysLeft <= t);

    if (hit !== undefined && daysLeft >= 0) {
      const day = endsAt.toISOString().slice(0, 10);
      await once(`plan:${day}:${hit}`, 40 * 86400, async () => {
        await sendMail({
          to,
          subject: `اشتراك مزوّد البيانات ينتهي بعد ${daysLeft} يوماً`,
          ...providerAlert({
            title: `الاشتراك ينتهي بعد ${daysLeft} يوماً`,
            lines: [
              `الخطة: <strong>${status.plan || 'غير معروفة'}</strong>`,
              `تاريخ الانتهاء: <strong>${day}</strong>`,
              'عند الانتهاء تتوقف مزامنة المباريات والنتائج. الموقع والتطبيق يبقيان يعملان، لكن البيانات تتجمّد على آخر يوم نُقل — بلا خطأ ظاهر.',
            ],
            action: 'جدّد الاشتراك من dashboard.api-football.com',
          }),
        });
        logger.warn(`[planWatch] أُرسل تنبيه انتهاء (${daysLeft} يوماً)`);
      });
    }

    // انتهى فعلاً: تنبيه يومي لا مرة واحدة — هذا عطل قائم لا قادم.
    if (daysLeft < 0 || !status.active) {
      await once(`plan:expired:${new Date().toISOString().slice(0, 10)}`, 26 * 3600, async () => {
        await sendMail({
          to,
          subject: 'انتهى اشتراك مزوّد البيانات — المزامنة متوقفة',
          ...providerAlert({
            title: 'الاشتراك منتهٍ والمزامنة متوقفة',
            lines: [
              'لا تصل مباريات جديدة ولا نتائج ولا ترتيب. البيانات المعروضة الآن هي آخر ما نُقل قبل الانتهاء.',
            ],
            action: 'جدّد الاشتراك فوراً',
          }),
        });
      });
    }
  }

  // ── الحصة اليومية ────────────────────────────────────────────
  if (status.limit && status.used / status.limit >= QUOTA_RATIO) {
    const day = new Date().toISOString().slice(0, 10);
    await once(`quota:${day}`, 26 * 3600, async () => {
      await sendMail({
        to,
        subject: `استُهلك ${Math.round((status.used / status.limit) * 100)}% من حصة اليوم`,
        ...providerAlert({
          title: 'الحصة اليومية تقترب من النفاد',
          lines: [
            `المستهلك: <strong>${status.used}</strong> من <strong>${status.limit}</strong>`,
            'عند النفاد تتوقف المزامنة حتى منتصف الليل بتوقيت المزوّد.',
            'السبب المعتاد: دوري أُضيف حديثاً، أو مباريات كثيرة تُلعب في وقت واحد.',
          ],
          action: 'راجع الدوريات المفعّلة أو ارفع الخطة',
        }),
      });
      logger.warn(`[planWatch] تنبيه حصة: ${status.used}/${status.limit}`);
    });
  }
}

async function tick() {
  try {
    await check();
  } catch (err) {
    // فشل الفحص لا يُسقط شيئاً — يُعاد في الدورة القادمة.
    logger.error('[planWatch] فشل الفحص:', err.message);
  }
}

function start() {
  logger.info(`[planWatch] started (كل ${TICK_MS / 3600000} ساعات، تنبيه عند ${DAY_THRESHOLDS.join('/')} أيام)`);
  // بعد دقيقة من الإقلاع: نترك الاتصالات تستقر أولاً.
  setTimeout(tick, 60_000);
  setInterval(tick, TICK_MS);
}

module.exports = { start, tick, check };
