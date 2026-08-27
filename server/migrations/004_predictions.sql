-- 004_predictions.sql — نظام التوقعات والنقاط + إعدادات التطبيق

-- إعدادات عامة تُعدَّل من لوحة التحكم بلا نشر نسخة جديدة.
-- key/value مع JSONB: نضيف إعدادات مستقبلية (مدة قفل التوقع،
-- رسائل إعلانات...) بلا هجرات جديدة. JSONB وليس TEXT حتى يفهم
-- PostgreSQL البنية ويمكن الاستعلام داخلها.
CREATE TABLE IF NOT EXISTS app_settings (
  key        TEXT PRIMARY KEY,
  value      JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- قيم النقاط الافتراضية. ON CONFLICT DO NOTHING: لو عدّلها الأدمن
-- ثم أعيد تشغيل الهجرات لأي سبب، لا نمسح تعديله.
INSERT INTO app_settings (key, value)
VALUES ('scoring', '{"exact": 5, "diff": 3, "outcome": 2}')
ON CONFLICT (key) DO NOTHING;

-- دور المستخدم: 'user' أو 'admin'. عمود بسيط يكفي الآن —
-- جدول أدوار وصلاحيات مستقل ترف لا نحتاجه قبل تعدد أنواع الإدارة.
ALTER TABLE users ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'user';

CREATE TABLE IF NOT EXISTS predictions (
  id          BIGSERIAL PRIMARY KEY,
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  fixture_id  INTEGER NOT NULL REFERENCES fixtures(id) ON DELETE CASCADE,
  pred_home   INTEGER NOT NULL CHECK (pred_home BETWEEN 0 AND 99),
  pred_away   INTEGER NOT NULL CHECK (pred_away BETWEEN 0 AND 99),
  -- NULL = لم تُحتسب بعد (المباراة لم تنته أو الاحتساب لم يجرِ).
  -- بعد الاحتساب: 0 فأكثر. التمييز بين "صفر نقاط" و"لم يُحتسب"
  -- هو سبب اختيار NULL هنا وليس DEFAULT 0.
  points      INTEGER,
  settled_at  TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- توقع واحد لكل مستخدم لكل مباراة — التعديل قبل البداية يحدّث
  -- الصف نفسه (UPSERT) ولا ينشئ ثانياً.
  UNIQUE (user_id, fixture_id)
);

-- الاستعلامان المتكرران: "توقعاتي" و"توقعات مباراة لم تُحتسب".
CREATE INDEX IF NOT EXISTS idx_predictions_user    ON predictions (user_id);
CREATE INDEX IF NOT EXISTS idx_predictions_fixture ON predictions (fixture_id);
