-- 003_apple_signin.sql — دعم تسجيل الدخول عبر Apple
--
-- تغييران على جدول users:
--
-- 1. apple_sub: المعرّف الدائم للمستخدم عند Apple (حقل sub في
--    الـ identity token). ثابت للمستخدم مدى الحياة لتطبيقنا، حتى لو
--    غيّر بريده أو استخدم "إخفاء بريدي". هو مفتاح الربط الحقيقي —
--    البريد قد يتغير، الـ sub لا.
--
-- 2. password_hash يصبح NULLable: مستخدم Apple ليس له كلمة سر
--    عندنا أصلاً، وتوليد كلمة عشوائية وهمية له خدعة تربك المنطق
--    (تفتح باب "دخول بكلمة سر" لا يعرفها أحد). NULL صريح أصدق:
--    "هذا الحساب يدخل عبر Apple فقط".

ALTER TABLE users ALTER COLUMN password_hash DROP NOT NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS apple_sub TEXT UNIQUE;
