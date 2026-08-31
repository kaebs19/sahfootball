// championService — الرهان الموسمي: من يرفع الكأس؟
//
// توقّعُ مباراةٍ قرار دقائق، وتوقّعُ بطلٍ قرار موسم. ولهذا لا
// يُسعَّران بالطريقة نفسها: نقاط المباراة ثابتة لأن كل من يتوقّعها
// يتوقّعها بنفس المعلومات تقريباً، والبطل لا — من يراهن في الجولة
// الأولى يراهن على غيب، ومن يراهن قبل جولتين من النهاية يقرأ
// جدولاً.
//
// ═══ التسعير ═══
//
//   الجائزة = الحد الأقصى × (1 − ما انقضى من الموسم)
//
// معادلة سطر واحد تحلّ المشكلة كلها: الباب لا يُغلق أبداً — من
// يسجّل في مارس يلعبها بمئتي نقطة — ولا يوجد مع ذلك قطفٌ مجاني،
// لأن اليقين والجائزة يتحرّكان عكس بعضهما بالضبط.
//
// والبديل المرفوض كان "يُقفل بعد ربع الموسم": يمنع القطف نعم،
// لكنه يترك كل من يسجّل بعد نوفمبر أمام باب مغلق طوال الموسم —
// وهم أكثر المستخدمين على مدى سنة.
//
// ═══ لماذا تُخزَّن الجائزة مع التوقّع ═══
//
// لأن الحساب عند التسوية يُلغي المعادلة من أصلها: الموسم حينها
// منقضٍ 100%، فتصير جائزة الجميع صفراً. القيمة تُقفل لحظة
// الاختيار، وهي عقدٌ بين اللاعب واللعبة لا رقم مشتقّ.
const settingsRepo = require('../repositories/settingsRepo');
const championRepo = require('../repositories/championRepo');
const standingsService = require('./standingsService');
const logger = require('../utils/logger');

const DEFAULT_CHAMPION = { max_award: 1000 };

/** إعدادات الجائزة المعمول بها. */
async function config() {
  return (await settingsRepo.get('champion').catch(() => null)) ?? DEFAULT_CHAMPION;
}

/**
 * سعر الرهان الآن على هذا الدوري.
 *
 * يرجع { award, played, total, progress } — الأرقام كلها معروضة
 * للاعب لا مخفية عنه: "قيمتها الآن 940 لأن الموسم في أوّله" يفهمها
 * ويقرّر بها، و"940" وحدها تبدو اعتباطاً.
 */
async function quote(leagueId, season) {
  const { max_award: max } = await config();
  const { played, total } = await championRepo.seasonProgress(leagueId, season);

  // موسم بلا مباريات (لم يُزامَن بعد) يساوي بداية موسم لا نهايته:
  // القسمة على صفر تعطي NaN، وأي احتياطٍ آخر يمنح صفراً لمن يراهن
  // أبكر من الجميع — وهو أحقّ الناس بالجائزة كاملة.
  const progress = total > 0 ? played / total : 0;
  return {
    award: Math.max(0, Math.round(max * (1 - progress))),
    played,
    total,
    progress,
    max,
  };
}

/**
 * تسجيل الرهان أو تغييره.
 *
 * التغيير يُعيد التسعير بسعر اليوم — لا يحتفظ بسعر الأمس. ولو
 * احتفظ به لصار الرهان المبكّر خياراً مجانياً: أراهن على الأوفر
 * حظاً في الجولة الأولى بألف، ثم أبدّله في الجولة الثلاثين وقد
 * عرفت الجواب، محتفظاً بسعر الغيب. القيمة ثمن المخاطرة لا ثمن
 * التبكير وحده.
 */
async function pick({ userId, leagueId, season, teamId }) {
  const { award } = await quote(leagueId, season);
  return championRepo.upsert({ userId, leagueId, season, teamId, award });
}

/**
 * تسوية الأبطال: كل دوري انتهت مبارياته ولم يُسجَّل بطله بعد.
 *
 * المصدر هو ترتيب المزوّد لا حسابنا: احتساب البطل من النتائج يعني
 * تنفيذ قواعد كل اتحاد في فضّ التعادل (فارق الأهداف هنا، المواجهات
 * المباشرة هناك) — ستّ قواعد تتغيّر بين موسم وآخر، وخطأ واحد فيها
 * يمنح ألف نقطة لغير مستحقّها. الترتيب الرسمي يعرفها كلها.
 *
 * ولا تُستدعى إلا حين تنتهي كل مباريات الموسم، فهي نداء واحد
 * للمزوّد في السنة لكل دوري.
 */
async function settleFinishedSeasons() {
  const pending = await championRepo.leaguesAwaitingChampion();
  let settled = 0;

  for (const { league_id: leagueId, season } of pending) {
    let champion;
    try {
      const table = await standingsService.getStandings({ leagueId, season });
      // mapStandings يرجع صفوفاً مرتّبة برتبتها، فالأول هو البطل.
      champion = table?.[0]?.team_id ?? null;
    } catch (err) {
      // المزوّد ساقط اليوم؟ نحاول غداً. لا نخمّن بطلاً.
      logger.error(`[champion] standings failed for ${leagueId}:`, err.message);
      continue;
    }
    if (!champion) continue;

    await championRepo.recordChampion({ leagueId, season, teamId: champion, source: 'auto' });
    // النقاط = الجائزة المخزّنة لمن أصاب، وصفر لمن أخطأ. والصفر
    // يُكتب صراحةً لا يُترك NULL: "سُوّي بصفر" غير "لم يُسوَّ بعد"،
    // والفرق بينهما هو ما يمنع إعادة الاحتساب كل يوم إلى الأبد.
    settled += await championRepo.settleLeague({ leagueId, season, teamId: champion });
    logger.info(`[champion] league ${leagueId} season ${season} settled`);
  }
  return settled;
}

module.exports = { config, quote, pick, settleFinishedSeasons, DEFAULT_CHAMPION };
