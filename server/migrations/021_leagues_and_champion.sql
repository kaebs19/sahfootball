-- 021 — متابعة الدوريات، وتوقّع البطل.
--
-- ═══ متابعة الدوريات ═══
--
-- جدول ربط لا عمود مصفوفة على المستخدم: العلاقة كثير-إلى-كثير
-- فعلاً، والمصفوفة تمنع المفتاح الأجنبي — فدوريٌ يُحذف يترك
-- معرّفه معلّقاً في صفوف المستخدمين بلا أن تعترض القاعدة.
CREATE TABLE user_leagues (
  user_id    UUID NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
  league_id  INTEGER NOT NULL REFERENCES leagues(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, league_id)
);
-- الاتجاه المعاكس مفهرس أيضاً: "من يتابع هذا الدوري؟" سؤال
-- الإشعارات، والمفتاح المركّب لا يخدمه.
CREATE INDEX idx_user_leagues_league ON user_leagues (league_id);

-- ═══ توقّع البطل ═══
--
-- المفتاح (مستخدم، دوري، موسم): توقّع واحد لكل موسم، والموسم
-- الجديد يبدأ نظيفاً بلا تصفير يدوي.
--
-- award مخزّن لا محسوب: هذا جوهر القاعدة. الجائزة تُسعَّر لحظة
-- الاختيار بحسب ما بقي من الموسم، فمن راهن في الجولة الأولى يملك
-- 1000 ومن راهن في العاشرة يملك أقل — ولو حسبناها عند التسوية
-- لتساوى المخاطر والمتربّص، وهو عين ما نمنعه.
--
-- ويعطي التخزين خاصية ثانية: تغيير الرأي يُعيد التسعير بسعر
-- اليوم لا سعر الأمس. فالتردّد يكلّف، وهذا صحيح رياضياً وعادل.
CREATE TABLE champion_picks (
  user_id    UUID NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
  league_id  INTEGER NOT NULL REFERENCES leagues(id) ON DELETE CASCADE,
  season     INTEGER NOT NULL,
  team_id    INTEGER NOT NULL REFERENCES teams(id),
  award      INTEGER NOT NULL CHECK (award >= 0),
  picked_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  settled_at TIMESTAMPTZ,
  points     INTEGER,
  PRIMARY KEY (user_id, league_id, season)
);
-- استعلام التسوية يمرّ على غير المسوّى وحده، وهو أقلية دائمة.
CREATE INDEX idx_champion_unsettled
  ON champion_picks (league_id, season) WHERE settled_at IS NULL;

-- البطل الفعلي حين يُعرف — صفٌّ واحد لكل دوري وموسم.
--
-- جدول مستقل لا عمود على leagues: leagues صفٌّ واحد للدوري عبر
-- المواسم كلها (عمود season فيه يعني "الموسم الجاري")، ووضع
-- البطل فيه يمحو بطل العام الماضي كل صيف.
CREATE TABLE league_champions (
  league_id  INTEGER NOT NULL REFERENCES leagues(id) ON DELETE CASCADE,
  season     INTEGER NOT NULL,
  team_id    INTEGER NOT NULL REFERENCES teams(id),
  decided_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  source     TEXT NOT NULL DEFAULT 'auto' CHECK (source IN ('auto', 'admin')),
  PRIMARY KEY (league_id, season)
);

-- إعدادات الجائزة، لتُعدَّل من اللوحة لا من نشر جديد.
INSERT INTO app_settings (key, value)
VALUES ('champion', '{"max_award":1000}'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- ═══ مصدر واحد لنقاط اللاعب ═══
--
-- صارت النقاط تأتي من مصدرين: المباريات والأبطال. وجمعُهما في كل
-- استعلام على حدة (العرش، ملف اللاعب، مركزه) يعني ثلاث نسخ من
-- نفس القاعدة — وأول مصدر ثالث للنقاط يُضاف يُنسى في إحداها،
-- فيقرأ اللاعب مجموعاً في صفحته وآخر في اللوحة.
--
-- والفرز بـ kind لا بمجرّد الجمع: التعادل في اللوحة يُفضّ بعدد
-- التوقّعات المحتسبة (الأقل توقّعاً بنفس النقاط أدقّ)، ورهان
-- البطل ليس توقّع مباراة فلا يدخل ذلك العدّ.
CREATE VIEW user_settled_points AS
  SELECT user_id, points, settled_at, 'match'::text AS kind
    FROM predictions      WHERE settled_at IS NOT NULL
  UNION ALL
  SELECT user_id, points, settled_at, 'champion'::text
    FROM champion_picks   WHERE settled_at IS NOT NULL;
