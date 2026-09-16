// fantasyRepo — كل تعامل جدولي «فريقي» مع القاعدة.
const db = require('../config/db');
const fantasyMarket = require('../services/fantasyMarket');

// أعمدة اللاعب كما يراها السوق والتشكيلة: اسمٌ واحد جاهز للعرض،
// ونادٍ باسمه لا بمعرّفه — الشاشة لا يجب أن تبحث عن اسم نادٍ
// بطلب ثانٍ لكل لاعب من خمسة عشر.
const MARKET_COLUMNS = `
  p.id AS player_id, p.team_id, p.league_id, p.position,
  COALESCE(p.name_ar, p.name_en) AS name,
  p.photo_url, p.shirt_number, p.price, p.price_delta, p.total_points, p.available,
  COALESCE(t.name_ar, t.name_en) AS team_name,
  t.logo_url AS team_logo
`;

/**
 * سوق اللاعبين: من يجوز شراؤه في هذا الدوري.
 *
 * `available` شرطٌ لا خيار: اللاعبون الذين زُرعوا صفوفاً ناقصة من
 * إحصاء مباراة (راجع playerRepo.upsertFixtureStats) بلا مركز ولا
 * نادٍ، وعرضُهم يعني بطاقةً بلا صورة ترفض كل خانة.
 */
async function market(leagueId, season, { position, teamId, search, limit = 500 } = {}) {
  const { rows } = await db.query(
    `SELECT ${MARKET_COLUMNS}
       FROM players p
       JOIN teams t ON t.id = p.team_id
      WHERE p.league_id = $1 AND p.season = $2 AND p.available
        AND ($3::text IS NULL OR p.position = $3)
        AND ($4::int  IS NULL OR p.team_id = $4)
        AND ($5::text IS NULL OR COALESCE(p.name_ar, p.name_en) ILIKE '%' || $5 || '%')
      ORDER BY p.total_points DESC, p.price DESC, p.id
      LIMIT $6`,
    [leagueId, season, position || null, teamId || null, search || null, limit]
  );
  return rows;
}

/** اللاعبون المطلوبون بمعرّفاتهم — للتحقّق قبل الحفظ. */
async function playersByIds(ids) {
  if (!ids.length) return [];
  const { rows } = await db.query(
    `SELECT ${MARKET_COLUMNS}
       FROM players p LEFT JOIN teams t ON t.id = p.team_id
      WHERE p.id = ANY($1)`,
    [ids]
  );
  return rows;
}

async function findSquad(userId, leagueId, season) {
  const { rows } = await db.query(
    `SELECT s.*,
            COALESCE(t.name_ar, t.name_en) AS club_name,
            t.logo_url AS club_logo,
            (SELECT COUNT(*) FROM fantasy_squad_players sp
              WHERE sp.squad_id = s.id)::int AS player_count
       FROM fantasy_squads s
       LEFT JOIN teams t ON t.id = s.club_team_id
      WHERE s.user_id = $1 AND s.league_id = $2 AND s.season = $3`,
    [userId, leagueId, season]
  );
  return rows[0] ?? null;
}

/**
 * تثبيت النادي وحده — قبل أن يوجد لاعبٌ واحد في التشكيلة.
 *
 * ولماذا صفٌّ في القاعدة لا حالةٌ في التطبيق؟ لأن «فريقي» أول
 * قرار في اللعبة وأبعدها أثراً: منه ثلاثة لاعبين في كل تشكيلة
 * وشعارُه شعارُ الفريق في العرش. وحملُه في ذاكرة الشاشة حتى يكتمل
 * الخمسة عشر يعني أن من اختار ناديه ثم أغلق التطبيق — أو ردّ على
 * رسالة — يعود فيجد شاشة «ابنِ فريقك» كأنه لم يفعل شيئاً.
 *
 * والصفّ الناتج تشكيلةٌ بلا لاعبين: لا تُجمَّد عند الإقفال ولا
 * تظهر في العرش (راجع lockRound و leaderboard) — فهي نيّةٌ لا
 * مشاركة.
 */
async function setClub({ userId, leagueId, season, clubTeamId, budget }) {
  const { rows } = await db.query(
    `INSERT INTO fantasy_squads
       (user_id, league_id, season, club_team_id, budget_left, updated_at)
     VALUES ($1,$2,$3,$4,$5, now())
     ON CONFLICT (user_id, league_id, season) DO UPDATE SET
       club_team_id = EXCLUDED.club_team_id,
       updated_at   = now()
     RETURNING id`,
    [userId, leagueId, season, clubTeamId, budget]
  );
  return rows[0];
}

async function squadPlayers(squadId) {
  const { rows } = await db.query(
    `SELECT sp.player_id, sp.on_bench, sp.bench_order, sp.is_captain,
            sp.is_vice, sp.bought_price, ${MARKET_COLUMNS}
       FROM fantasy_squad_players sp
       JOIN players p ON p.id = sp.player_id
       LEFT JOIN teams t ON t.id = p.team_id
      WHERE sp.squad_id = $1
      ORDER BY sp.on_bench, sp.bench_order,
               CASE p.position WHEN 'Goalkeeper' THEN 0 WHEN 'Defender' THEN 1
                               WHEN 'Midfielder' THEN 2 ELSE 3 END,
               p.id`,
    [squadId]
  );
  return rows;
}

/**
 * ما ستؤول إليه المحفظة لو حُفظت هذه التشكيلة.
 *
 * يُحسب **قبل** التحقّق لا بعده: قاعدة المحفظة لا تُفحص بجمع
 * أسعار اليوم (راجع validateSquad)، بل بحركة بيعٍ وشراء من
 * محفظةٍ قائمة. ومن باع رابحاً يستردّ سعر شرائه ونصف ربحه.
 *
 * ويعيد المبيعين والمشترين كذلك: هما سجلّ الانتقالات الذي تتحرّك
 * به أسعار الأسبوع القادم.
 */
async function planTransaction({ userId, leagueId, season, picks, prices, budget }) {
  const squad = await findSquad(userId, leagueId, season);
  const owned = squad ? await squadPlayers(squad.id) : [];
  const ownedById = new Map(owned.map((p) => [p.player_id, p]));
  const wanted = new Set(picks.map((p) => p.player_id));

  const sold = owned.filter((p) => !wanted.has(p.player_id));
  const bought = picks.filter((p) => !ownedById.has(p.player_id));

  const opening = squad ? Number(squad.budget_left) : budget;
  const proceeds = sold.reduce(
    (sum, p) => sum + fantasyMarket.sellPrice(p.bought_price, p.price), 0);
  const outlay = bought.reduce(
    (sum, p) => sum + Number(prices.get(p.player_id)?.price ?? 0), 0);

  return {
    squad,
    sold,
    bought,
    wallet: Number((opening + proceeds - outlay).toFixed(1)),
  };
}

/**
 * حفظ التشكيلة كاملة — استبدالٌ لا تعديل جزئي.
 *
 * كل حفظ يمسح الخمسة عشر ويكتبهم من جديد داخل معاملة واحدة.
 * أبسط من حساب الفروق، وأهم من ذلك أنه يجعل الحالة الوسيطة
 * مستحيلة: تشكيلةٌ بأربعة عشر لاعباً أو بكابتنين لا توجد ولو
 * للحظة، حتى لو انقطع الاتصال في منتصف الطلب.
 *
 * والسعر يُثبَّت هنا: من كان في التشكيلة يحتفظ بسعر شرائه، ومن
 * دخل الآن يُشترى بسعر اليوم.
 */
async function saveSquad({
  userId, leagueId, season, clubTeamId, formation, name,
  rows, wallet, value, sold = [], bought = [], round = null,
}) {
  const client = await db.pool.connect();
  try {
    await client.query('BEGIN');

    const { rows: squadRows } = await client.query(
      `INSERT INTO fantasy_squads
         (user_id, league_id, season, club_team_id, formation, name,
          budget_left, squad_value, updated_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8, now())
       ON CONFLICT (user_id, league_id, season) DO UPDATE SET
         club_team_id = EXCLUDED.club_team_id,
         formation    = EXCLUDED.formation,
         name         = COALESCE(EXCLUDED.name, fantasy_squads.name),
         budget_left  = EXCLUDED.budget_left,
         squad_value  = EXCLUDED.squad_value,
         updated_at   = now()
       RETURNING *`,
      [userId, leagueId, season, clubTeamId, formation, name || null, wallet, value]
    );
    const squad = squadRows[0];

    // الأسعار المثبّتة قبل المسح: بعده تضيع.
    const { rows: oldRows } = await client.query(
      'SELECT player_id, bought_price FROM fantasy_squad_players WHERE squad_id = $1',
      [squad.id]
    );
    const boughtAt = new Map(oldRows.map((r) => [r.player_id, r.bought_price]));

    await client.query('DELETE FROM fantasy_squad_players WHERE squad_id = $1', [squad.id]);

    for (const r of rows) {
      await client.query(
        `INSERT INTO fantasy_squad_players
           (squad_id, player_id, on_bench, bench_order, is_captain, is_vice, bought_price)
         VALUES ($1,$2,$3,$4,$5,$6,$7)`,
        [squad.id, r.player_id, !!r.on_bench, r.bench_order ?? 0,
         !!r.is_captain, !!r.is_vice, boughtAt.get(r.player_id) ?? r.price]
      );
    }

    // سجلّ الانتقالات: مصدر الطلب الذي تتحرّك به أسعار الأسبوع
    // القادم، وأساس حساب الكلفة عند الإقفال.
    //
    // ON CONFLICT DO NOTHING لا UPDATE: من حفظ تشكيلته خمس مرات
    // في الأسبوع لم ينتقل خمس مرات، ولاعبٌ دخل ثم خرج ثم عاد لم
    // ينتقل أصلاً — السجلّ يقول «حدث هذا الأسبوع» لا كم مرة.
    if (round) {
      for (const p of sold) {
        await client.query(
          `INSERT INTO fantasy_transfers (squad_id, round, player_id, direction, price)
           VALUES ($1,$2,$3,'out',$4) ON CONFLICT DO NOTHING`,
          [squad.id, round, p.player_id, p.price]
        );
      }
      for (const p of bought) {
        await client.query(
          `INSERT INTO fantasy_transfers (squad_id, round, player_id, direction, price)
           VALUES ($1,$2,$3,'in',$4) ON CONFLICT DO NOTHING`,
          [squad.id, round, p.player_id, p.price]
        );
      }
    }

    await client.query('COMMIT');
    return squad;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

// ── الجولة ──────────────────────────────────────────────────────

/**
 * تجميد تشكيلات جولة: نسخةٌ لا تتأثّر بتعديل لاحق.
 *
 * ON CONFLICT DO NOTHING: التجميد يجري مرة واحدة عند أول مباراة،
 * وإعادة النداء بعدها (نبضة ثانية، إعادة تشغيل) يجب ألا تكتب
 * التشكيلة الحالية فوق المجمّدة — وإلا صار التجميد بلا معنى.
 */
async function lockRound(leagueId, season, round, { minPlayers = 15 } = {}) {
  const client = await db.pool.connect();
  try {
    await client.query('BEGIN');
    // التشكيلات الكاملة وحدها. ومن ثبّت ناديه ولم يبنِ بعد له صفٌّ
    // بلا لاعبين (راجع setClub)، وتجميدُه يصنع جولةً فارغة تُسوّى
    // بصفر وتضع صاحبها في العرش بلا أن يلعب.
    const { rows: squads } = await client.query(
      `SELECT s.* FROM fantasy_squads s
        WHERE s.league_id = $1 AND s.season = $2
          AND (SELECT COUNT(*) FROM fantasy_squad_players sp
                WHERE sp.squad_id = s.id) >= $3`,
      [leagueId, season, minPlayers]
    );

    let locked = 0;
    for (const squad of squads) {
      // كلفة الانتقالات تُحسب هنا لا عند الحفظ، ولهذا سببان:
      //
      // الأول أن الحفظ يتكرّر — من عدّل تشكيلته خمس مرات في
      // الأسبوع لم ينتقل خمس مرات، والسجلّ يقول «حدث هذا الأسبوع»
      // لا كم مرة حُفظ.
      //
      // والثاني أن الانتقال لا يصير نهائياً قبل الإقفال: من باع
      // لاعباً ثم أعاده قبل صافرة البداية لم ينتقل شيء.
      const { rows: counted } = await client.query(
        `SELECT COUNT(DISTINCT player_id)::int AS used
           FROM fantasy_transfers
          WHERE squad_id = $1 AND round = $2 AND direction = 'in'`,
        [squad.id, round]
      );
      const used = counted[0]?.used ?? 0;

      const { rows: chip } = await client.query(
        `SELECT 1 FROM fantasy_chips
          WHERE squad_id = $1 AND chip = 'wildcard' AND round = $2`,
        [squad.id, round]
      );
      const wildcard = chip.length > 0;

      // المجانية أولاً ثم الخصم. والوايلد كارد تلغيه كلّه — وهذا
      // كل معناها: إعادة بناء بلا ثمن.
      const free = squad.free_transfers ?? 1;
      const paid = wildcard ? 0 : Math.max(0, used - free);
      const cost = paid * -4;

      const { rows: entry } = await client.query(
        `INSERT INTO fantasy_round_entries
           (squad_id, round, formation, captain_id, vice_id,
            transfers_cost, transfers_used, wildcard)
         SELECT $1, $2, $3,
                (SELECT player_id FROM fantasy_squad_players WHERE squad_id = $1 AND is_captain),
                (SELECT player_id FROM fantasy_squad_players WHERE squad_id = $1 AND is_vice),
                $4, $5, $6
         ON CONFLICT (squad_id, round) DO NOTHING
         RETURNING squad_id`,
        [squad.id, round, squad.formation, cost, used, wildcard]
      );
      if (!entry.length) continue;

      // المجانية للجولة القادمة: ما لم يُستعمل يتراكم حتى خمس.
      // والتراكم هو ما يجعل الصبر خياراً — من لم يحتج انتقالاً
      // هذا الأسبوع يملك اثنين الأسبوع القادم.
      const nextFree = wildcard
        ? 1
        : Math.min(5, Math.max(1, free - Math.min(used, free) + 1));
      await client.query(
        'UPDATE fantasy_squads SET free_transfers = $2 WHERE id = $1',
        [squad.id, nextFree]
      );

      await client.query(
        `INSERT INTO fantasy_round_players (squad_id, round, player_id, on_bench, bench_order)
         SELECT squad_id, $2, player_id, on_bench, bench_order
           FROM fantasy_squad_players WHERE squad_id = $1
         ON CONFLICT DO NOTHING`,
        [squad.id, round]
      );
      locked += 1;
    }
    await client.query('COMMIT');
    return locked;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

/**
 * تفعيل رقاقة. القيد في القاعدة (مفتاح squad+chip+half) لا هنا:
 * مسارٌ ينسى الفحص يعطي صاحبه رقاقتين في نصفٍ واحد.
 */
async function useChip(squadId, chip, round, half) {
  const { rowCount } = await db.query(
    `INSERT INTO fantasy_chips (squad_id, chip, round, half)
     VALUES ($1,$2,$3,$4) ON CONFLICT DO NOTHING`,
    [squadId, chip, round, half]
  );
  return rowCount > 0;
}

/** رقائق تشكيلةٍ المستعملة. */
async function chipsFor(squadId) {
  const { rows } = await db.query(
    'SELECT chip, round, half FROM fantasy_chips WHERE squad_id = $1',
    [squadId]
  );
  return rows;
}

/** كم انتقالاً سُجّل في هذه الجولة — يُعرض قبل الإقفال. */
async function transfersThisRound(squadId, round) {
  const { rows } = await db.query(
    `SELECT COUNT(DISTINCT player_id)::int AS used
       FROM fantasy_transfers
      WHERE squad_id = $1 AND round = $2 AND direction = 'in'`,
    [squadId, round]
  );
  return rows[0]?.used ?? 0;
}

/** مدخلات جولة لم تُسوَّ بعد. */
async function unsettledEntries(round) {
  const { rows } = await db.query(
    `SELECT e.*, s.league_id, s.season, s.user_id
       FROM fantasy_round_entries e
       JOIN fantasy_squads s ON s.id = e.squad_id
      WHERE e.round = $1 AND e.settled_at IS NULL`,
    [round]
  );
  return rows;
}

/**
 * الجولة المجمَّدة بأسماء لاعبيها وأنديتهم — لا بمعرّفاتهم وحدها.
 *
 * ولماذا لا نصل الأسماء من التشكيلة الحالية كما كان؟ لأن من باع
 * لاعباً بعد الجولة يفقد اسمه منها: الصفّ المجمَّد يبقى ويظهر بلا
 * اسم ولا صورة، وهي أول جولةٍ يفتحها بعد انتقالاته. والأسماء من
 * جدول اللاعبين نفسه تبقى ما بقي الصفّ.
 */
async function roundLineupDetailed(squadId, round) {
  const { rows } = await db.query(
    `SELECT rp.player_id, rp.on_bench, rp.bench_order, rp.points,
            rp.multiplier, rp.auto_subbed, rp.lines, ${MARKET_COLUMNS}
       FROM fantasy_round_players rp
       JOIN players p ON p.id = rp.player_id
       LEFT JOIN teams t ON t.id = p.team_id
      WHERE rp.squad_id = $1 AND rp.round = $2
      ORDER BY rp.on_bench, rp.bench_order,
               CASE p.position WHEN 'Goalkeeper' THEN 0 WHEN 'Defender' THEN 1
                               WHEN 'Midfielder' THEN 2 ELSE 3 END,
               p.id`,
    [squadId, round]
  );
  return rows;
}

/**
 * آخر جولةٍ أُقفلت لتشكيلةٍ بعينها — نافذةُ من يشاهد غيرَه.
 *
 * تشكيلة غيرك لا تُرى حيّةً بل مجمَّدةً (راجع FANTASY.md): من رأى
 * تشكيلة المتصدّر قبل صافرة البداية نسخها، فتموت المفاضلة التي
 * هي اللعبة كلها.
 */
async function lastLockedRound(squadId) {
  const { rows } = await db.query(
    `SELECT round FROM fantasy_round_entries
      WHERE squad_id = $1 ORDER BY locked_at DESC LIMIT 1`,
    [squadId]
  );
  return rows[0]?.round ?? null;
}

/** ترتيب تشكيلةٍ في عرش دوريها — رقمٌ واحد بلا جلب العرش كله. */
async function rankOf(squadId, leagueId, season) {
  const { rows } = await db.query(
    `SELECT rank FROM (
       SELECT s.id, RANK() OVER (ORDER BY s.total_points DESC) AS rank
         FROM fantasy_squads s
        WHERE s.league_id = $1 AND s.season = $2
          AND EXISTS (SELECT 1 FROM fantasy_squad_players sp WHERE sp.squad_id = s.id)
     ) r WHERE r.id = $3`,
    [leagueId, season, squadId]
  );
  return rows[0] ? Number(rows[0].rank) : null;
}

/** تشكيلة مستخدمٍ آخر في دوري — للاطّلاع لا للتعديل. */
async function squadOfUser(userId, leagueId, season) {
  const { rows } = await db.query(
    `SELECT s.*, u.display_name, u.avatar_url,
            COALESCE(t.name_ar, t.name_en) AS club_name, t.logo_url AS club_logo
       FROM fantasy_squads s
       JOIN users u ON u.id = s.user_id
       LEFT JOIN teams t ON t.id = s.club_team_id
      WHERE s.user_id = $1 AND s.league_id = $2 AND s.season = $3
        AND EXISTS (SELECT 1 FROM fantasy_squad_players sp WHERE sp.squad_id = s.id)`,
    [userId, leagueId, season]
  );
  return rows[0] ?? null;
}

async function roundLineup(squadId, round) {
  const { rows } = await db.query(
    `SELECT player_id, on_bench, bench_order, points, multiplier, auto_subbed, lines
       FROM fantasy_round_players WHERE squad_id = $1 AND round = $2
      ORDER BY on_bench, bench_order`,
    [squadId, round]
  );
  return rows;
}

/** كتابة نتيجة التسوية: نقاط اللاعبين، ثم مجموع الجولة والموسم. */
async function writeSettlement(squadId, round, rows, totalPoints) {
  const client = await db.pool.connect();
  try {
    await client.query('BEGIN');
    for (const r of rows) {
      await client.query(
        `UPDATE fantasy_round_players
            SET points = $3, multiplier = $4, auto_subbed = $5, lines = $7
          WHERE squad_id = $1 AND round = $2 AND player_id = $6`,
        [squadId, round, r.points, r.multiplier, r.auto_subbed, r.player_id,
         JSON.stringify(r.lines || [])]
      );
    }
    await client.query(
      `UPDATE fantasy_round_entries
          SET points = $3, settled_at = now()
        WHERE squad_id = $1 AND round = $2`,
      [squadId, round, totalPoints]
    );
    // مجموع الموسم يُجمع من الجولات لا يُزاد بالفرق: الجمع يصحّح
    // نفسه لو أُعيدت تسوية جولة، والزيادة تضاعفها بلا أثر ظاهر.
    await client.query(
      `UPDATE fantasy_squads s
          SET total_points = COALESCE((
                SELECT SUM(points + transfers_cost)
                  FROM fantasy_round_entries WHERE squad_id = s.id
              ), 0),
              updated_at = now()
        WHERE s.id = $1`,
      [squadId]
    );
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

/** عرش «فريقي» — مستقلٌّ تماماً عن عرش التوقّعات. */
async function leaderboard(leagueId, season, limit = 100) {
  const { rows } = await db.query(
    `SELECT s.id, s.name, s.total_points, s.user_id,
            u.display_name, u.avatar_url,
            COALESCE(t.name_ar, t.name_en) AS club_name, t.logo_url AS club_logo,
            RANK() OVER (ORDER BY s.total_points DESC) AS rank
       FROM fantasy_squads s
       JOIN users u ON u.id = s.user_id
       LEFT JOIN teams t ON t.id = s.club_team_id
      WHERE s.league_id = $1 AND s.season = $2
        AND EXISTS (SELECT 1 FROM fantasy_squad_players sp WHERE sp.squad_id = s.id)
      ORDER BY s.total_points DESC
      LIMIT $3`,
    [leagueId, season, limit]
  );
  return rows;
}

module.exports = {
  market,
  planTransaction,
  useChip,
  chipsFor,
  transfersThisRound,
  playersByIds,
  findSquad,
  setClub,
  squadPlayers,
  saveSquad,
  lockRound,
  unsettledEntries,
  roundLineup,
  roundLineupDetailed,
  lastLockedRound,
  rankOf,
  squadOfUser,
  writeSettlement,
  leaderboard,
};
