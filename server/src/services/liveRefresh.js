// liveRefresh — إنعاش المباريات الجارية عند الطلب لا بالمؤقّت وحده.
//
// المجدول ينبض كل خمس دقائق (SYNC_LIVE_SECONDS) لأنه يدفع من الحصة
// سواء تابع أحدٌ المباراة أم لا. لكن من فتح شاشة «مباشر» يريد
// النتيجة الآن لا بعد أربع دقائق — فنجعل الطلب نفسه هو ما يُنعش:
// حين يُسأل السيرفر عن مباريات جارية يسأل المزوّد أولاً.
//
// والتكلفة مضبوطة من طبقتين:
//   1) كاش المزوّد (30 ثانية لمباريات اليوم): ألف مستخدم يحدّثون كل
//      عشرين ثانية يكلّفون طلبين في الدقيقة لكل دوري، لا ألفين.
//   2) خانق محلي أقصر من الكاش: لا نلمس Redis أصلاً إن كنا أنعشنا
//      هذا الدوري قبل لحظات — الحمل على السيرفر نفسه لا على الحصة.
//
// وبلا مباراة جارية لا يخرج طلب واحد: الشرط في الاستعلام لا هنا.
//
// ولا يرمي أبداً: فشل الإنعاش يعني نتيجة عمرها دقائق لا شاشة خطأ —
// والمجدول سيلحق بها في نبضته التالية على أي حال.
const provider = require('./footballProvider');
const fixtureRepo = require('../repositories/fixtureRepo');
const { mapFixture } = require('../mappers/fixtureMapper');
const logger = require('../utils/logger');

/** أقل فاصل بين إنعاشين لنفس (دوري، يوم) — أقصر من كاش المزوّد. */
const MIN_GAP_MS = 20 * 1000;

/** آخر إنعاش لكل مفتاح، للخنق. في الذاكرة: السيرفر عملية واحدة. */
const lastRun = new Map();

/** يوم المباراة بتوقيت UTC كما يفهمه المزوّد — نفس حساب المجدول. */
function utcDay(kickoffAt) {
  return new Date(kickoffAt).toISOString().slice(0, 10);
}

/**
 * ينعش صفوف المباريات الجارية من المزوّد ثم يعيد نسختها المحدّثة.
 *
 * يقبل أي قائمة مباريات ويتجاهل غير الجارية؛ فالمستدعي يمرّر ما
 * عنده بلا تصفية. ويعيد القائمة نفسها بعد إعادة قراءتها من القاعدة
 * كي يرى المستدعي النتيجة الجديدة لا القديمة التي حملها.
 */
async function refresh(fixtures, reload) {
  const live = fixtures.filter((f) => f.status === 'live');
  if (live.length === 0) return fixtures;

  // (دوري، موسم، يوم) بلا تكرار: مباراتان في نفس الدوري طلب واحد.
  const groups = new Map();
  for (const f of live) {
    const key = `${f.league_id}:${f.season}:${utcDay(f.kickoff_at)}`;
    if (!groups.has(key)) groups.set(key, f);
  }

  let touched = false;
  for (const [key, f] of groups) {
    const last = lastRun.get(key) ?? 0;
    if (Date.now() - last < MIN_GAP_MS) continue;
    lastRun.set(key, Date.now());
    try {
      const raw = await provider.getFixturesByDate(utcDay(f.kickoff_at), {
        leagueId: f.league_id,
        season: f.season,
      });
      await fixtureRepo.upsertMany(raw.map(mapFixture));
      touched = true;
    } catch (err) {
      logger.warn(`[live] refresh ${key} failed: ${err.message}`);
    }
  }

  return touched && reload ? reload() : fixtures;
}

module.exports = { refresh };
