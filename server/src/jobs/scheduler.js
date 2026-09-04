// scheduler — المزامنة التلقائية الدورية.
//
// مبدأ التصميم: الحصة المجانية 100 طلب/يوم، فكل قرار هنا محكوم
// بسؤال "كم طلباً يكلف؟":
//
// 1. مزامنة كاملة كل SYNC_FULL_HOURS (افتراضياً 6 ساعات):
//    فرق + جدول الموسم = طلبان لكل دوري مفعّل × 4 مرات/يوم.
//    بدوري واحد: 8 طلبات/يوم.
//
// 2. نبض مباشر كل SYNC_LIVE_SECONDS (افتراضياً 300 ثانية = 5 دقائق)،
//    لكنه يسأل قاعدتنا أولاً: هل توجد مباراة في "النافذة النشطة"
//    (من 15 دقيقة قبل الانطلاق حتى 4 ساعات بعده)؟
//    - لا  ← لا شيء. صفر طلبات خارجية. وهذا هو حال معظم اليوم.
//    - نعم ← طلب واحد لكل دوري له مباراة نشطة، يحدّث النتائج
//            الجارية ويلتقط المنتهية ويحتسب نقاطها فوراً.
//    يوم مباريات كامل (~4 ساعات) بدوري واحد يكلف ~48 طلباً.
//
// الضرب في عدد الدوريات هو الخطر الحقيقي على الحصة: دوريان
// يلعبان في نفس المساء يضاعفان تكلفة النبض. لهذا يفلتر الاستعلام
// أدناه على الدوريات المفعّلة فقط.
//
// لماذا setInterval وليس مكتبة cron؟ جدولنا "كل n" بسيط ولا يحتاج
// صيغ cron (دقائق/أيام أسبوع محددة). حين نحتاجها نضيف المكتبة.
const db = require('../config/db');
const footballProvider = require('../services/footballProvider');
const { mapFixture } = require('../mappers/fixtureMapper');
const fixtureRepo = require('../repositories/fixtureRepo');
const scoringService = require('../services/scoringService');
const { syncAll } = require('./syncFixtures');
const liveActivityService = require('../services/liveActivityService');
const logger = require('../utils/logger');

const FULL_SYNC_MS = Number(process.env.SYNC_FULL_HOURS || 6) * 3600 * 1000;
const LIVE_TICK_MS = Number(process.env.SYNC_LIVE_SECONDS || 300) * 1000;

// أعلام "قيد التنفيذ": لو تأخر المزود وجاء موعد النبض التالي قبل
// انتهاء السابق، نتخطى بدل أن تتراكم العمليات فوق بعضها.
let fullSyncRunning = false;
let liveTickRunning = false;

async function fullSync() {
  if (fullSyncRunning) return;
  fullSyncRunning = true;
  try {
    await syncAll();
  } catch (err) {
    // المجدول لا يسقط أبداً بسبب فشل دورة واحدة — يسجل ويجرب
    // في الموعد التالي (الفشل الشائع: نفاد الحصة أو انقطاع الشبكة).
    logger.error('[scheduler] full sync failed:', err.message);
  } finally {
    fullSyncRunning = false;
  }
}

async function liveTick() {
  if (liveTickRunning) return;
  liveTickRunning = true;
  try {
    // الفحص المحلي المجاني: (دوري، موسم، يوم UTC) فيه مباريات ضمن
    // النافذة النشطة. عادة يوم واحد، وقد يكونان اثنين لو مباراة قرب
    // منتصف الليل UTC.
    // to_char يعيد التاريخ نصاً جاهزاً "YYYY-MM-DD". لو أرجعناه
    // كعمود date لحولته مكتبة pg إلى كائن Date بمنتصف ليل التوقيت
    // المحلي، وتحويله لنص UTC يزحزحه لليوم السابق — وقعنا فيها فعلاً.
    //
    // مع تعدد الدوريات صار الصف يحمل الدوري أيضاً: طلب المزود
    // مقيّد بدوري واحد، فمباريات دوريين في نفس اللحظة تحتاج طلبين.
    // JOIN مع leagues (وليس LEFT JOIN) مقصود: دوري أوقفه الأدمن
    // يختفي من النتيجة فلا يكلّف شيئاً من الحصة رغم وجود مبارياته.
    //
    // خاصية "صفر تكلفة وقت الخمول" باقية كما هي: الشرط الزمني هو
    // ما يحكم، فبلا مباراة نشطة تعود النتيجة فارغة ولا يخرج أي
    // طلب مهما بلغ عدد الدوريات المفعّلة.
    const { rows } = await db.query(`
      SELECT DISTINCT f.league_id, f.season,
             to_char((f.kickoff_at AT TIME ZONE 'UTC')::date, 'YYYY-MM-DD') AS day
      FROM fixtures f
      JOIN leagues l ON l.id = f.league_id AND l.enabled
      WHERE f.status IN ('scheduled', 'live')
        AND f.kickoff_at BETWEEN now() - interval '4 hours'
                             AND now() + interval '15 minutes'
    `);
    if (rows.length === 0) return; // لا نشاط — صفر تكلفة

    for (const { league_id: leagueId, season, day: date } of rows) {
      const raw = await footballProvider.getFixturesByDate(date, { leagueId, season });
      const fixtures = raw.map(mapFixture);
      await fixtureRepo.upsertMany(fixtures);
      liveActivityService.syncInBackground(fixtures);
      logger.info(
        `[scheduler] live tick: refreshed ${fixtures.length} fixtures for league ${leagueId} on ${date}`
      );
    }

    // احتساب فوري لما انتهى للتو — المتوقعون يرون نقاطهم خلال
    // دقائق من صافرة النهاية، لا بعد المزامنة الكاملة التالية.
    await scoringService.settleFinished();
  } catch (err) {
    logger.error('[scheduler] live tick failed:', err.message);
  } finally {
    liveTickRunning = false;
  }
}

function start() {
  logger.info(
    `[scheduler] started (full sync every ${FULL_SYNC_MS / 3600000}h, ` +
    `live tick every ${LIVE_TICK_MS / 1000}s when matches are active)`
  );

  // مزامنة كاملة بعد 5 ثوانٍ من الإقلاع (نمهل اتصالات القاعدة
  // وRedis)، ثم دورياً. كاش الست ساعات يجعل إعادة تشغيل السيرفر
  // المتكررة أثناء التطوير شبه مجانية.
  setTimeout(fullSync, 5000);
  setInterval(fullSync, FULL_SYNC_MS);
  setInterval(liveTick, LIVE_TICK_MS);
}

module.exports = { start, liveTick, fullSync };
