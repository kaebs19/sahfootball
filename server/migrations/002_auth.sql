-- 002_auth.sql — جداول المصادقة
--
-- لماذا UUID للمستخدمين بينما بقية الجداول INTEGER؟
-- معرّفات الفرق والمباريات جاءت من المزود (INTEGER عنده). المستخدمون
-- ملكنا نحن، والـ UUID أنسب لهم: لا يكشف عدد المستخدمين (id=17 يخبر
-- المنافس أن عندك 17 مستخدماً)، ولا يمكن تخمين معرّفات الآخرين
-- بالتجربة المتسلسلة. gen_random_uuid() مدمجة في PostgreSQL 13+.

CREATE TABLE IF NOT EXISTS users (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- نخزن البريد بحروف صغيرة دائماً (التطبيع في الكود قبل الإدخال)
  -- حتى لا يسجل Ali@x.com و ali@x.com كحسابين مختلفين.
  email         TEXT NOT NULL UNIQUE,
  -- hash فقط — كلمة السر الأصلية لا تُخزن في أي مكان أبداً.
  password_hash TEXT NOT NULL,
  display_name  TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- جلسات التجديد (refresh tokens).
--
-- لماذا جدول في القاعدة وليس Redis؟ الجلسة عمرها 30 يوماً — بيانات
-- يجب أن تنجو من إعادة تشغيل Redis. ولماذا نخزن hash التوكن وليس
-- التوكن نفسه؟ نفس منطق كلمات السر: لو سُرّب dump من القاعدة،
-- لا يستطيع أحد استعمال الصفوف لانتحال الجلسات.
CREATE TABLE IF NOT EXISTS refresh_tokens (
  id         BIGSERIAL PRIMARY KEY,
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- NULL = الجلسة حية. عند تسجيل الخروج أو تدوير التوكن نضع الوقت
  -- هنا بدل حذف الصف — يبقى أثر للتدقيق (متى ومن أي جلسة خرج).
  revoked_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user ON refresh_tokens (user_id);
