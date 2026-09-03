-- 025 — سياسة الانضمام بثلاث حالات، وطلبات الانضمام.
--
-- «عام/خاص» (024) كان سؤالاً بجواب واحد: هل يظهر المجلس للناس؟
-- لكن الظهور والدخول سؤالان: مجلس يظهر للجميع ويدخله أي أحد يمتلئ
-- بالغرباء ويفقد معناه. لذا العمود الجديد يجيب «كيف يُدخَل؟»:
--   code     — بالرمز وحده (لا يظهر في الاستكشاف) — الافتراضي.
--   open     — يظهر ويُدخَل مباشرة.
--   approval — يظهر ويُطلب الانضمام، والمالك أو المشرف يوافق.
-- والرمز يعمل في الحالات الثلاث: من معه الرمز مدعوّ، والدعوة
-- تسبق الموافقة.
--
-- is_public يُحذف لا يُبقى: عمودان لحقيقة واحدة يتباعدان عند أول
-- تحديث ينسى أحدهما. المستودع يشتقّه (join_policy <> 'code') كي
-- تبقى الواجهات التي تقرؤه كما هي.
ALTER TABLE groups
  ADD COLUMN IF NOT EXISTS join_policy TEXT NOT NULL DEFAULT 'code';

UPDATE groups SET join_policy = 'open' WHERE is_public;

ALTER TABLE groups DROP CONSTRAINT IF EXISTS groups_join_policy_check;
ALTER TABLE groups
  ADD CONSTRAINT groups_join_policy_check
  CHECK (join_policy IN ('code', 'open', 'approval'));

DROP INDEX IF EXISTS idx_groups_public;
ALTER TABLE groups DROP COLUMN IF EXISTS is_public;

-- الاستكشاف يبحث فيما ليس بالرمز؛ فهرس جزئي كما كان.
CREATE INDEX IF NOT EXISTS idx_groups_discoverable
  ON groups (created_at DESC) WHERE join_policy <> 'code';

-- طلب الانضمام: صفّ واحد لكل (مجلس، مستخدم). المفتاح المركّب يمنع
-- الطلب المكرر في القاعدة نفسها، والقبول يحذف الصف ويُدخل العضو في
-- معاملة واحدة — لا حالة «مقبول» تُخزَّن: القبول يعني العضوية،
-- والعضوية لها جدولها.
CREATE TABLE IF NOT EXISTS group_join_requests (
  group_id   UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (group_id, user_id)
);

-- «طلباتي المعلّقة» تُسأل بالمستخدم؛ المفتاح يخدم المجلس وحده.
CREATE INDEX IF NOT EXISTS idx_group_join_requests_user
  ON group_join_requests (user_id);
