-- 016_fixture_details.sql — الملعب والحكم ونتيجة الشوط الأول
--
-- كان fixtureMapper يرمي venue و referee صراحةً، وتعليقه يشرح
-- السبب: "حقول لا تهمنا". كان قراراً صحيحاً حين كان المنتج تطبيق
-- توقّعات — المتوقّع لا يحتاج اسم الملعب.
--
-- ثم صار للموقع صفحة مباراة، وسؤالها مختلف: أين تُلعب، ومن يحكمها،
-- وكيف انتهى شوطها الأول. هذه هي الحقول التي تفصل صفحة نتيجة عن
-- صفحة إحصاء.
--
-- وكلها تصل في نفس نداء fixtures الذي يجريه المزامن أصلاً، فالإضافة
-- بصفر تكلفة على الحصة — نكفّ عن رميها فحسب.
--
-- الملعب عمودان لا واحد: "Estadio Mendizorrotza — Vitoria-Gasteiz"
-- نص واحد لا يمكن عرض جزء منه على شاشة ضيقة، ولا الفرز بالمدينة.
ALTER TABLE fixtures ADD COLUMN IF NOT EXISTS venue_name TEXT;
ALTER TABLE fixtures ADD COLUMN IF NOT EXISTS venue_city TEXT;
ALTER TABLE fixtures ADD COLUMN IF NOT EXISTS referee    TEXT;

-- نتيجة الشوط الأول. NULL قبل نهايته لا صفر — نفس فخّ goals الذي
-- وقعنا فيه: "0 - 0" لشوط لم ينته يُقرأ تعادلاً لا غياب بيانات.
ALTER TABLE fixtures ADD COLUMN IF NOT EXISTS ht_home INTEGER;
ALTER TABLE fixtures ADD COLUMN IF NOT EXISTS ht_away INTEGER;
