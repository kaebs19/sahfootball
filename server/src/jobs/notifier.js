// notifier — الوظيفة المجدولة التي تقرر متى يُزعج المستخدم.
//
// نوعان اليوم:
//   reminder — "مباريات تُقفل قريباً ولم تتوقّع بعد"
//   result   — "احتُسبت نقاطك"
//
// المبدأ الحاكم لكل سطر هنا: إشعار واحد مجمّع أفضل من خمسة.
// المستخدم لا يقرأ خمسة إشعارات متتالية، بل يوقف الإشعارات —
// وهذا في iOS قرار لا رجعة فيه عملياً، لأن الإذن يُطلب مرة واحدة
// ولا يعود التطبيق يسأل عنه أبداً.
//
// ولا نداء خارجي هنا إطلاقاً: كل الأسئلة تُجاب من قاعدتنا، فلا
// أثر على حصة مزوّد المباريات مهما تكرر النبض.
const notificationRepo = require('../repositories/notificationRepo');
const pushService = require('../services/pushService');
const logger = require('../utils/logger');

// كم قبل صافرة البداية نذكّر. ساعتان: وقت كافٍ ليفتح المستخدم
// التطبيق ويتوقّع بهدوء، وقريب بما يكفي ليبقى الأمر في ذهنه.
const LEAD_MINUTES = Number(process.env.NOTIFY_LEAD_MINUTES || 120);
const TICK_MS = Number(process.env.NOTIFY_TICK_SECONDS || 300) * 1000;

let running = false;

// آخر تنظيف. الوظيفة تنبض كل خمس دقائق بينما التنظيف يكفيه مرة
// يومياً — تشغيله في كل نبضة يعني ~288 استعلام حذف يومياً لا يحذف
// أغلبها شيئاً.
let lastPurgeAt = 0;
const PURGE_EVERY_MS = 24 * 3600 * 1000;

// جمع عربي صحيح. نسخة مطابقة لـ Format._counted في
// mobile/lib/format.dart، ومقصود أن تكون مطابقة: الإشعار والشاشة
// يقولان نفس الرقم للمستخدم نفسه، و"5 نقطة" في الإشعار بينما
// الشاشة تقول "5 نقاط" يجعل الإشعار يبدو رسالة آلية غريبة.
//
// ولماذا تُكتب مرتين بدل حزمة i18n مشتركة؟ نفس منطق format.dart:
// أربع صيغ في سطرين يقرؤهما أي عربي فوراً، مقابل ملفات ترجمة
// وأدوات بناء لتطبيق بلغة واحدة.
function counted(n, one, two, few, many) {
  if (n === 1) return one;
  if (n === 2) return two;
  if (n >= 3 && n <= 10) return `${n} ${few}`;
  return `${n} ${many}`;
}

const points = (n) => counted(n, 'نقطة', 'نقطتين', 'نقاط', 'نقطة');
const matches = (n) => counted(n, 'مباراة', 'مباراتين', 'مباريات', 'مباراة');

// "لـ3 مباريات" لكن "لمباراتين": التطويل يفصل حرف الجر عن رقم
// (وبدونه يلتصق الحرف بالرقم فيصعب قراءته)، أما مع كلمة فالوصل
// هو الإملاء الصحيح و"لـمباراتين" تبدو خطأً مطبعياً.
const withLam = (text) => (/^[0-9]/.test(text) ? `لـ${text}` : `ل${text}`);


/** يجمع صفوف الاستعلام في خريطة: مستخدم ← صفوفه. */
function groupByUser(rows) {
  const map = new Map();
  for (const row of rows) {
    const list = map.get(row.user_id);
    if (list) list.push(row);
    else map.set(row.user_id, [row]);
  }
  return map;
}

/**
 * نص التذكير. مباراة واحدة تُذكر بالاسم، وأكثر من ذلك يُختصر عدداً:
 * الإشعار يُقتطع بعد سطرين على شاشة القفل، فسرد أربعة أسماء يعني
 * ألا يقرأ المستخدم أهم كلمة فيه — "لم تتوقّع".
 */
function reminderText(rows) {
  if (rows.length === 1) {
    const { home_name: home, away_name: away } = rows[0];
    return {
      title: 'مباراة تُقفل قريباً',
      body: `${home} ضد ${away} — ما توقّعت بعد. توقّعك يُقفل عند صافرة البداية.`,
    };
  }
  // العدد يأتي بعد حرف جر لا في موضع الفاعل، وهذا يحسم مشكلة
  // إعرابية حقيقية: "مباراتين تُقفل" خطأ (الصواب "مباراتان
  // تُقفلان")، وضبط ذلك يفرض صيغة فعل لكل عدد. بعد اللام يصح
  // المجرور في كل الحالات بصيغة واحدة.
  return {
    title: 'توقعاتك تُقفل قريباً',
    body: `ما توقّعت ${withLam(matches(rows.length))} تنطلق قريباً. ادخل قبل صافرة البداية.`,
  };
}

/**
 * نص النتيجة. الرقم أولاً لأنه ما ينتظره المستخدم، والمباراة بعده.
 * صفر نقاط يُقال بلا مواساة ولا تهوين: الصياغة الودّية المفرطة عند
 * الخسارة تُقرأ سخريةً.
 */
function resultText(rows) {
  const total = rows.reduce((sum, r) => sum + (r.points || 0), 0);

  if (rows.length === 1) {
    const r = rows[0];
    const score = `${r.goals_home} - ${r.goals_away}`;
    return {
      title: total > 0 ? `كسبت ${points(total)}` : 'انتهت المباراة',
      body: `${r.home_name} ${score} ${r.away_name}`,
    };
  }
  return {
    title: total > 0 ? `كسبت ${points(total)}` : 'احتُسبت توقعاتك',
    body: `من ${matches(rows.length)}. افتح "ملفي" لتفاصيل الجولة.`,
  };
}

/**
 * دورة واحدة. تعالج النوعين، وتسجّل ما أُرسل قبل أن تنتقل
 * للمستخدم التالي.
 *
 * التسجيل بعد الإرسال لا قبله، والفرق يظهر عند تعطّل المزوّد:
 * لو سجّلنا أولاً لضاع الإشعار نهائياً (مسجّل كمُرسَل ولم يصل).
 * بهذا الترتيب أسوأ ما يحدث هو تكرار نادر لو انهار السيرفر في
 * الثانية الفاصلة — وتكرار نادر أهون من صمت دائم.
 */
async function tick() {
  if (running) return;
  running = true;
  try {
    const [reminders, results] = await Promise.all([
      notificationRepo.usersNeedingReminder(LEAD_MINUTES),
      notificationRepo.unnotifiedResults(),
    ]);

    for (const [userId, rows] of groupByUser(reminders)) {
      const { title, body } = reminderText(rows);
      const delivered = await pushService.sendToUser(userId, {
        title, body, data: { type: 'reminder', fixtureId: rows[0].fixture_id },
      });
      // لا نسجّل ما لم يصل لأي جهاز: مستخدم كل أجهزته ميتة سيُسجَّل
      // له "أُرسل" ثم يثبّت التطبيق من جديد فلا يصله شيء أبداً.
      if (delivered > 0) {
        await notificationRepo.markSent(userId, 'reminder', rows.map((r) => r.fixture_id));
      }
    }

    for (const [userId, rows] of groupByUser(results)) {
      const { title, body } = resultText(rows);
      const delivered = await pushService.sendToUser(userId, {
        title, body, data: { type: 'result', fixtureId: rows[0].fixture_id },
      });
      if (delivered > 0) {
        await notificationRepo.markSent(userId, 'result', rows.map((r) => r.fixture_id));
      }
    }

    if (reminders.length || results.length) {
      logger.info(
        `[notifier] tick: ${reminders.length} reminder rows, ${results.length} result rows`
      );
    }

    // التنظيف بعد الإرسال لا قبله: لو حذف شيئاً ما زال ذا معنى
    // (خطأ في الحد) نريد أن يقع ذلك بعد أن يأخذ الاستعلامان
    // نسختهما، فلا يتحوّل خطأ الحد إلى إشعار مكرر في نفس الدورة.
    const now = Date.now();
    if (now - lastPurgeAt > PURGE_EVERY_MS) {
      lastPurgeAt = now;
      const removed = await notificationRepo.purgeOldSent();
      if (removed) logger.info(`[notifier] purged ${removed} old sent rows`);
    }
  } catch (err) {
    // كالمجدول تماماً: دورة فاشلة تُسجَّل ولا تُسقط شيئاً.
    logger.error('[notifier] tick failed:', err.message);
  } finally {
    running = false;
  }
}

function start() {
  const driver = process.env.PUSH_DRIVER || 'console';
  logger.info(
    `[notifier] started (driver=${driver}, lead=${LEAD_MINUTES}m, tick=${TICK_MS / 1000}s)`
  );
  setInterval(tick, TICK_MS);
}

module.exports = { start, tick, reminderText, resultText };
