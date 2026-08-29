// fixtureMapper — تطبيع بيانات المباريات من شكل المزود إلى شكلنا.
//
// لماذا طبقة mapper منفصلة أصلاً؟
// استجابة API-Football عميقة التداخل ومليئة بحقول لا تهمنا
// (venue، referee، timezone...). لو خزّنّاها كما هي:
//   1. قاعدة بياناتنا تصبح مرآة لقرارات مزوّد خارجي.
//   2. أي تغيير في شكل استجابتهم يكسر كل المشروع، وليس ملفاً واحداً.
//   3. تبديل المزود يعني إعادة كتابة كل شيء.
// الـ mapper هو "الجمارك": البيانات تدخل بلدنا بجواز سفرنا نحن.
//
// شكل عنصر المباراة عند API-Football (مبسّطاً):
// {
//   fixture: { id, date, status: { short: 'NS' | '1H' | 'FT' ..., elapsed: 67 } },
//   league:  { id, season, round },
//   teams:   { home: { id, name, logo }, away: { ... } },
//   goals:   { home: 2, away: 1 }
// }

// المزود يستخدم ~20 رمز حالة تفصيلياً. تطبيقنا لا يحتاج التمييز بين
// "الشوط الأول" و"استراحة" و"وقت إضافي" في مستوى قاعدة البيانات —
// يحتاج فقط: هل المباراة لم تبدأ، جارية، انتهت، مؤجلة، أو ملغاة؟
// نختزل الرموز لخمس حالات خاصة بنا. أما دقيقة اللعب فنأخذها كما هي
// من status.elapsed (انظر أسفل mapFixture) — تبويب "مباشر" يحتاجها.
const STATUS_MAP = {
  // لم تبدأ
  TBD: 'scheduled', // موعدها غير مؤكد بعد
  NS: 'scheduled',  // Not Started

  // جارية
  '1H': 'live', HT: 'live', '2H': 'live',
  ET: 'live',   BT: 'live', P: 'live', // أشواط إضافية، استراحتها، ركلات ترجيح
  LIVE: 'live', INT: 'live',           // INT = متوقفة مؤقتاً (إصابة، طقس...)
  SUSP: 'live',                        // معلّقة وقد تُستأنف

  // انتهت
  FT: 'finished',  // Full Time
  AET: 'finished', // بعد وقت إضافي
  PEN: 'finished', // بعد ركلات ترجيح
  WO: 'finished',  // انسحاب (walkover)
  AWD: 'finished', // نتيجة بقرار إداري

  // لن تُلعب في موعدها
  PST: 'postponed',
  CANC: 'cancelled',
  ABD: 'cancelled', // أُلغيت بعد بدايتها (abandoned)
};

// يحوّل عنصر مباراة واحداً من شكل المزود إلى صف جدول fixtures.
// أسماء الحقول الناتجة تطابق أعمدة الجدول حرفياً — هذا مقصود:
// الـ repository يستطيع تمريرها للاستعلام دون إعادة تسمية.
function mapFixture(apiItem) {
  const { fixture, league, teams, goals } = apiItem;

  const shortStatus = fixture.status?.short;
  const status = STATUS_MAP[shortStatus];
  if (!status) {
    // رمز جديد لا نعرفه: نسجّله كي نضيفه للخريطة، ولا نُفشل المزامنة
    // كلها بسببه — نعتبره scheduled كأسلم افتراض.
    console.warn(`[fixtureMapper] unknown status code "${shortStatus}" for fixture ${fixture.id}`);
  }

  return {
    id: fixture.id,
    league_id: league.id,
    season: league.season,
    home_team_id: teams.home.id,
    away_team_id: teams.away.id,
    // المزود يرسل التاريخ كنص ISO مع المنطقة الزمنية
    // (مثال "2026-08-28T18:00:00+00:00"). نمرره كما هو — عمود
    // TIMESTAMPTZ في PostgreSQL يفهمه ويخزّنه بتوقيت UTC.
    kickoff_at: fixture.date,
    status: status || 'scheduled',
    // ?? وليس ||: قبل المباراة goals تكون null ويجب أن تبقى null،
    // لكن نتيجة 0-0 حقيقية يجب ألا تتحول إلى null. عملياً ?? يحمينا
    // لو أرسل المزود undefined.
    goals_home: goals.home ?? null,
    goals_away: goals.away ?? null,
    // دقيقة اللعب الرسمية. المزود يرسلها null قبل الانطلاق وبعد
    // النهاية، ونمررها null كما هي — العمود nullable لهذا السبب
    // بالضبط (انظر migrations/010).
    elapsed: fixture.status?.elapsed ?? null,
    round: league.round ?? null,
    // الملعب والحكم: كان الـ mapper يرميهما صراحةً حين كان المنتج
    // تطبيق توقّعات فقط. صفحة المباراة على الموقع تسألهما.
    venue_name: fixture.venue?.name ?? null,
    venue_city: fixture.venue?.city ?? null,
    referee: fixture.referee ?? null,
    // نتيجة الشوط الأول. null قبل نهايته لا صفر — نفس منطق goals
    // أعلاه: "0 - 0" لشوط لم ينته يُقرأ تعادلاً لا غياب بيانات.
    ht_home: apiItem.score?.halftime?.home ?? null,
    ht_away: apiItem.score?.halftime?.away ?? null,
    // ركلات الترجيح: null لغير الإقصائية.
    pen_home: apiItem.score?.penalty?.home ?? null,
    pen_away: apiItem.score?.penalty?.away ?? null,
  };
}

// شكل الحدث عند المزود:
// {
//   time:   { elapsed: 55, extra: null },
//   team:   { id, name, logo },
//   player: { id, name },
//   assist: { id, name },        // كلاهما null لو لا يوجد صانع
//   type:   'Goal' | 'Card' | 'subst' | 'Var',
//   detail: 'Normal Goal' | 'Yellow Card' | ...
// }
function mapEvent(apiEvent, fixtureId) {
  return {
    fixture_id: fixtureId,
    // نطبّع النوع لحروف صغيرة موحّدة: المزود غير متسق
    // ('Goal' بحرف كبير لكن 'subst' بحرف صغير).
    type: (apiEvent.type || '').toLowerCase(),
    detail: apiEvent.detail ?? null,
    // time.extra = الوقت بدل الضائع. هدف في 90+3 يصل كـ
    // { elapsed: 90, extra: 3 } — نجمعهما في رقم واحد للتبسيط.
    minute: (apiEvent.time?.elapsed ?? 0) + (apiEvent.time?.extra ?? 0),
    player_id: apiEvent.player?.id ?? null,
    assist_id: apiEvent.assist?.id ?? null,
    team_id: apiEvent.team?.id ?? null,
  };
}

module.exports = { mapFixture, mapEvent, STATUS_MAP };
