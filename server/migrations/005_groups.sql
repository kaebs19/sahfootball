-- 005_groups.sql — القروبات (الدوريات الخاصة بين الأصدقاء)
--
-- التصميم: جدولان بعلاقة كثير-لكثير كلاسيكية.
-- النقاط لا تُخزن هنا إطلاقاً: ترتيب القروب يُحسب وقت الطلب من
-- جدول predictions نفسه — القروب مجرد "عدسة" على النقاط العامة،
-- فلا يوجد مجموعان منفصلان يمكن أن يختلفا (مصدر حقيقة واحد،
-- نفس مبدأ لوحة الصدارة العامة).

CREATE TABLE IF NOT EXISTS groups (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  -- رمز الدعوة الذي يُشارك في واتساب. UNIQUE لأن الانضمام يتم به.
  invite_code TEXT NOT NULL UNIQUE,
  -- حذف حساب المالك يحذف قروباته (CASCADE) — قرار مقصود:
  -- قروب بلا مالك لا أحد يديره.
  owner_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS group_members (
  group_id  UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
  user_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- المفتاح المركب يمنع الانضمام المكرر على مستوى القاعدة نفسها —
  -- حتى لو أخطأ الكود يوماً، القاعدة ترفض.
  PRIMARY KEY (group_id, user_id)
);

-- استعلام "قروباتي" يبحث بـ user_id، والمفتاح المركب يخدم البحث
-- بـ group_id فقط (العمود الأول) — لذا نفهرس الثاني.
CREATE INDEX IF NOT EXISTS idx_group_members_user ON group_members (user_id);
