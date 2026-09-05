-- 035 — المجلس على عدة دوريات لا دوري واحد.
--
-- كان groups.league_id عموداً واحداً: دوري أو NULL = كل الدوريات.
-- طلب محمد (2026-09-06) أن يضيف المشرف دوريات مجلسه واحداً بعد آخر،
-- فصار الدوري علاقة لا عموداً: جدول group_leagues، وصفوفه لمجلسٍ ما
-- هي نطاقه — مبارياته التي تُعرض لأعضائه، والنقاط التي يُرتَّبون بها.
--
-- «لا صفوف» تبقى تعني «كل الدوريات» كما كان NULL يعنيه: المجالس
-- القائمة بلا دوري لا تتغيّر، والمجالس بدوري واحد تُنقل إلى صفّ
-- واحد — لا هجرة مؤلمة ولا سؤال يُطرح على المالك عند أول فتح.
--
-- ON DELETE CASCADE على الدوري لا SET NULL (كما كان في 024): حذف
-- دوري من اللعبة يُسقط صفّه وحده، فيضيق نطاق المجلس أو يعود إلى
-- «كل الدوريات» إن كان الأخير — ولا يُفنى مجلس أصدقاء.
CREATE TABLE IF NOT EXISTS group_leagues (
  group_id  UUID    NOT NULL REFERENCES groups(id)  ON DELETE CASCADE,
  league_id INTEGER NOT NULL REFERENCES leagues(id) ON DELETE CASCADE,
  PRIMARY KEY (group_id, league_id)
);

-- نقل القيمة القائمة قبل حذف العمود. تُعاد الهجرة بأمان: العمود
-- يُفحص قبل القراءة منه، والإدراج يتجاهل المكرّر.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_name = 'groups' AND column_name = 'league_id') THEN
    INSERT INTO group_leagues (group_id, league_id)
    SELECT id, league_id FROM groups WHERE league_id IS NOT NULL
    ON CONFLICT DO NOTHING;

    ALTER TABLE groups DROP COLUMN league_id;
  END IF;
END $$;
