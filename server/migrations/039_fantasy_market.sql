-- ٠٣٩ — السوق الحيّ: محفظة، وانتقالات، وأسعار تتحرّك، وتفصيل نقاط.
--
-- ما قبل هذه الهجرة كان سوقاً ساكناً: سعرٌ يُحتسب مرة، وميزانيةٌ
-- تُجمع من أسعار اليوم، ونقاطٌ تصل رقماً بلا تفسير. وهذه الثلاثة
-- هي ما يفصل لعبةً تُلعب أسبوعاً عن لعبةٍ تُلعب موسماً.

-- ── حركة السعر ──────────────────────────────────────────────────
ALTER TABLE players
  -- السعر الابتدائي: مرجع «كم تحرّك هذا اللاعب منذ الإطلاق»،
  -- وبه يُحسب سقف الموسم. بلا حفظه لا سبيل لمعرفة أين بدأ.
  ADD COLUMN IF NOT EXISTS start_price   NUMERIC(4,1),
  -- حركة آخر جولة — هي وحدها ما يُعرض بشارة ▲/▼.
  ADD COLUMN IF NOT EXISTS price_delta   NUMERIC(3,1) NOT NULL DEFAULT 0,
  -- مجموع الحركة في الموسم. مخزّن لا محسوب من start_price لأن
  -- السقف (±٣) يجب أن يُفحص قبل الكتابة لا بعدها.
  ADD COLUMN IF NOT EXISTS season_delta  NUMERIC(3,1) NOT NULL DEFAULT 0;

-- من كان له سعر ولا بداية له: اليوم هو بدايته.
UPDATE players SET start_price = price WHERE start_price IS NULL;

-- ── المحفظة والرقائق ────────────────────────────────────────────
ALTER TABLE fantasy_squads
  -- كم وايلد كارد استُعملت. مرتان في الموسم — واحدة لكل نصف.
  ADD COLUMN IF NOT EXISTS wildcards_used SMALLINT NOT NULL DEFAULT 0,
  -- الوايلد كارد الجارية: الجولة التي تُلغى فيها كلفة الانتقالات.
  -- تُخزَّن باسم الجولة لا براية صحيحة/خاطئة كي لا تبقى مفتوحة
  -- إلى الأبد إن فشل ما يُغلقها.
  ADD COLUMN IF NOT EXISTS wildcard_round TEXT,
  -- قيمة اللاعبين وقت آخر حفظ — «قيمة فريقك» = هذه + المحفظة.
  ADD COLUMN IF NOT EXISTS squad_value NUMERIC(6,1) NOT NULL DEFAULT 0;

-- ── سجلّ الانتقالات ─────────────────────────────────────────────
--
-- مصدر **الطلب** الذي تتحرّك به الأسعار: كم مدرّباً اشترى هذا
-- اللاعب هذا الأسبوع وكم باعه. وبلا سجلّ لا سبيل لمعرفة ذلك —
-- مقارنة التشكيلات قبل وبعد تقول «من فيها الآن» لا «من دخلها».
--
-- وهو أيضاً ما يجعل حساب الكلفة قابلاً للتكرار: من حفظ تشكيلته
-- خمس مرات في الأسبوع لا يُحاسب على خمسة انتقالات.
CREATE TABLE IF NOT EXISTS fantasy_transfers (
  squad_id   UUID    NOT NULL REFERENCES fantasy_squads(id) ON DELETE CASCADE,
  round      TEXT    NOT NULL,
  player_id  INTEGER NOT NULL REFERENCES players(id),
  -- 'in' دخل التشكيلة، 'out' خرج منها.
  direction  TEXT    NOT NULL CHECK (direction IN ('in', 'out')),
  -- السعر لحظة الحركة: البيع يستردّ سعر الشراء ونصف الربح، وبلا
  -- تسجيل سعر اللحظة يستحيل مراجعة حسابٍ بعد أسابيع.
  price      NUMERIC(4,1) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- لاعبٌ واحد لا يدخل ويخرج مرتين في نفس الجولة: من أعاد من
  -- باعه في نفس الأسبوع لم ينتقل شيء.
  PRIMARY KEY (squad_id, round, player_id, direction)
);

CREATE INDEX IF NOT EXISTS idx_fantasy_transfers_demand
  ON fantasy_transfers (round, player_id, direction);

-- ── تفصيل النقاط ────────────────────────────────────────────────
--
-- «من أين جاءت هذه النقاط؟» سؤالٌ يجب أن تجيبه الشاشة بلا أن
-- تحسب. والمحرّك يولّد السطور أصلاً مع الرقم (راجع
-- computePlayerPoints) — كان ينقصها أن تُحفظ.
--
-- ومحفوظةٌ لا محسوبةٌ عند القراءة: جدول النقاط يُعدَّل من اللوحة،
-- وإعادة الحساب بجدول اليوم تجعل جولةً ماضية تقول رقماً غير الذي
-- رآه صاحبها يومها.
ALTER TABLE fantasy_round_players
  ADD COLUMN IF NOT EXISTS lines JSONB;
