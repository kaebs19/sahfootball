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
 * المرجع الذي تُقاس عليه الأسعار: أعلى معدّل بين **المنتظمين**.
 *
 * وليس المئين ٩٥ — جُرّب وظهر عيبه في السوق: كل من تجاوز المئين
 * يُقصّ إلى السقف، والمتجاوزون ٥٪ من الدوري لا واحد. فخرج ستة
 * لاعبي وسط بسعر ١٣ متساوين رغم أن نقاطهم ٤١ و٤٠ و٣٨ و٣٦ —
 * وتساوي النجوم في السعر يمحو المفاضلة بينهم، وهي أدقّ قرار في
 * اللعبة كلها.
 *
 * والشاذّة التي خشيناها منه — لاعبٌ لعب مباراة وسجّل هدفين —
 * يحجبها شرط الانتظام لا المئين: من لعب نصف الجولات فأكثر معدّله
 * حقيقي، ومن لعب أقلّ لا يدخل في تحديد السقف أصلاً (وإن سُعِّر
 * هو نفسه بعدها).
 */
function reference(rows, perGame) {
  if (!rows.length) return 0;

  // عتبة الانتظام تتحرّك مع الموسم: نصف مباريات أكثر من لعب.
  // في الجولة الثالثة تعني مباراتين، وفي الثلاثين تعني خمس عشرة.
  // وعتبةٌ ثابتة (٥ مثلاً) تجعل أول ثلاث جولات بلا مرجع أصلاً.
  const maxApps = Math.max(...rows.map((r) => r.apps));
  const threshold = Math.max(2, Math.round(maxApps * 0.5));

  const regular = rows.filter((r) => r.apps >= threshold);
  const pool = regular.length >= 3 ? regular : rows;
  return Math.max(...pool.map(perGame), 0);
}

/**
 * بند السعر لكل مركز: أرخص ما فيه وأغلى ما فيه.
 *
 * ولماذا لا يشترك المراكز في بندٍ واحد ٤–١٥؟ لأن السقف يجب أن
 * يعكس **ما يستطيع المركز أن يعطيه**، لا ترتيب صاحبه بين أقرانه
 * وحدهم. أفضل حارس في الدوري هو الأفضل بين الحرّاس، لكنه لن يصنع
 * جولةً كما يصنعها مهاجمٌ يسجّل ثلاثة — فسعرهما المتساوي يعني أن
 * من اشترى الحارس دفع ثمن نجمٍ وأخذ حارساً.
 *
 * والبنود هنا تصنع اقتصاد اللعبة: الميزانية ١٠٠ لخمسة عشر، وهذه
 * الأسقف تجعل تشكيلةً متوازنة (حارسان رخيصان، دفاعٌ معقول، نجمٌ
 * أو اثنان في الأمام) ممكنةً بالكاد — وهو بالضبط ما يجعل كل
 * اختيار مؤلماً.
 *
 * والحدّ الأدنى واحدٌ في الجميع: اللاعب الذي لا يلعب لا يساوي
 * شيئاً في أي مركز.
 */
const POSITION_BANDS = {
  Goalkeeper: { min: 4.0, max: 6.5, base: 4.5 },
  Defender: { min: 4.0, max: 8.0, base: 4.5 },
  Midfielder: { min: 4.5, max: 13.0, base: 5.5 },
  Attacker: { min: 4.5, max: 15.0, base: 6.0 },
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
  const band = POSITION_BANDS[position] ?? { min: MIN_PRICE, max: MAX_PRICE, base: 5.0 };

  // أقلّ من مباراة كاملة في الموسم: لا حصيلة يُحكم بها، فيبقى
  // على سعر مركزه. والحكم بعيّنة من عشر دقائق أسوأ من ألا نحكم.
  if (!best || minutes < 90) return round(band.base, band);

  const ratio = Math.max(0, Math.min(1, perGame / best));
  // أسٌّ فوق الواحد لا جذرٌ تحته. جُرّب الجذر أولاً فخرج اللاعب
  // المتوسط بـ١٢٫٠: خمسة عشر مثله = ١٨٠ من ميزانية ١٠٠، أي أن
  // **كل** تشكيلة ممكنة مرفوضة — واللعبة تموت قبل أن تبدأ.
  //
  // والرقم ٢٫١ ليس ذوقاً: الميزانية ١٠٠ لخمسة عشر لاعباً تعني
  // متوسطاً مقصوداً ٦٫٧، فيُضبط الأسّ ليضع من أداؤه نصفُ الأفضل
  // عند ٦٫٥ تقريباً. لو تغيّرت الميزانية وجب أن يتغيّر معها.
  const scaled = Math.pow(ratio, PRICE_CURVE);
  return round(band.min + scaled * (band.max - band.min), band);
}

/** إلى أقرب نصف نقطة: ٧٫٥ لا ٧٫٣ — هكذا تُقرأ الأسعار في كل فانتازي. */
function round(value, band = { min: MIN_PRICE, max: MAX_PRICE }) {
  const clamped = Math.max(band.min, Math.min(band.max, value));
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

  // مرجعٌ **لكل مركز على حدة**، لا مرجعٌ واحد للدوري.
  //
  // جُرّب المرجع الواحد وظهر عيبه في السوق فوراً: كل الحرّاس
  // الجيدين بسقف السعر (١٥)، أغلى من المهاجمين. والسبب بنيوي لا
  // عابر — الحارس يجمع نقاطه **بانتظام** (حضور وشباك نظيفة
  // وتصدّيات في كل مباراة) والمهاجم يجمعها **دفعات** (هدفان في
  // مباراة ثم أربع مباريات صفر)، فمعدّل الحارس أعلى وإن كان أقلّ
  // نفعاً في لعبةٍ تكافئ الأهداف.
  //
  // والأهم أن المقارنة عبر المراكز بلا معنى أصلاً: الخطة تُلزمك
  // بحارس واحد، فأنت تفاضل بين حارسٍ وحارس لا بين حارسٍ ومهاجم.
  // السعر جوابٌ عن «كم يساوي هذا مقارنةً بمن قد يشغل مكانه».
  const bestByPosition = {};
  for (const position of Object.keys(POSITION_BANDS)) {
    bestByPosition[position] = reference(
      rows.filter((r) => r.position === position && r.apps > 0),
      perGame
    );
  }

  const client = await db.pool.connect();
  try {
    await client.query('BEGIN');
    for (const r of rows) {
      const price = priceFor(
        perGame(r),
        bestByPosition[r.position] ?? 0,
        r.position,
        { minutes: r.minutes }
      );
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
    `[pricing] league ${leagueId}: ${rows.length} players — ` +
      Object.entries(bestByPosition)
        .map(([k, v]) => `${k[0]}${v.toFixed(1)}`)
        .join(' ')
  );
  return rows.length;
}

module.exports = {
  priceFor,
  repriceLeague,
  POSITION_BANDS,
  MIN_PRICE,
  MAX_PRICE,
  reference,
};
