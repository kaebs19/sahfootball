-- 024 — المجلس يصير عاماً أو خاصاً، له دوري، ولأعضائه أدوار.
--
-- ثلاثة قرارات صغيرة كل واحد له سبب:
--
-- 1) is_public عمودٌ لا جدولٌ ثانٍ: المجلس العام هو المجلس نفسه
--    برمز دعوة وترتيب وأعضاء، والفرق الوحيد أنه يظهر في الاستكشاف
--    ويُدخَل بلا رمز. جدولان لشيء واحد يعني نسختين من كل استعلام.
--
-- 2) league_id فارغ = كل الدوريات. المجلس المقيّد بدوري يُرتَّب
--    أعضاؤه بنقاط ذلك الدوري وحدها — نفس قرار عرش الدوري: من يلعب
--    في ستة دوريات لا يعلو من يتقن واحداً. ON DELETE SET NULL لا
--    CASCADE: حذف دوري من اللعبة لا يبرّر إفناء مجلس أصدقاء —
--    يعود مجلساً عاماً بكل الدوريات.
--
-- 3) الدور في group_members لا في جدول ثالث، والمالك ليس دوراً
--    هنا: المالك هو groups.owner_id كما كان، فمصدر «من المالك؟»
--    يبقى واحداً ولا يحتاج مزامنة. المشرف دورٌ يمنحه المالك: يضيف
--    ويزيل الأعضاء ولا يحذف المجلس ولا يمسّ المشرفين.
ALTER TABLE groups
  ADD COLUMN IF NOT EXISTS is_public BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS league_id INTEGER REFERENCES leagues(id) ON DELETE SET NULL;

ALTER TABLE group_members
  ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'member';

-- القيد في القاعدة لا في الكود وحده: قيمة دور مجهولة تُرفض عند
-- الكتابة بدل أن تمرّ وتُقرأ يوماً «عضواً عادياً» بصمت.
ALTER TABLE group_members
  DROP CONSTRAINT IF EXISTS group_members_role_check;
ALTER TABLE group_members
  ADD CONSTRAINT group_members_role_check CHECK (role IN ('member', 'moderator'));

-- الاستكشاف يبحث في العامة وحدها؛ فهرس جزئي يخدم ذلك الاستعلام
-- دون أن يثقل الإدخال على الخاصة (الأغلبية المتوقعة).
CREATE INDEX IF NOT EXISTS idx_groups_public
  ON groups (created_at DESC) WHERE is_public;
