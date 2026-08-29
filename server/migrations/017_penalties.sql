-- 017_penalties.sql — ركلات الترجيح
--
-- في البطولات الإقصائية (دوري أبطال أوروبا وآسيا) تنتهي المباراة
-- بالتعادل ويُحسم التأهل بالركلات. عرض "1 - 1" وحدها صحيح حرفياً
-- ومضلّل تماماً: القارئ يظنها انتهت بلا فائز.
--
-- NULL لغير الإقصائية وللمباريات التي لم تصل الركلات — لا صفر:
-- "0 - 0 ركلات" لمباراة لم تُلعب فيها ركلات معلومة كاذبة.
ALTER TABLE fixtures ADD COLUMN IF NOT EXISTS pen_home INTEGER;
ALTER TABLE fixtures ADD COLUMN IF NOT EXISTS pen_away INTEGER;
