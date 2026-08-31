-- 023 — نقاط اللاعب موسومةً بدوريها.
--
-- "من ملك الدوري السعودي؟" سؤال لا تجيبه لوحة واحدة لكل الدوريات:
-- من يتوقّع في ستة دوريات يعلو من يتقن واحداً، لا لأنه أدقّ بل
-- لأنه ألعبُ أكثر. ولوحة كل دوري تُعيد المنافسة إلى ما يقارَن.
--
-- الأعمدة تُضاف في آخر القائمة لا في وسطها: CREATE OR REPLACE
-- VIEW لا يقبل إعادة ترتيب ما كان، ويقبل الزيادة عليه.
CREATE OR REPLACE VIEW user_settled_points AS
  SELECT p.user_id, p.points, p.settled_at, 'match'::text AS kind,
         f.league_id, f.season
    FROM predictions p
    JOIN fixtures f ON f.id = p.fixture_id
   WHERE p.settled_at IS NOT NULL
  UNION ALL
  SELECT c.user_id, c.points, c.settled_at, 'champion'::text,
         c.league_id, c.season
    FROM champion_picks c
   WHERE c.settled_at IS NOT NULL;
