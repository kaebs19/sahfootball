-- 001_init.sql — الجداول الأساسية
--
-- قرار مهم: نستخدم معرّفات API-Football نفسها كمفاتيح أساسية
-- (id بدون SERIAL). لماذا؟
-- المزود يرسل لنا فريقاً id=2939 مثلاً. لو ولّدنا معرّفات خاصة بنا
-- لاحتجنا جدول ربط (mapping) بين معرّفاتنا ومعرّفاتهم في كل مزامنة.
-- استخدام معرّف المزود مباشرة يبسّط المزامنة كثيراً (UPSERT مباشر).
-- ملاحظة: هذا استثناء مقصود من مبدأ العزل — لو غيّرنا المزود يوماً
-- سنحتاج هجرة بيانات على أي حال، وجدول الربط لن يغنينا عنها.

CREATE TABLE IF NOT EXISTS teams (
  id          INTEGER PRIMARY KEY,        -- معرّف الفريق عند المزود
  name_en     TEXT NOT NULL,
  name_ar     TEXT,                       -- NULL الآن، تُملأ من لوحة التحكم لاحقاً
  logo_url    TEXT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS players (
  id          INTEGER PRIMARY KEY,
  team_id     INTEGER REFERENCES teams(id),
  name_en     TEXT NOT NULL,
  name_ar     TEXT,
  photo_url   TEXT,
  position    TEXT,                       -- Goalkeeper / Defender / Midfielder / Attacker
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS fixtures (
  id            INTEGER PRIMARY KEY,      -- معرّف المباراة عند المزود
  league_id     INTEGER NOT NULL,
  season        INTEGER NOT NULL,
  home_team_id  INTEGER NOT NULL REFERENCES teams(id),
  away_team_id  INTEGER NOT NULL REFERENCES teams(id),
  -- TIMESTAMPTZ وليس TIMESTAMP: يخزّن اللحظة بتوقيت UTC دائماً،
  -- والتحويل لتوقيت السعودية مسؤولية التطبيق (iOS) عند العرض.
  kickoff_at    TIMESTAMPTZ NOT NULL,
  -- الحالة بعد التطبيع لقيمنا نحن، وليست رموز المزود الخام.
  -- القيم الممكنة: scheduled, live, finished, postponed, cancelled
  status        TEXT NOT NULL DEFAULT 'scheduled',
  goals_home    INTEGER,                  -- NULL قبل بداية المباراة
  goals_away    INTEGER,
  round         TEXT,                     -- مثال: "Regular Season - 5"
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- أكثر استعلامين سنكررهما: مباريات يوم معيّن، والمباريات القادمة.
-- كلاهما يصفّي على kickoff_at، لذلك نفهرسه.
CREATE INDEX IF NOT EXISTS idx_fixtures_kickoff ON fixtures (kickoff_at);
CREATE INDEX IF NOT EXISTS idx_fixtures_status  ON fixtures (status);

CREATE TABLE IF NOT EXISTS fixture_events (
  -- الأحداث ليس لها معرّف عند المزود، لذلك نولّد نحن معرّفاً.
  -- BIGSERIAL = عدّاد تلقائي (مثل autoincrement).
  id          BIGSERIAL PRIMARY KEY,
  fixture_id  INTEGER NOT NULL REFERENCES fixtures(id) ON DELETE CASCADE,
  type        TEXT NOT NULL,              -- goal, card, substitution, var
  detail      TEXT,                       -- مثال: "Normal Goal", "Yellow Card"
  minute      INTEGER,
  player_id   INTEGER,                    -- بلا REFERENCES: قد يصلنا حدث للاعب لم نزامنه بعد
  assist_id   INTEGER,
  team_id     INTEGER REFERENCES teams(id)
);

CREATE INDEX IF NOT EXISTS idx_events_fixture ON fixture_events (fixture_id);
