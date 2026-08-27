-- 008_user_status.sql — إيقاف الحسابات (الإشراف)
--
-- لماذا عمودان على users بدل جدول "عقوبات" مستقل؟
-- الحالة التي نحتاجها اليوم ثنائية: موقوف أو لا. جدول عقوبات بتاريخ
-- كامل (من أوقف، متى، متى رُفع) يخدم التدقيق لكنه يفرض JOIN على كل
-- طلب محمي — وهذا الفحص سيجري في requireAuth أي في كل طلب تقريباً.
-- عمود على نفس صف المستخدم يبقي الفحص قراءة بمفتاح أساسي واحد.
--
-- suspended_at وليس suspended BOOLEAN: التاريخ يحمل المعلومة نفسها
-- (NULL = حساب سليم) ويضيف "متى" مجاناً — نفس منطق revoked_at في
-- جدول refresh_tokens.
ALTER TABLE users ADD COLUMN IF NOT EXISTS suspended_at TIMESTAMPTZ;

-- السبب اختياري: الأدمن قد يوقف حساباً بسرعة ثم يوثّق لاحقاً.
-- نعرضه للمستخدم في رسالة الرفض عند الدخول، لذلك يُكتب بالعربية
-- وبصيغة يفهمها صاحب الحساب لا بملاحظة داخلية.
ALTER TABLE users ADD COLUMN IF NOT EXISTS suspended_reason TEXT;

-- فهرس جزئي (partial index): يفهرس الصفوف الموقوفة فقط.
-- فحص requireAuth يمر بالمفتاح الأساسي فلا يحتاجه، لكن استعلام
-- اللوحة "أرني الموقوفين" يستفيد منه — وحجمه يساوي عدد الموقوفين
-- (حفنة صفوف) لا عدد المستخدمين.
CREATE INDEX IF NOT EXISTS idx_users_suspended
  ON users (suspended_at) WHERE suspended_at IS NOT NULL;
