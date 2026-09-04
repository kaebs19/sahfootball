-- 028 — درعٌ يُشترى مرة واحدة، وحزمة مضاعِفات من خمسة.
--
-- الدرع المشترى يختلف عن المكتسب في شيء واحد حاسم: **وقته**.
--
-- المكتسب يُشتقّ من التتابع نفسه (كل خمس إصابات تمنح درعاً)، فهو
-- موجود في اللحظة التي استُحقّ فيها. أما المشترى فيدخل حياة اللاعب
-- لحظة الدفع، ولا يجوز أن يحمي خطأً وقع الشهر الماضي — وهذا ما
-- كان سيحدث لو عُدّ درعاً عادياً: حساب السلسلة يُعاد من أول
-- التاريخ في كل مرة، فيُنفَق الدرع على أقدم خطأ لا على أول خطأ
-- بعد الشراء. لاعبٌ يدفع اليوم فتُصلَّح له سلسلةٌ انكسرت وانتهت.
--
-- ولهذا لا عمود "دروع متبقية" هنا أيضاً: تاريخ الشراء في الدفتر
-- (purchases.created_at) هو كل ما يلزم، وحساب السلسلة يُدخِل الدرع
-- في رصيده حين يبلغ ذلك التاريخ في مروره الزمني. الرصيد المتبقي
-- ناتجُ ذلك المرور لا رقمٌ يُخزَّن ويُنقص باليد.
ALTER TABLE purchases DROP CONSTRAINT IF EXISTS purchases_kind_check;
ALTER TABLE purchases
  ADD CONSTRAINT purchases_kind_check CHECK (kind IN ('crown', 'multiplier', 'shield'));

-- «متى اشترى دروعه؟» سؤال يُسأل مع كل حساب سلسلة؛ الفهرس الحالي
-- على (user_id, kind) يخدمه، ونضيف الترتيب الزمني إليه.
CREATE INDEX IF NOT EXISTS idx_purchases_shield
  ON purchases (user_id, created_at) WHERE kind = 'shield';

-- حزمة المضاعِفات صارت خمسة، وأُضيفت حزمة الدرع.
--
-- jsonb_set لا استبدال كامل: الإعدادات قد تكون عُدّلت من اللوحة
-- (سعر، تفعيل، عدد التعديلات المجانية)، واستبدال الكائن كله يمحو
-- تلك التعديلات بصمت ويعيد الافتراضيات.
UPDATE app_settings
   SET value = jsonb_set(
                 jsonb_set(value, '{multiplier_pack,size}', '5'::jsonb, true),
                 '{shield_pack}',
                 '{
                    "product_id": "com.sahfootball.app.shield.pack",
                    "price": 9,
                    "currency": "SAR",
                    "size": 1
                  }'::jsonb,
                 true
               ),
       updated_at = now()
 WHERE key = 'premium';
