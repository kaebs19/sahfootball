// fantasyPricing — كم يساوي اللاعب؟
//
// السعر هو اللعبة كلها. بلا تفاوتٍ فيه تصير الميزانية بلا معنى:
// أيّ خمسة عشر لاعباً يساوون نفس المجموع، فلا مفاضلة ولا ندم ولا
// اكتشاف. وهذا بالضبط ما كان قبل هذا الملف — كل لاعب بـ٥٫٠.
//
// والسعر **ليس رأياً**: يُحتسب من أداء الموسم، ويُعدَّل من لوحة
// الأدمن حين يخطئ الحساب (لاعبٌ عاد من إصابة، صفقةٌ لم تلعب بعد).
const db = require('../config/db');
const logger = require('../utils/logger');

/**
 * حدود السلّم. من البيئة لا ثوابت: أول موسم بلا تاريخ قد يحتاج
 * سلّماً أضيق، وتغييره لا يستحقّ نشرة كود.
 */
const MIN_PRICE = Number(process.env.FANTASY_MIN_PRICE) || 4.0;
const MAX_PRICE = Number(process.env.FANTASY_MAX_PRICE) || 15.0;
const PRICE_CURVE = Number(process.env.FANTASY_PRICE_CURVE) || 2.1;

/**
 * المرجع الذي تُقاس عليه الأسعار: المئين ٩٥ لا الأعلى.
 *
 * الأعلى رهينةُ شاذّة واحدة — لاعبٌ نزل مباراة واحدة وسجّل هدفين
 * يخرج بمعدّل ١٢ نقطة/مباراة، فيصير هو المقياس ويهبط الدوري كله
 * إلى قاع السلّم بسببه. والمئين ٩٥ يتجاهله ويبقى في يد النجوم
 * الحقيقيين.
 */
function reference(values) {
  const sorted = [...values].sort((a, b) => a - b);
  if (!sorted.length) return 0;
  return sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * 0.95))];
}

/**
 * سعرٌ ابتدائي حسب المركز، لمن لا تاريخ له بعد.
 *
 * المهاجمون أغلى من المدافعين عند الصفر لا تحيّزاً بل لأن جدول
 * النقاط يعطيهم فرصاً أكثر للتسجيل، والسوق بلا فروق ابتدائية
 * يجعل أول جولة في الموسم قرعةً لا اختياراً.
 */
const BASE_BY_POSITION = {
  Goalkeeper: 4.5,
  Defender: 4.5,
  Midfielder: 5.5,
  Attacker: 6.0,
};

/**
 * سعر لاعب من حصيلته.
 *
 * المعادلة: نقاط لكل مباراة (لا المجموع) — لاعبٌ جمع ٤٠ في عشر
 * مباريات أفضل ممن جمعها في عشرين، والمجموع وحده يكافئ من لعب
 * كثيراً لا من لعب جيداً.
 *
 * ثم يُنسب إلى السلّم نسبةً إلى أعلى معدّل في الدوري: السعر
 * مقارنةٌ بمن حولك لا رقمٌ مطلق، ودوريٌّ كله متواضع يجب أن يبقى
 * فيه غالٍ ورخيص.
 *
 * @param perGame معدّل نقاط اللاعب في المباراة
 * @param best أعلى معدّل في الدوري
 * @param position مركزه — يحدّد نقطة البداية لمن لا تاريخ له
 */
function priceFor(perGame, best, position, { minutes = 0 } = {}) {
  const base = BASE_BY_POSITION[position] ?? 5.0;

  // أقلّ من مباراة كاملة في الموسم: لا حصيلة يُحكم بها، فيبقى
  // على سعر مركزه. والحكم بعيّنة من عشر دقائق أسوأ من ألا نحكم.
  if (!best || minutes < 90) return round(base);

  const ratio = Math.max(0, Math.min(1, perGame / best));
  // أسٌّ فوق الواحد لا جذرٌ تحته. جُرّب الجذر أولاً فخرج اللاعب
  // المتوسط بـ١٢٫٠: خمسة عشر مثله = ١٨٠ من ميزانية ١٠٠، أي أن
  // **كل** تشكيلة ممكنة مرفوضة — واللعبة تموت قبل أن تبدأ.
  //
  // والرقم ٢٫١ ليس ذوقاً: الميزانية ١٠٠ لخمسة عشر لاعباً تعني
  // متوسطاً مقصوداً ٦٫٧، فيُضبط الأسّ ليضع من أداؤه نصفُ الأفضل
  // عند ٦٫٥ تقريباً. لو تغيّرت الميزانية وجب أن يتغيّر معها.
  const scaled = Math.pow(ratio, PRICE_CURVE);
  return round(MIN_PRICE + scaled * (MAX_PRICE - MIN_PRICE));
}

/** إلى أقرب نصف نقطة: ٧٫٥ لا ٧٫٣ — هكذا تُقرأ الأسعار في كل فانتازي. */
function round(value) {
  const clamped = Math.max(MIN_PRICE, Math.min(MAX_PRICE, value));
  return Math.round(clamped * 2) / 2;
}

/**
 * إعادة تسعير دوري كامل.
 *
 * `manual_price` يمنع الدهس: ما ضبطه الأدمن بيده يبقى، وإعادة
 * تسعيرٍ تمحوه تجعل عمله يضيع في كل جولة بلا أن يعرف لماذا.
 */
async function repriceLeague(leagueId, season) {
  const { rows } = await db.query(
    `SELECT p.id, p.position,
            COALESCE(SUM(s.points), 0)::int  AS points,
            COALESCE(SUM(s.minutes), 0)::int AS minutes,
            COUNT(s.fixture_id)::int         AS apps
       FROM players p
       LEFT JOIN player_fixture_stats s ON s.player_id = p.id
      WHERE p.league_id = $1 AND p.season = $2 AND p.available
        AND NOT p.manual_price
      GROUP BY p.id, p.position`,
    [leagueId, season]
  );
  if (!rows.length) return 0;

  const perGame = (r) => (r.apps ? r.points / r.apps : 0);
  // المرجع من اللاعبين المنتظمين وحدهم (٣ مباريات فأكثر): من لعب
  // مباراة أو اثنتين معدّله ضجيج، وإقحامه في المرجع يزيح السلّم.
  const best = reference(
    rows.filter((r) => r.apps >= 3).map(perGame)
  ) || Math.max(...rows.map(perGame), 0);

  const client = await db.pool.connect();
  try {
    await client.query('BEGIN');
    for (const r of rows) {
      const price = priceFor(perGame(r), best, r.position, { minutes: r.minutes });
      await client.query('UPDATE players SET price = $2 WHERE id = $1', [r.id, price]);
    }
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }

  logger.info(
    `[pricing] league ${leagueId}: ${rows.length} players, best ${best.toFixed(2)}/game`
  );
  return rows.length;
}

module.exports = {
  priceFor,
  repriceLeague,
  BASE_BY_POSITION,
  MIN_PRICE,
  MAX_PRICE,
  reference,
};
