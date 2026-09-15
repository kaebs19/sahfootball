-- ٠٣٧ — تشكيلات «فريقي».
--
-- المرحلة الثالثة (راجع FANTASY.md). أربعة جداول، وثنائيتها هي
-- كل الفكرة: التشكيلة **الحيّة** يملكها اللاعب ويعدّلها متى شاء،
-- ونسخةٌ **مجمّدة** منها لكل جولة عند الإقفال.
--
-- ولماذا النسخة؟ لأن اللعبة موسمية: من بدّل كابتنه بعد المباراة
-- الأولى لأنه أُصيب سيأخذ نقاط الكابتن الجديد على مباراةٍ لُعبت
-- قبل التبديل. التجميد يجعل الجولة تُحتسب بما كان لا بما صار.

-- ── التشكيلة الحيّة ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS fantasy_squads (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  league_id    INTEGER NOT NULL REFERENCES leagues(id),
  season       INTEGER NOT NULL,

  name         TEXT,

  -- «فريقي»: النادي الذي يشجّعه. منه ثلاثة لاعبين على الأقل،
  -- وهو ما يميّز اللعبة عن كل فانتازي آخر.
  club_team_id INTEGER REFERENCES teams(id),

  formation    TEXT NOT NULL DEFAULT '4-4-2',

  -- المتبقّي من الميزانية. مخزّن لا محسوب: السعر يُثبَّت عند
  -- الشراء (bought_price أدناه)، فجمع أسعار اليوم يعطي رقماً
  -- آخر غير الذي أنفقه صاحبه.
  budget_left  NUMERIC(5,1) NOT NULL DEFAULT 100.0,

  free_transfers INTEGER NOT NULL DEFAULT 1,
  total_points   INTEGER NOT NULL DEFAULT 0,

  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- تشكيلة واحدة لكل لاعب في كل دوري وموسم: «فريقي» فريقٌ واحد،
  -- وتعدّدها يعني أن من خسر جولة ينشئ غيرها ويُخفي الخسارة.
  UNIQUE (user_id, league_id, season)
);

CREATE INDEX IF NOT EXISTS idx_fantasy_squads_league
  ON fantasy_squads (league_id, season, total_points DESC);

-- ── لاعبو التشكيلة ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS fantasy_squad_players (
  squad_id    UUID    NOT NULL REFERENCES fantasy_squads(id) ON DELETE CASCADE,
  player_id   INTEGER NOT NULL REFERENCES players(id),

  on_bench    BOOLEAN NOT NULL DEFAULT false,
  -- ترتيب دخول البدلاء. للأساسيين لا معنى له ويبقى صفراً.
  bench_order SMALLINT NOT NULL DEFAULT 0,

  is_captain  BOOLEAN NOT NULL DEFAULT false,
  is_vice     BOOLEAN NOT NULL DEFAULT false,

  -- السعر يوم الشراء. من اشترى بـ٧٫٠ ثم ارتفع اللاعب لا يُطالَب
  -- بالفرق — وهذا ما يجعل اكتشاف لاعب قبل الناس مكسباً.
  bought_price NUMERIC(4,1) NOT NULL,

  PRIMARY KEY (squad_id, player_id)
);

-- كابتن واحد ونائب واحد لكل تشكيلة — بالقاعدة لا بانضباط الشيفرة:
-- مسارٌ واحد ينسى تصفير القديم يعطي صاحبه كابتنين، وهي أرباح
-- مضاعفة لا يشتكي منها أحد فلا تُكتشف.
CREATE UNIQUE INDEX IF NOT EXISTS idx_fantasy_one_captain
  ON fantasy_squad_players (squad_id) WHERE is_captain;
CREATE UNIQUE INDEX IF NOT EXISTS idx_fantasy_one_vice
  ON fantasy_squad_players (squad_id) WHERE is_vice;

-- ── الجولة المجمَّدة ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS fantasy_round_entries (
  squad_id       UUID NOT NULL REFERENCES fantasy_squads(id) ON DELETE CASCADE,
  round          TEXT NOT NULL,

  formation      TEXT NOT NULL,
  captain_id     INTEGER REFERENCES players(id),
  vice_id        INTEGER REFERENCES players(id),

  points         INTEGER NOT NULL DEFAULT 0,
  -- عقوبة الانتقالات الزائدة (سالبة). منفصلة عن النقاط كي تقول
  -- الشاشة «٥٤ نقطة، −٤ انتقالات» بدل رقمٍ واحد لا يُفسَّر.
  transfers_cost INTEGER NOT NULL DEFAULT 0,

  locked_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  settled_at     TIMESTAMPTZ,

  PRIMARY KEY (squad_id, round)
);

CREATE TABLE IF NOT EXISTS fantasy_round_players (
  squad_id    UUID    NOT NULL REFERENCES fantasy_squads(id) ON DELETE CASCADE,
  round       TEXT    NOT NULL,
  player_id   INTEGER NOT NULL REFERENCES players(id),

  on_bench    BOOLEAN NOT NULL DEFAULT false,
  bench_order SMALLINT NOT NULL DEFAULT 0,

  -- نقاط اللاعب في هذه الجولة بعد التسوية، ومضاعِفه (٢ للكابتن،
  -- ١ لغيره). مخزّنان كي تبقى شاشة الجولة ثابتة بعد أشهر حتى لو
  -- عُدّل جدول النقاط من اللوحة.
  points      INTEGER NOT NULL DEFAULT 0,
  multiplier  SMALLINT NOT NULL DEFAULT 1,
  -- دخل بديلاً مكان أساسيٍّ لم يلعب.
  auto_subbed BOOLEAN NOT NULL DEFAULT false,

  PRIMARY KEY (squad_id, round, player_id)
);
