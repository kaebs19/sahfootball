// playerMapper — من شكل API-Football إلى صفوف جداولنا.
//
// نفس فلسفة fixtureMapper: أسماء الحقول الناتجة تطابق أعمدة
// الجدول حرفياً، فيمرّرها المستودع للاستعلام بلا إعادة تسمية،
// ويبقى شكل المزوّد محبوساً في هذا الملف وحده. تغيّر المزوّد
// يوماً = ملفٌ واحد يُعاد كتابته.

// مراكز المزوّد بالإنجليزية إلى قيمنا. نخزّن الإنجليزية نفسها
// (كما في عمود position منذ الهجرة ٠٠١) والترجمة في التطبيق —
// المركز مفتاحُ قواعد لا نصُّ عرض: جدول النقاط يسأل «أهو حارس؟»
// ولا يجوز أن تتوقّف إجابته على لغة.
const POSITIONS = {
  Goalkeeper: 'Goalkeeper',
  Defender: 'Defender',
  Midfielder: 'Midfielder',
  Attacker: 'Attacker',
};

/**
 * قائمة نادٍ واحدة من ردّ `players/squads`.
 *
 * الردّ عنصرٌ واحد فيه { team, players }، لكنه يصل داخل مصفوفة —
 * نقرأ الأول ونتجاهل ما بعده.
 *
 * ومن جاء بمركز لا نعرفه (المزوّد يرسل أحياناً مركزاً فارغاً
 * للاعب حديث الانضمام) يُسقَط: لاعبٌ بلا مركز لا مكان له في
 * تشكيلة، وإدخاله يعني صفّاً يظهر في السوق ويرفض كل خانة.
 */
function mapSquad(response, { leagueId, season }) {
  const first = Array.isArray(response) ? response[0] : null;
  if (!first?.team?.id) return [];

  return (first.players || [])
    .filter((p) => p?.id && POSITIONS[p.position])
    .map((p) => ({
      id: p.id,
      team_id: first.team.id,
      league_id: leagueId,
      season,
      name_en: p.name,
      // المزوّد لا يعطي عربية؛ العمود يبقى NULL ويتدهور العرض
      // للإنجليزية (COALESCE في الاستعلام) حتى تُملأ يدوياً من
      // اللوحة — كما في أسماء الأندية تماماً.
      name_ar: null,
      photo_url: p.photo || null,
      position: POSITIONS[p.position],
      shirt_number: Number.isInteger(p.number) ? p.number : null,
    }));
}

/**
 * إحصاء لاعبي مباراة من ردّ `fixtures/players`.
 *
 * الردّ فريقان، كلٌّ بقائمة لاعبيه، ولكل لاعب مصفوفة
 * `statistics` طولها واحد دائماً (تطول فقط في استعلامات الموسم).
 *
 * @param goalsAgainst خريطة team_id → كم دخل مرماه في هذه
 *   المباراة. تأتي من صفّ المباراة عندنا لا من الردّ، ولهذا
 *   سبب: المزوّد يعطي `goals.conceded` **للحارس وحده**، فلو
 *   اكتفينا به لخرج كل مدافع بشباك نظيفة في كل مباراة — عطلٌ
 *   يبدو كرماً فلا يشتكي منه أحد حتى يُفسد الترتيب كله.
 */
function mapFixturePlayers(response, { fixtureId, goalsAgainst = {}, starterIds = null }) {
  const rows = [];
  for (const side of Array.isArray(response) ? response : []) {
    const teamId = side?.team?.id;
    if (!teamId) continue;

    for (const entry of side.players || []) {
      const playerId = entry?.player?.id;
      const st = entry?.statistics?.[0];
      if (!playerId || !st) continue;

      const minutes = st.games?.minutes ?? 0;
      const isKeeper = st.games?.position === 'G';

      // من لم ينزل الملعب لا صفَّ له: خمسة عشر بديلاً في كل
      // مباراة يعني آلاف الصفوف الفارغة في الموسم، وغياب الصفّ
      // نفسه هو ما يقرأه محرّك النقاط «لم يلعب».
      if (!minutes) continue;

      rows.push({
        fixture_id: fixtureId,
        player_id: playerId,
        team_id: teamId,
        // الاسم والصورة يركبان مع الإحصاء وإن كان مكانهما جدول
        // players: لاعبٌ انضم بعد آخر مزامنة قوائم يظهر في مباراة
        // ولا صفَّ له عندنا، ومفتاح أجنبي يرفض إحصاءه فتسقط
        // المباراة كلها لأجل واحد. المستودع يزرع صفّاً ناقصاً به
        // ثم تُكمله أول مزامنة قوائم.
        player_name: entry.player?.name || 'لاعب',
        player_photo: entry.player?.photo || null,
        minutes,
        // **لا تستعمل `games.substitute` من المزوّد.** مقيسٌ على
        // بيانات حقيقية من دوري روشن (مباراة 1603028): يرسلها
        // `false` لكل لاعب في القائمة — للأساسيين والبدلاء ومن لم
        // ينزل أصلاً. أي أن الحقل لا يحمل معلومة، وقراءته تعطي
        // «الجميع أساسيون» بلا خطأ يكشف ذلك.
        //
        // المصدر الصحيح هو `fixtures/lineups` (getFixtureLineups)،
        // وهو طلبٌ إضافي لكل مباراة. ولأن الراية زينةٌ في بطاقة
        // اللاعب ولا تدخل النقاط — البدلاء في الفانتازي بدلاء
        // **تشكيلتنا** لا بدلاء المدرّب — لا نشتريه إلا حين
        // يطلبه المستدعي بتمرير starterIds.
        started: starterIds ? starterIds.has(playerId) : false,
        goals: st.goals?.total ?? 0,
        assists: st.goals?.assists ?? 0,
        // الحارس من المزوّد مباشرة، وغيره من نتيجة المباراة:
        // كلاهما يجيب «كم دخل مرمى فريقه» بأدقّ ما هو متاح.
        conceded: isKeeper
          ? (st.goals?.conceded ?? 0)
          : (goalsAgainst[teamId] ?? 0),
        saves: st.goals?.saves ?? 0,
        yellow: st.cards?.yellow ?? 0,
        red: st.cards?.red ?? 0,
        // المزوّد لا يفرد عموداً لهدف المرمى الخاطئ في إحصاء
        // اللاعب — يصل حدثاً في fixtures/events. يبقى صفراً هنا
        // ويُصحَّح من الأحداث عند التسوية (المرحلة الثانية).
        own_goals: 0,
        pen_scored: st.penalty?.scored ?? 0,
        pen_missed: st.penalty?.missed ?? 0,
        pen_saved: st.penalty?.saved ?? 0,
        // التقييم نصّ عند المزوّد ("7.2") لا رقم.
        rating: st.games?.rating != null ? Number(st.games.rating) : null,
      });
    }
  }
  return rows;
}

module.exports = { mapSquad, mapFixturePlayers, POSITIONS };
