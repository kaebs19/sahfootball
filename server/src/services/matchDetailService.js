// matchDetailService — كل ما تعرضه صفحة المباراة، بشكل جاهز للعرض.
//
// ثلاثة نداءات مستقلة عند المزوّد (أحداث، إحصاءات، تشكيلات)، وكل
// واحد قد يكون فارغاً لسبب مشروع: التشكيلة لا تُنشر قبل ساعة من
// الانطلاق، والإحصاءات لا توجد قبل صافرة البداية. الفراغ هنا ليس
// عطلاً، ولذلك يُرجَع كقائمة فارغة لا كخطأ — والصفحة تخفي القسم
// بدل أن تعرض "تعذّر الجلب" لشيء لم يُنشر بعد.
//
// وثلاثتها على التوازي: زمنها زمن أبطأها لا مجموعها.
const provider = require('./footballProvider');
const teamRepo = require('../repositories/teamRepo');
const logger = require('../utils/logger');

// ترجمة أسماء الإحصاءات. المزوّد يرسلها بالإنجليزية دائماً.
//
// الترتيب هنا هو ترتيب العرض: الاستحواذ أولاً لأنه أكثر ما يُقرأ،
// ثم التسديدات فالبقية. ما لا يرد في هذه الخريطة يُسقَط عمداً —
// المزوّد يرسل حقولاً كثيرة (expected_goals، passes_%) تزحم الجدول
// بلا أن يقرأها أحد.
const STAT_LABELS = new Map([
  ['Ball Possession', 'الاستحواذ'],
  ['Total Shots', 'التسديدات'],
  ['Shots on Goal', 'على المرمى'],
  ['Corner Kicks', 'الركنيات'],
  ['Fouls', 'الأخطاء'],
  ['Offsides', 'التسلل'],
  ['Yellow Cards', 'بطاقات صفراء'],
  ['Red Cards', 'بطاقات حمراء'],
  ['Total passes', 'التمريرات'],
]);

// أنواع الأحداث التي تُعرض. التبديلات تُعرض في التشكيلة لا في
// الخط الزمني — سردها بينها يغرق الأهداف والبطاقات في ضجيج.
const EVENT_KINDS = new Set(['Goal', 'Card', 'subst']);

function eventKind(e) {
  if (e.type === 'Goal') {
    if (e.detail === 'Own Goal') return { icon: '⚽', label: 'هدف عكسي', cls: 'own' };
    if (e.detail === 'Penalty') return { icon: '⚽', label: 'هدف من ركلة جزاء', cls: 'goal' };
    if (e.detail === 'Missed Penalty') return { icon: '✕', label: 'أضاع ركلة جزاء', cls: 'miss' };
    return { icon: '⚽', label: 'هدف', cls: 'goal' };
  }
  if (e.type === 'Card') {
    return e.detail === 'Red Card'
      ? { icon: '▮', label: 'بطاقة حمراء', cls: 'red' }
      : { icon: '▮', label: 'بطاقة صفراء', cls: 'yellow' };
  }
  return { icon: '⇄', label: 'تبديل', cls: 'subst' };
}

/** أحداث مرتبة زمنياً وجاهزة للعرض. */
function shapeEvents(raw, homeTeamId) {
  return raw
    .filter((e) => EVENT_KINDS.has(e.type))
    .map((e) => ({
      minute: e.time?.elapsed ?? 0,
      extra: e.time?.extra ?? null,
      side: e.team?.id === homeTeamId ? 'home' : 'away',
      player: e.player?.name || '',
      assist: e.assist?.name || null,
      ...eventKind(e),
    }))
    .sort((a, b) => (a.minute + (a.extra || 0)) - (b.minute + (b.extra || 0)));
}

/** إحصاءات مزدوجة: قيمة لكل فريق في صف واحد. */
function shapeStatistics(raw, homeTeamId) {
  if (raw.length < 2) return [];

  const home = raw.find((r) => r.team?.id === homeTeamId);
  const away = raw.find((r) => r.team?.id !== homeTeamId);
  if (!home || !away) return [];

  const valueOf = (side, type) => {
    const found = (side.statistics || []).find((s) => s.type === type);
    return found?.value ?? null;
  };

  const rows = [];
  for (const [type, label] of STAT_LABELS) {
    const h = valueOf(home, type);
    const a = valueOf(away, type);
    // صف بلا قيمة في الطرفين لا يضيف شيئاً.
    if (h === null && a === null) continue;
    rows.push({ label, home: h ?? 0, away: a ?? 0 });
  }
  return rows;
}

/** تشكيلة كل فريق: الخطة والأساسيون. */
function shapeLineups(raw, homeTeamId) {
  const pick = (side) => (side ? {
    formation: side.formation || null,
    coach: side.coach?.name || null,
    starters: (side.startXI || []).map((p) => ({
      number: p.player?.number ?? null,
      name: p.player?.name || '',
      pos: p.player?.pos || '',
    })),
    bench: (side.substitutes || []).map((p) => ({
      number: p.player?.number ?? null,
      name: p.player?.name || '',
    })),
  } : null);

  return {
    home: pick(raw.find((r) => r.team?.id === homeTeamId)),
    away: pick(raw.find((r) => r.team?.id !== homeTeamId)),
  };
}

/**
 * تفاصيل مباراة. لا يرمي أبداً: كل جزء يفشل وحده ويعود فارغاً،
 * فعطل في نداء الإحصاءات لا يمنع عرض الأهداف.
 */
async function get(fixture) {
  const id = fixture.id;
  const homeId = fixture.home_team_id;

  const [events, stats, lineups] = await Promise.all([
    provider.getFixtureEvents(id).catch((e) => { logger.warn('[match] events:', e.message); return []; }),
    provider.getFixtureStatistics(id).catch((e) => { logger.warn('[match] stats:', e.message); return []; }),
    provider.getFixtureLineups(id).catch((e) => { logger.warn('[match] lineups:', e.message); return []; }),
  ]);

  return {
    events: shapeEvents(events, homeId),
    statistics: shapeStatistics(stats, homeId),
    lineups: shapeLineups(lineups, homeId),
  };
}

/**
 * هدافو الدوري بأسماء فرق عربية.
 *
 * أسماء اللاعبين تبقى كما يرسلها المزوّد: ترجمة آلاف الأسماء
 * مستحيلة الصيانة، و"I. Toney" مفهوم لمتابع الكرة بينما ترجمة
 * نصف الأسماء وترك نصفها أسوأ من تركها كلها.
 */
async function topScorers(options) {
  const raw = await provider.getTopScorers(options);
  const teams = await teamRepo.findAll();
  const nameById = new Map(teams.map((t) => [t.id, t.name]));

  return raw.map((row, i) => {
    const stat = row.statistics?.[0] || {};
    return {
      rank: i + 1,
      name: row.player?.name || '',
      photo: row.player?.photo || null,
      team: nameById.get(stat.team?.id) ?? stat.team?.name ?? '',
      teamLogo: stat.team?.logo || null,
      goals: stat.goals?.total ?? 0,
      assists: stat.goals?.assists ?? 0,
      played: stat.games?.appearences ?? 0,
      penalties: stat.penalty?.scored ?? 0,
    };
  });
}

module.exports = { get, topScorers };
