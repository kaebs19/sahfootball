// fantasySquadService — قواعد التشكيلة: ما يجوز وما لا يجوز.
//
// كل قاعدة في اللعبة مكتوبة هنا مرة واحدة، والمسار حلقةٌ فوقها
// لا نسخةٌ منها (نفس ترتيب predictionService). والسبب أن التطبيق
// سيتحقّق من نفس القواعد ليمنع الضغطة الخاطئة قبل الشبكة — وأي
// قاعدة مكتوبة مرتين تفترق مرتين: واحدة تقبل تشكيلة ترفضها
// الأخرى، فيرى اللاعب زرّاً يعمل ورسالة خطأ بعده.
const fantasyScoring = require('./fantasyScoring');

/** الخطط المسموحة: اسمها → عدد كل خط في الأساسي. */
const FORMATIONS = {
  '4-4-2': { Defender: 4, Midfielder: 4, Attacker: 2 },
  '4-3-3': { Defender: 4, Midfielder: 3, Attacker: 3 },
  '4-5-1': { Defender: 4, Midfielder: 5, Attacker: 1 },
  '3-5-2': { Defender: 3, Midfielder: 5, Attacker: 2 },
  '3-4-3': { Defender: 3, Midfielder: 4, Attacker: 3 },
  '5-3-2': { Defender: 5, Midfielder: 3, Attacker: 2 },
  '5-4-1': { Defender: 5, Midfielder: 4, Attacker: 1 },
};

/**
 * حصص التشكيلة الكاملة (أساسي + بدلاء) بلا نظر إلى الخطة.
 *
 * ثابتةٌ عمداً وإن تغيّرت الخطة: الخطة تعيد توزيع الأساسيين على
 * الخطوط، ولا تغيّر من تملك. ولولا ذلك لصار تغييرُ الخطة شراءَ
 * لاعبين وبيعَهم — وهو التفاف على حدّ الانتقالات.
 */
const SQUAD_QUOTA = {
  Goalkeeper: 2,
  Defender: 5,
  Midfielder: 5,
  Attacker: 3,
};

const RULES = {
  squad_size: 15,
  starters: 11,
  budget: 100.0,
  /** أقلّ عدد من نادي اللاعب نفسه — روح اللعبة. */
  min_from_club: 3,
  /** أكثر عدد من أي نادٍ — يمنع أن تصير التشكيلة نادياً واحداً. */
  max_from_club: 3,
  free_transfers_per_round: 1,
  extra_transfer_cost: -4,
};

class SquadError extends Error {
  constructor(message) {
    super(message);
    this.code = 'FANTASY_RULE';
    this.status = 400;
  }
}

/**
 * تحقّق كامل من تشكيلة مقترحة.
 *
 * @param picks مصفوفة { player_id, on_bench, is_captain, is_vice }
 * @param players خريطة player_id → صفّ اللاعب (المركز، النادي، السعر)
 * @param opts { formation, clubTeamId, leagueId, budget }
 *
 * يرمي عند أول خرق برسالة عربية جاهزة للعرض: اللاعب يقرأ الرسالة
 * لا الرمز، ورسالةٌ مثل "INVALID_SQUAD" تعني شاشةً تقول شيئاً
 * لا يفهمه أحد.
 *
 * ولا يرمي قائمةً بكل الأخطاء: من نسي الكابتن وتجاوز الميزانية
 * يصلح واحداً في كل مرة على أي حال، وقائمةٌ من ستة أسطر تبدو
 * حائطاً لا إرشاداً.
 */
function validateSquad(picks, players, {
  formation,
  clubTeamId,
  leagueId,
  budget = RULES.budget,
  /** ما يبقى في المحفظة بعد هذا الحفظ — null لتخطّي الفحص. */
  wallet = null,
}) {
  const shape = FORMATIONS[formation];
  if (!shape) throw new SquadError('خطة غير معروفة.');

  if (picks.length !== RULES.squad_size) {
    throw new SquadError(`التشكيلة ${RULES.squad_size} لاعباً — عندك ${picks.length}.`);
  }

  const seen = new Set();
  for (const p of picks) {
    if (seen.has(p.player_id)) throw new SquadError('لاعبٌ مكرّر في التشكيلة.');
    seen.add(p.player_id);

    const row = players.get(p.player_id);
    if (!row) throw new SquadError('لاعبٌ غير موجود في السوق.');
    if (row.league_id !== leagueId) {
      throw new SquadError('كل اللاعبين يجب أن يكونوا من نفس الدوري.');
    }
    if (!row.available) throw new SquadError(`${row.name} خارج القائمة الآن.`);
  }

  const rows = picks.map((p) => ({ ...p, ...players.get(p.player_id) }));
  const starters = rows.filter((r) => !r.on_bench);
  const bench = rows.filter((r) => r.on_bench);

  if (starters.length !== RULES.starters) {
    throw new SquadError(`الأساسيون ${RULES.starters} — عندك ${starters.length}.`);
  }

  // ١) حصص التشكيلة كاملة
  for (const [position, quota] of Object.entries(SQUAD_QUOTA)) {
    const have = rows.filter((r) => r.position === position).length;
    if (have !== quota) {
      throw new SquadError(`${arabicPosition(position)}: المطلوب ${quota} وعندك ${have}.`);
    }
  }

  // ٢) الأساسيون حسب الخطة — وحارسٌ واحد دائماً في كل الخطط
  const startingKeepers = starters.filter((r) => r.position === 'Goalkeeper').length;
  if (startingKeepers !== 1) throw new SquadError('حارسٌ واحد في الأساسي.');

  for (const [position, need] of Object.entries(shape)) {
    const have = starters.filter((r) => r.position === position).length;
    if (have !== need) {
      throw new SquadError(`خطة ${formation} تحتاج ${need} ${arabicPosition(position)} في الأساسي — عندك ${have}.`);
    }
  }

  // ٣) الأندية: ثلاثة من ناديك على الأقل، وثلاثة من أي نادٍ كحدّ
  const byClub = new Map();
  for (const r of rows) byClub.set(r.team_id, (byClub.get(r.team_id) || 0) + 1);

  for (const [teamId, count] of byClub) {
    if (count > RULES.max_from_club) {
      const name = rows.find((r) => r.team_id === teamId)?.team_name || 'نادٍ واحد';
      throw new SquadError(`${RULES.max_from_club} لاعبين كحدّ أقصى من ${name} — عندك ${count}.`);
    }
  }

  if (clubTeamId) {
    const fromClub = byClub.get(clubTeamId) || 0;
    if (fromClub < RULES.min_from_club) {
      throw new SquadError(`${RULES.min_from_club} لاعبين على الأقل من فريقك — عندك ${fromClub}.`);
    }
  }

  // ٤) الكابتن ونائبه، وكلاهما من الأساسيين: كابتنٌ على الدكّة
  // لا يلعب فلا يضاعف شيئاً، وهو خطأ صامت يكلّف جولة كاملة.
  const captains = rows.filter((r) => r.is_captain);
  const vices = rows.filter((r) => r.is_vice);
  if (captains.length !== 1) throw new SquadError('اختر كابتناً واحداً.');
  if (vices.length !== 1) throw new SquadError('اختر نائباً واحداً للكابتن.');
  if (captains[0].player_id === vices[0].player_id) {
    throw new SquadError('الكابتن ونائبه لاعبان مختلفان.');
  }
  if (captains[0].on_bench) throw new SquadError('الكابتن من الأساسيين.');
  if (vices[0].on_bench) throw new SquadError('نائب الكابتن من الأساسيين.');

  // ٥) المحفظة — لا «مجموع الأسعار ≤ الميزانية».
  //
  // الفرق جوهري بعد أول أسبوع: السعر يتحرّك، فمن اشترى بـ٧
  // وارتفع لاعبه إلى ٩ يملك تشكيلةً قيمتُها أعلى من ميزانيته
  // الابتدائية — ومقارنةُ مجموع أسعار اليوم بـ١٠٠ ترفض تشكيلته
  // الرابحة وتعاقبه على حسن اختياره.
  //
  // الصحيح: محفظةٌ تُنقَص بالشراء وتُزاد بالبيع، ويُفحص أن تبقى
  // موجبة. والحساب في المستودع لأنه يحتاج أسعار الشراء المحفوظة؛
  // هنا نفحص النتيجة التي يعطيها.
  if (wallet !== null && wallet < -1e-9) {
    throw new SquadError(
      `تنقصك ${Math.abs(wallet).toFixed(1)} — بِع لاعباً أو اختر أرخص.`
    );
  }

  // ترتيب الدكّة: الحارس البديل لا يدخل إلا مكان حارس، فيُستثنى
  // من الترتيب ويُترك آخراً — وهذا ما تفعله كل تطبيقات الفانتازي.
  const orderedBench = [
    ...bench.filter((r) => r.position !== 'Goalkeeper'),
    ...bench.filter((r) => r.position === 'Goalkeeper'),
  ];

  // قيمة التشكيلة بأسعار اليوم — تُعرض بجوار المحفظة، ومجموعهما
  // هو «قيمة فريقك»: الرقم الذي ينمو بالذكاء في السوق.
  const value = rows.reduce((sum, r) => sum + Number(r.price), 0);

  return {
    rows,
    starters,
    bench: orderedBench,
    value: Number(value.toFixed(1)),
    wallet: wallet === null ? Number((budget - value).toFixed(1)) : wallet,
  };
}

function arabicPosition(position) {
  return {
    Goalkeeper: 'حرّاس',
    Defender: 'مدافعين',
    Midfielder: 'لاعبي وسط',
    Attacker: 'مهاجمين',
  }[position] || position;
}

/**
 * تسوية جولة لتشكيلة واحدة: من لعب، من دخل بديلاً، وكم النقاط.
 *
 * @param entry صفّ fantasy_round_entries (الخطة والكابتن المجمَّدان)
 * @param lineup صفوف fantasy_round_players (من كان أساسياً وقتها)
 * @param statsByPlayer خريطة player_id → إحصاؤه في مباريات الجولة
 * @param players خريطة player_id → مركزه
 *
 * التبديل التلقائي: من لم يلعب دقيقة يحلّ محلّه أول بديل **لا
 * يكسر الخطة**. والشرط ليس تفصيلاً: بلا فحص الخطة يدخل مهاجمٌ
 * مكان حارس فتلعب التشكيلة بلا حارس، أو يخرج دفاعٌ من خطة 5-3-2
 * إلى أربعة فتنكسر شروط النظافة التي بُنيت عليها.
 */
function settleRound(entry, lineup, statsByPlayer, players, cfg) {
  const scoring = cfg || fantasyScoring.DEFAULT_FANTASY_SCORING;
  const shape = FORMATIONS[entry.formation] || FORMATIONS['4-4-2'];

  const played = (id) => (statsByPlayer.get(id) || []).some((s) => (s.minutes ?? 0) > 0);
  // النقاط وسطورها معاً: «من أين جاءت؟» سؤالٌ تجيبه الشاشة بلا
  // أن تحسب، وحسابُه مرتين (هنا وفي العميل) هو الطريق إلى شاشةٍ
  // تقول ٩ وخادمٍ يقول ٨.
  const breakdownOf = (id) => {
    const position = players.get(id)?.position;
    const lines = [];
    let points = 0;
    for (const s of statsByPlayer.get(id) || []) {
      const one = fantasyScoring.computePlayerPoints(s, position, scoring);
      points += one.points;
      lines.push(...one.lines);
    }
    return { points, lines };
  };

  const starters = lineup.filter((l) => !l.on_bench);
  const bench = lineup
    .filter((l) => l.on_bench)
    .sort((a, b) => a.bench_order - b.bench_order);

  const active = new Set(starters.filter((s) => played(s.player_id)).map((s) => s.player_id));
  const subbedIn = new Set();

  // الخطة الحالية بعد الغيابات — يُفحص كل بديل مقابلها.
  const countOf = (position, set) =>
    [...set].filter((id) => players.get(id)?.position === position).length;

  for (const missing of starters.filter((s) => !played(s.player_id))) {
    const missingPos = players.get(missing.player_id)?.position;

    const candidate = bench.find((b) => {
      if (subbedIn.has(b.player_id) || !played(b.player_id)) return false;
      const pos = players.get(b.player_id)?.position;
      if (missingPos === 'Goalkeeper') return pos === 'Goalkeeper';
      if (pos === 'Goalkeeper') return false;
      // لا يكسر الخطة: عدد كل خط بعد الإحلال يبقى ضمن المسموح.
      const after = new Set([...active, b.player_id]);
      return countOf(pos, after) <= (shape[pos] ?? 0);
    });

    if (candidate) {
      active.add(candidate.player_id);
      subbedIn.add(candidate.player_id);
    }
  }

  // الكابتن: نائبه يحلّ محلّه إن لم يلعب — وهذا كل معنى النائب.
  let captainId = entry.captain_id;
  if (!active.has(captainId)) captainId = active.has(entry.vice_id) ? entry.vice_id : null;

  const rows = lineup.map((l) => {
    const counts = active.has(l.player_id);
    const { points: base, lines } = counts
      ? breakdownOf(l.player_id)
      : { points: 0, lines: [] };
    const multiplier = counts && l.player_id === captainId ? scoring.captain_multiplier : 1;
    return {
      player_id: l.player_id,
      points: base * multiplier,
      multiplier,
      lines,
      auto_subbed: subbedIn.has(l.player_id),
      // البديل الذي دخل يُحتسب، والأساسي الذي غاب لا — والعمود
      // on_bench يبقى كما جُمّد كي تعرف الشاشة من كان أين.
      on_bench: l.on_bench,
    };
  });

  return {
    rows,
    captain_id: captainId,
    points: rows.reduce((sum, r) => sum + r.points, 0),
  };
}

module.exports = {
  FORMATIONS,
  SQUAD_QUOTA,
  RULES,
  SquadError,
  validateSquad,
  settleRound,
  arabicPosition,
};
