-- ٠٣٦ — لاعبو الأندية وإحصاؤهم في كل مباراة.
--
-- المرحلة الأولى من «فريقي» (راجع FANTASY.md): البيانات قبل
-- اللعبة. جدول players موجود منذ الهجرة ٠٠١ وفارغ منذ ذلك اليوم
-- لأن لا شيء كان يكتب فيه — والفانتازي كلها تقف عليه.

-- ── قوائم الأندية ───────────────────────────────────────────────
--
-- الدوري والموسم على اللاعب لا على ناديه: النادي قد يلعب دوريين
-- في سنة واحدة (الدوري وكأس آسيا)، وقائمة الفانتازي قائمة دوري
-- بعينه في موسم بعينه. وبلا هذين العمودين يستحيل أن نعرف من كان
-- في القائمة الموسم الماضي.
ALTER TABLE players
  ADD COLUMN IF NOT EXISTS league_id    INTEGER REFERENCES leagues(id),
  ADD COLUMN IF NOT EXISTS season       INTEGER,
  ADD COLUMN IF NOT EXISTS shirt_number INTEGER,
  -- السعر بخانة عشرية واحدة كما في كل تطبيقات الفانتازي (٧٫٥)،
  -- و NUMERIC لا FLOAT: مجموع أسعار خمسة عشر لاعباً يُقارن
  -- بميزانية ثابتة، وفاصلة عائمة تجعل ٩٩٫٩٩٩٩٩٩ ترفض تشكيلة
  -- صحيحة بلا أن يفهم صاحبها لماذا.
  ADD COLUMN IF NOT EXISTS price        NUMERIC(4,1) NOT NULL DEFAULT 5.0,
  -- حصيلة الموسم — تُحدَّث عند تسوية كل جولة. مخزّنة لا محسوبة:
  -- سوق اللاعبين يرتّب بها في كل فتحة، وجمعها من جدول الإحصاء
  -- لكل لاعب في كل مرة استعلامٌ ثقيل بلا سبب.
  ADD COLUMN IF NOT EXISTS total_points INTEGER NOT NULL DEFAULT 0,
  -- خارج القائمة: إصابة طويلة أو انتقال. يبقى الصفّ لأن تشكيلات
  -- سابقة تشير إليه، لكنه لا يُعرض في السوق.
  ADD COLUMN IF NOT EXISTS available    BOOLEAN NOT NULL DEFAULT true;

-- السوق يفتح دائماً على «لاعبي هذا الدوري في هذا الموسم»، وهو
-- أكثر استعلام يتكرر في اللعبة كلها.
CREATE INDEX IF NOT EXISTS idx_players_league_season
  ON players (league_id, season) WHERE available;

CREATE INDEX IF NOT EXISTS idx_players_team ON players (team_id);

-- ── إحصاء اللاعب في مباراة ──────────────────────────────────────
--
-- صفٌّ لكل لاعب شارك في كل مباراة. هذا مصدر الحقيقة الوحيد
-- لنقاط الفانتازي: كل نقطة في اللعبة تُشتقّ من صفّ هنا، فيمكن
-- دائماً أن نجيب «من أين جاءت هذه النقطة؟» بصفّ واحد.
--
-- والأعمدة أحداثٌ خام لا نقاط: النقاط تُحتسب منها بجدول قابل
-- للتعديل من اللوحة (راجع FANTASY.md)، فتعديل قيمة الهدف من ٤
-- إلى ٥ يعيد حساب الماضي بلا إعادة شراء البيانات من المزوّد.
CREATE TABLE IF NOT EXISTS player_fixture_stats (
  fixture_id  INTEGER NOT NULL REFERENCES fixtures(id) ON DELETE CASCADE,
  player_id   INTEGER NOT NULL REFERENCES players(id)  ON DELETE CASCADE,
  team_id     INTEGER REFERENCES teams(id),

  -- الدقائق أولاً لأنها البوابة: من لم يلعب دقيقة لا ينال شيئاً،
  -- ويحلّ محلّه بديلٌ من دكّة صاحبه.
  minutes     INTEGER NOT NULL DEFAULT 0,
  started     BOOLEAN NOT NULL DEFAULT false,

  goals       INTEGER NOT NULL DEFAULT 0,
  assists     INTEGER NOT NULL DEFAULT 0,
  -- ما دخل مرمى فريقه وهو في الملعب — لا نتيجة المباراة: من نزل
  -- في الدقيقة ٨٠ والنتيجة ٣-٠ لا يُحاسب على الثلاثة.
  conceded    INTEGER NOT NULL DEFAULT 0,
  saves       INTEGER NOT NULL DEFAULT 0,
  yellow      INTEGER NOT NULL DEFAULT 0,
  red         INTEGER NOT NULL DEFAULT 0,
  own_goals   INTEGER NOT NULL DEFAULT 0,
  pen_scored  INTEGER NOT NULL DEFAULT 0,
  pen_missed  INTEGER NOT NULL DEFAULT 0,
  pen_saved   INTEGER NOT NULL DEFAULT 0,

  -- تقييم المزوّد (٠–١٠). لا يدخل النقاط — رأيٌ لا حدث — لكنه
  -- يُعرض في بطاقة اللاعب ويُستأنس به في التسعير.
  rating      NUMERIC(3,1),

  -- النقاط المحسوبة بجدول وقتِها. مخزّنة كي تبقى شاشة «نقاط
  -- الجولة» ثابتة بعد أشهر حتى لو عُدّل الجدول لاحقاً.
  points      INTEGER NOT NULL DEFAULT 0,

  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- مفتاح مركّب لا id مستقل: لا معنى لصفّين لنفس اللاعب في نفس
  -- المباراة، والنبضة المباشرة تعيد كتابة الصفّ عشرات المرات
  -- أثناء اللعب (ON CONFLICT يحتاج هذا المفتاح).
  PRIMARY KEY (fixture_id, player_id)
);

-- «كم جمع هذا اللاعب هذا الموسم؟» و«نقاط تشكيلتي في هذه الجولة؟»
-- كلاهما يبدأ من اللاعب لا من المباراة.
CREATE INDEX IF NOT EXISTS idx_player_stats_player
  ON player_fixture_stats (player_id);
