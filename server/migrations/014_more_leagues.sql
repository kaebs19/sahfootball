-- 014_more_leagues.sql — دوريات الموقع العام، وفصلها عن لعبة التطبيق
--
-- الموقع العام يعرض مباريات ونتائج ثماني بطولات كبرى. التطبيق لعبة
-- توقّعات حول دوري روشن. الحاجتان مختلفتان، وكان عمود enabled
-- الوحيد يخدمهما معاً — فتفعيل دوري لعرضه على الموقع كان يعني
-- إقحامه في اللعبة أيضاً.
--
-- أثر ذلك ليس نظرياً: المستخدم يفتح التطبيق فيجد ثمانين مباراة
-- بدل عشر، ويصله تذكير يقول "ما توقّعت لـ63 مباراة" — وهو إشعار
-- يوقفه المستخدم فوراً، وإيقافه في iOS شبه نهائي.
--
-- لذلك عمودان بمعنيين منفصلين:
--   enabled — نزامن هذا الدوري ونعرضه على الموقع.
--   in_app  — يظهر في التطبيق ويُتوقَّع عليه ويدخل في النقاط.
--
-- والعلاقة بينهما اتجاه واحد: لا معنى لـ in_app بلا enabled، لأن
-- ما لا يُزامَن لا توجد مبارياته أصلاً. القيد أدناه يفرض ذلك بدل
-- أن يبقى عرفاً يُنسى.
ALTER TABLE leagues ADD COLUMN IF NOT EXISTS in_app BOOLEAN NOT NULL DEFAULT false;

-- الدوري السعودي هو اللعبة اليوم — يبقى وحده داخل التطبيق.
UPDATE leagues SET in_app = true WHERE id = 307;

ALTER TABLE leagues DROP CONSTRAINT IF EXISTS leagues_in_app_needs_enabled;
ALTER TABLE leagues ADD CONSTRAINT leagues_in_app_needs_enabled
  CHECK (NOT in_app OR enabled);

-- ── البطولات الثماني ─────────────────────────────────────────────
--
-- المعرّفات مقروءة من المزوّد لا مخمّنة: "Premier League" وحدها
-- يحملها أكثر من عشرين اتحاداً (ناميبيا، باكستان، بليز…)، و"دوري
-- أبطال آسيا" صار اسمه AFC Champions League Elite بمعرّف 17.
--
-- الموسم 2026 هو الجاري لكل الثمانية، مؤكَّداً من نداء /leagues.
--
-- الترتيب يتبع القارئ السعودي: دوريه أولاً، ثم البطولتان اللتان
-- تلعب فيهما أنديته، ثم الدوريات الأوروبية الخمسة.
INSERT INTO leagues (id, name_en, name_ar, country, season, enabled, in_app, sort_order)
VALUES
  (2,   'UEFA Champions League',      'دوري أبطال أوروبا',      'أوروبا',   2026, true, false, 1),
  (17,  'AFC Champions League Elite', 'دوري أبطال آسيا',        'آسيا',     2026, true, false, 2),
  (39,  'Premier League',             'الدوري الإنجليزي',       'إنجلترا',  2026, true, false, 3),
  (140, 'La Liga',                    'الدوري الإسباني',        'إسبانيا',  2026, true, false, 4),
  (135, 'Serie A',                    'الدوري الإيطالي',        'إيطاليا',  2026, true, false, 5),
  (78,  'Bundesliga',                 'الدوري الألماني',        'ألمانيا',  2026, true, false, 6),
  (61,  'Ligue 1',                    'الدوري الفرنسي',         'فرنسا',    2026, true, false, 7)
ON CONFLICT (id) DO NOTHING;

-- الدوري السعودي أولاً في الترتيب مهما كانت قيمته السابقة.
UPDATE leagues SET sort_order = 0 WHERE id = 307;
