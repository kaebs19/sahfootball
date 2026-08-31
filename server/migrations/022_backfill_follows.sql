-- 022 — من هُيِّئ قبل وجود خطوة "دورياتك".
--
-- التهيئة شُحنت أولاً بخطوتين (فريقك ← ابدأ)، ثم أُضيفت خطوة
-- الدوريات. فبقي من مرّ بينهما بفريق مفضّل وبلا متابعة واحدة —
-- وبطاقات "من يرفع الكأس؟" تُبنى على المتابعة، فلا يراها أبداً
-- ولا طريق له إليها: onboarded_at مضبوط فلا تُعرض له /welcome
-- ثانية. ميزةٌ كاملة محجوبة عنه بلا رسالة ولا زر.
--
-- والدوري مشتقٌّ من فريقه بلا سؤال: من اختار الهلال يتابع الدوري
-- السعودي بداهةً. نستنتجه من مبارياته لا من جدول عضوية — لا وجود
-- لذلك الجدول، والمباريات تقوله بدقة أعلى.
INSERT INTO user_leagues (user_id, league_id)
SELECT DISTINCT u.id, f.league_id
  FROM users u
  JOIN fixtures f ON (f.home_team_id = u.favorite_team_id
                   OR f.away_team_id = u.favorite_team_id)
  JOIN leagues l ON l.id = f.league_id AND l.in_app AND f.season = l.season
 WHERE u.favorite_team_id IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM user_leagues ul WHERE ul.user_id = u.id)
ON CONFLICT DO NOTHING;
