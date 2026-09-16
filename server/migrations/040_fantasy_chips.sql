-- ٠٤٠ — الرقائق: الوايلد كارد وما يأتي بعدها.
--
-- جدولٌ لا عمودان. الوايلد كارد أول الرقائق ولن تكون آخرها
-- (مضاعفة الكابتن، تفعيل الدكّة…)، وكل رقاقةٍ تُضاف بعمودين في
-- fantasy_squads تعني هجرةً جديدة وشيفرةً تفحص عموداً بعينه.
-- وهنا تُضاف بصفّ.
CREATE TABLE IF NOT EXISTS fantasy_chips (
  squad_id   UUID NOT NULL REFERENCES fantasy_squads(id) ON DELETE CASCADE,
  -- 'wildcard' اليوم؛ القيم تتوسّع بلا هجرة.
  chip       TEXT NOT NULL,
  round      TEXT NOT NULL,
  -- نصف الموسم (1 أو 2). الوايلد كارد واحدة لكل نصف، والقيد
  -- أدناه يفرضها في القاعدة لا في الشيفرة: مسارٌ ينسى الفحص
  -- يعطي صاحبه رقاقتين في نصفٍ واحد، وهي أرباح لا يشتكي منها.
  half       SMALLINT NOT NULL CHECK (half IN (1, 2)),
  used_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

  PRIMARY KEY (squad_id, chip, half)
);

-- كلفة الانتقالات تُحسب عند الإقفال وتُخصم من نقاط الجولة.
-- العمود موجود منذ ٠٣٧ (transfers_cost)؛ هذا عدد ما استُعمل،
-- يُعرض للاعب كي يفهم من أين جاء الخصم.
ALTER TABLE fantasy_round_entries
  ADD COLUMN IF NOT EXISTS transfers_used SMALLINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS wildcard BOOLEAN NOT NULL DEFAULT false;
