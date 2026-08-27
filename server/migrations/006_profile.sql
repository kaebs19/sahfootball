-- 006_profile.sql — الصورة الشخصية والفريق المفضل

-- avatar_url: مسار نسبي مثل "/uploads/ab12….png". نسبي وليس مطلقاً
-- عمداً: لو انتقلنا لدومين أو تخزين سحابي لا نعيد كتابة الصفوف.
ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url TEXT;

-- ON DELETE SET NULL: لو حُذف فريق يوماً (اندماج، هبوط وإزالة)
-- لا نحذف المستخدم معه — يفقد التفضيل فقط.
ALTER TABLE users ADD COLUMN IF NOT EXISTS favorite_team_id INTEGER
  REFERENCES teams(id) ON DELETE SET NULL;
