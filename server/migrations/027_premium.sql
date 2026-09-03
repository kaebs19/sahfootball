-- 027 — التاج الذهبي: اشتراك مدفوع، مشتريات، تعديل التوقّع، ودرع السلسلة.
--
-- أربعة قرارات، لكل واحد سبب يجب ألا يُنسى:
--
-- 1) الاشتراك نافذة زمنية لا علَم منطقي.
--    `premium_until` تنتهي من نفسها: من انتهى اشتراكه أمس يقرأ
--    الخادمُ صفَّه اليوم فيجده غير مشترك، بلا وظيفة دورية تُطفئ
--    أعلاماً. وعمود `is_premium` كان سيحتاج مهمّة مجدولة، وأول مرة
--    تتعطّل فيها يبقى آلاف المشتركين مجاناً — أو يُقطع عن دافعين.
--    NULL = لم يشترك قط، وهو ليس نفس "انتهى" في المعنى لكنه هو
--    نفسه في الأثر، فلا نحتاج عمودين.
--
-- 2) المشتريات دفتر يُضاف إليه ولا يُعدَّل (append-only).
--    الرصيد مشتقّ لا مخزّن — نفس مبدأ المضاعِف في الهجرة 019:
--    الباقي من المضاعِف ×5 = ما اشتراه ناقص ما أنفقه فعلاً في
--    توقّعاته. عمود "رصيد" كان سيحتاج أن يتفق مع الواقع، وأول
--    عملية تُكتب في أحدهما وتفشل في الآخر تعطي لاعباً أدوات وهمية
--    أو تسرق منه أدوات دفع ثمنها.
--
--    و`external_id` فريد لأنه ضمانة عدم التكرار الوحيدة الجادّة:
--    إيصال آبل يصل مرتين (إعادة محاولة من الجهاز، أو إشعار خادم
--    مكرّر من المتجر) وهو نفسه في المرتين. لو حرسنا التكرار
--    بفحص في الكود لكانت بين الفحص والكتابة فجوة تمرّ منها
--    الطلبات المتزامنة — والقاعدة لا فجوة فيها.
--
-- 3) `predictions.edits` عدّاد لأن التعديل صار ميزة تُشترى.
--    ويزيد فقط حين يتغيّر الرقمان فعلاً: تشغيل المضاعِف أو إطفاؤه
--    يمرّ بنفس المسار، ولو عدّه تعديلاً لأنفق اللاعب حقّه في
--    التعديل على ضغطة لم تغيّر توقّعه.
--
-- 4) درع السلسلة لا عمود له إطلاقاً.
--    يُشتقّ من نفس قائمة الإصابات التي تُحسب منها السلسلة (راجع
--    computeStreaks): كل خمس إصابات متتالية تمنح درعاً، والدرع
--    يمتصّ خطأً واحداً. عمودٌ يخزّن "عنده درع" كان سيصير مصدراً
--    ثانياً للحقيقة يخالف السلسلة المعروضة بجانبه في نفس الشاشة.

ALTER TABLE users ADD COLUMN IF NOT EXISTS premium_until TIMESTAMPTZ;

-- "من المشتركون الآن؟" سؤال لوحة التحكم، وفهرس جزئي يخدمه بحجم
-- صغير: المشتركون قلّة من المسجّلين بحكم تعريفهم.
CREATE INDEX IF NOT EXISTS idx_users_premium
  ON users (premium_until DESC) WHERE premium_until IS NOT NULL;

CREATE TABLE IF NOT EXISTS purchases (
  id          BIGSERIAL PRIMARY KEY,
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  -- 'crown'      = شهر اشتراك.
  -- 'multiplier' = حزمة مضاعِفات ×5 (الكمية في quantity).
  kind        TEXT NOT NULL CHECK (kind IN ('crown', 'multiplier')),
  quantity    INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
  -- 'apple' | 'google' | 'manual' (منحة من الأدمن أو تطوير محلي).
  platform    TEXT NOT NULL,
  -- معرّف المعاملة عند المتجر. NULL يُسمح به للمنح اليدوية، وقيد
  -- UNIQUE في postgres يسمح بتكرار NULL — وهو المطلوب بالضبط:
  -- منحتان يدويتان لا تصطدمان، وإيصالان متطابقان يصطدمان.
  external_id TEXT UNIQUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_purchases_user ON purchases (user_id, kind);

-- المضاعِف ×5: أداة تُشترى إلى جانب ×2 المجانية.
--
-- نستبدل القيد بدل توسيعه بـ ALTER: القيود لا تُعدَّل في postgres،
-- وحذفٌ ثم إضافة هو الشكل الوحيد. القيمة 5 من app_settings في
-- الكود، لكن القيد يذكرها صراحةً — القاعدة آخر حارس، وقيمةٌ لا
-- يعرفها القيد تمرّ إليها بلا فحص.
ALTER TABLE predictions DROP CONSTRAINT IF EXISTS predictions_multiplier_allowed;
ALTER TABLE predictions
  ADD CONSTRAINT predictions_multiplier_allowed CHECK (multiplier IN (1, 2, 5));

ALTER TABLE predictions
  ADD COLUMN IF NOT EXISTS edits SMALLINT NOT NULL DEFAULT 0;

-- إعدادات التاج، لتُعدَّل من اللوحة لا من نشر جديد (نفس قرار
-- scoring و multipliers).
--
-- الأسعار هنا للعرض الاحتياطي وحده: المتجر هو صاحب السعر الحقيقي،
-- وآبل تشترط عرض سعره هو لا سعراً نكتبه نحن. حين تُوصَل المشتريات
-- داخل التطبيق يقرأ العميل السعر من المتجر ويتجاهل هذه القيمة —
-- وتبقى هي لمن لا يصل إليه المتجر (الموقع، أو قبل التحميل).
INSERT INTO app_settings (key, value)
VALUES ('premium', '{
  "enabled": true,
  "crown": {
    "product_id": "com.sahfootball.app.crown.monthly",
    "price": 19,
    "currency": "SAR",
    "days": 30,
    "monthly_boosters": 3
  },
  "multiplier_pack": {
    "product_id": "com.sahfootball.app.multiplier5.pack",
    "price": 15,
    "currency": "SAR",
    "factor": 5,
    "size": 3
  },
  "free_edits": 0,
  "shield": { "every": 5, "max": 1, "premium_start": 1 },
  "ads": { "enabled": true }
}'::jsonb)
ON CONFLICT (key) DO NOTHING;
