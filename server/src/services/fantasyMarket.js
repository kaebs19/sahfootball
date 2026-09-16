// fantasyMarket — المحفظة وحركة الأسعار.
//
// هذا الملف يجيب سؤالين يصنعان عمق اللعبة:
//
//   ١) كم أملك؟ — المحفظة تنمو بالبيع الرابح لا بالنقاط. من
//      اكتشف لاعباً قبل الناس يشتري بما لا يستطيعه غيره.
//   ٢) كم يساوي فلان الأسبوع القادم؟ — السعر يتحرّك بالطلب قبل
//      الأداء، فيصير الشراء رهاناً على ما سينتبه له الناس لا
//      ملخّصاً لما حدث أمس.
//
// والفصل بين النقاط والمحفظة مقصود وحاسم: لو اشتُريت اللاعبون
// بالنقاط لتصدّر من فاز بالجولة الأولى فاشترى نجوماً أكثر ففاز
// أكثر — كرة ثلج لا يلحقها أحد بعد ثلاث جولات.
const db = require('../config/db');
const logger = require('../utils/logger');

/** خطوة السعر: عُشر لا نصف — الحركة الأسبوعية يجب أن تُتابَع لا أن تقفز. */
const STEP = 0.1;

/** أقصى حركة في الجولة الواحدة، وأقصى انحراف عن سعر البداية. */
const MAX_ROUND_MOVE = 0.3;
const MAX_SEASON_MOVE = 3.0;

/** وزن الطلب مقابل الأداء في تحريك السعر. */
const DEMAND_WEIGHT = 0.7;
const FORM_WEIGHT = 0.3;

/**
 * الطلب الذي يُشبع الإشارة: ١٥٪ من المدرّبين صافياً.
 *
 * بلا هذا القاسم يبقى السعر ساكناً إلى الأبد: صافي طلبٍ بـ٣٠٪ —
 * وهو انفجارُ شعبيةٍ نادر — كان يعطي حركة ٠٫١ فقط، لأن السقف
 * يُبلَغ عند طلبٍ بنسبة ١٠٠٪ أي أن كل مدرّب في اللعبة اشتراه في
 * أسبوع واحد. الحركة يجب أن تبلغ سقفها عند ما يحدث فعلاً.
 */
const DEMAND_FULL = 0.15;

/**
 * أقلّ عدد مدرّبين يصير الطلب عنده معلومةً لا ضجيجاً.
 *
 * تحت هذا العدد يتحرّك السعر بالأداء وحده: في أسبوع الإطلاق قد
 * يكون اللاعبون عشرة، فانتقالٌ واحد يعني «١٠٪ من السوق اشتراه»
 * ويقفز سعره — وهي معلومةٌ كاذبة عن سوقٍ لم يوجد بعد.
 */
const MIN_MANAGERS_FOR_DEMAND = 30;

// القسمة على ٠٫١ ثم الضرب فيها تُخرج ٥٫٣٠٠٠٠٠٠٠٠٠٠٠٠٠١ — خطأ
// الفاصلة العائمة المعتاد. الضرب في ١٠ والقسمة عليه يتجنّبه،
// والفرق ليس تجميلياً: هذا رقمٌ مالي يُجمع خمس عشرة مرة ثم
// يُقارن بالمحفظة.
const roundTo = (value) => Math.round(value * 10) / 10;
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));

/**
 * ما يستردّه البائع: سعر الشراء + **نصف** الربح.
 *
 * ونصفه لا كلّه: بالكامل تتضخّم المحافظ حتى يملك الجميع كل
 * النجوم بعد عشر جولات، فتموت المفاضلة التي بُنيت عليها اللعبة.
 * والنصف يكافئ الاكتشاف المبكر ويُبقي الثمن حقيقياً.
 *
 * والخسارة كاملةٌ على صاحبها: من اشترى بـ٩ وهبط إلى ٧ يستردّ ٧.
 * تقاسم الخسارة يجعل الشراء بلا مخاطرة، وبلا مخاطرة لا قرار.
 */
function sellPrice(boughtPrice, currentPrice) {
  const bought = Number(boughtPrice);
  const now = Number(currentPrice);
  if (now <= bought) return roundTo(now);
  return roundTo(bought + (now - bought) / 2);
}

/**
 * حركة سعر لاعب في جولة.
 *
 * @param demand صافي الطلب منسوباً لعدد المدرّبين (−١ إلى +١)
 * @param form أداؤه في الجولة منسوباً لسعره (−١ إلى +١)
 *
 * صافية (pure) كي تُختبر بأمثلة ورقية: مدخلان ورقم.
 */
function priceMove(demand, form, { hasMarket = true } = {}) {
  const scaled = clamp(demand / DEMAND_FULL, -1, 1);
  const signal = hasMarket
    ? DEMAND_WEIGHT * scaled + FORM_WEIGHT * form
    : form;
  return roundTo(clamp(signal, -1, 1) * MAX_ROUND_MOVE);
}

/**
 * تحريك أسعار دوري بعد انتهاء جولة.
 *
 * تُستدعى مرة لكل جولة بعد تسويتها. وآمنة التكرار بمعنى أنها لا
 * تنفجر، لكنها **ليست** بلا أثر عند التكرار — ولهذا يحرسها
 * المستدعي بعلامة الجولة المسوّاة (راجع settleFantasy).
 */
async function moveLeaguePrices(leagueId, season, round) {
  const { rows: counts } = await db.query(
    // المدرّبون هم من بنى تشكيلة. ومن ثبّت ناديه ولم يبنِ بعد له
    // صفٌّ في الجدول (راجع fantasyRepo.setClub)، وعدُّه يكبّر قاسم
    // الطلب بمن لا ينتقل أصلاً — فيبدو السوق ساكناً وهو يتحرّك.
    `SELECT COUNT(*)::int AS managers
       FROM fantasy_squads s
      WHERE s.league_id = $1 AND s.season = $2
        AND EXISTS (SELECT 1 FROM fantasy_squad_players sp WHERE sp.squad_id = s.id)`,
    [leagueId, season]
  );
  const managers = counts[0]?.managers ?? 0;
  const hasMarket = managers >= MIN_MANAGERS_FOR_DEMAND;

  // الطلب: كم دخل وكم خرج في هذه الجولة. والأداء: نقاط الجولة.
  const { rows } = await db.query(
    `SELECT p.id, p.price, p.start_price, p.season_delta,
            COALESCE(t.ins, 0)::int  AS ins,
            COALESCE(t.outs, 0)::int AS outs,
            COALESCE(s.points, 0)::int AS points
       FROM players p
       LEFT JOIN (
         SELECT player_id,
                COUNT(*) FILTER (WHERE direction = 'in')::int  AS ins,
                COUNT(*) FILTER (WHERE direction = 'out')::int AS outs
           FROM fantasy_transfers WHERE round = $3
          GROUP BY player_id
       ) t ON t.player_id = p.id
       LEFT JOIN (
         SELECT s.player_id, SUM(s.points)::int AS points
           FROM player_fixture_stats s
           JOIN fixtures f ON f.id = s.fixture_id
          WHERE f.league_id = $1 AND f.season = $2 AND f.round = $3
          GROUP BY s.player_id
       ) s ON s.player_id = p.id
      WHERE p.league_id = $1 AND p.season = $2 AND p.available
        AND NOT p.manual_price`,
    [leagueId, season, round]
  );
  if (!rows.length) return 0;

  const client = await db.pool.connect();
  let moved = 0;
  try {
    await client.query('BEGIN');
    for (const r of rows) {
      const demand = managers ? (r.ins - r.outs) / managers : 0;

      // الأداء منسوباً للسعر: هدفان من لاعب بـ٥ أثمن من هدفين من
      // لاعب بـ١٣ — الثاني كان ثمنه مدفوعاً سلفاً. والقاسم سعرُه
      // لا رقمٌ ثابت، وإلا صعد الغالي دائماً وهبط الرخيص دائماً.
      const expected = Number(r.price) / 2;
      const form = expected ? clamp((r.points - expected) / expected, -1, 1) : 0;

      let delta = priceMove(demand, form, { hasMarket });

      // سقف الموسم: لا يصعد لاعب ٤٫٥ إلى ١٢ في منتصف الموسم مهما
      // أحبّه الناس — السعر تقديرٌ لقيمته لا لشعبيته وحدها.
      const season = Number(r.season_delta);
      const allowed = clamp(delta, -MAX_SEASON_MOVE - season, MAX_SEASON_MOVE - season);
      delta = roundTo(allowed);

      if (!delta) {
        await client.query('UPDATE players SET price_delta = 0 WHERE id = $1', [r.id]);
        continue;
      }

      await client.query(
        `UPDATE players
            SET price        = GREATEST(4.0, price + $2),
                price_delta  = $2,
                season_delta = season_delta + $2
          WHERE id = $1`,
        [r.id, delta]
      );
      moved += 1;
    }
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }

  logger.info(
    `[market] league ${leagueId} ${round}: ${moved} prices moved` +
      (hasMarket ? '' : ' (بالأداء وحده — السوق صغير)')
  );
  return moved;
}

module.exports = {
  sellPrice,
  priceMove,
  moveLeaguePrices,
  STEP,
  MAX_ROUND_MOVE,
  MAX_SEASON_MOVE,
  MIN_MANAGERS_FOR_DEMAND,
  DEMAND_FULL,
};
