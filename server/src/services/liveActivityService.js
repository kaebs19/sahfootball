// liveActivityService — ما يحدث في الملعب يصل إلى الجيب لحظته.
//
// يراقب صفوف المباريات بعد كل مزامنة (المجدول أو الإنعاش عند
// الطلب) ويلتقط الفروق: هدف، انطلاق، صافرة نهاية. ثم ثلاثة أفعال:
//
//   • هدف      → إشعار «هدف!» لكل من توقّع المباراة (iOS وأندرويد)،
//                بمعرّف طيّ واحد للمباراة فيحلّ الجديد محل القديم
//                بدل أن تتكدّس ثلاثة إشعارات لثلاثة أهداف.
//   • أي تغيّر → تحديث النشاط الحيّ (Live Activity) على iOS: النتيجة
//                والدقيقة على شاشة القفل بلا إشعار ولا صوت.
//   • انطلاق   → بدء النشاط بالدفع لمن توقّع ولم يفتح التطبيق
//                (push-to-start)، فتظهر مباراته على قفل شاشته وحدها.
//   • نهاية    → إنهاء النشاط بنتيجته الأخيرة، ويختفي بعد نصف ساعة.
//
// الفروق تُحسب من ذاكرة العملية لا من القاعدة: أول رؤية لمباراة بعد
// الإقلاع تُسجَّل بصمت — وإلا أطلق كل إعادة تشغيل للسيرفر وابلاً
// من «أهداف» قديمة على كل من توقّع مباريات اليوم.
//
// ولا يرمي أبداً ولا يُنتظر: يُنادى من مسار طلب حيّ، وفشل دفعة
// واحدة يجب ألا يؤخّر ردّ /live على من ينتظره.
const notificationRepo = require('../repositories/notificationRepo');
const fixtureRepo = require('../repositories/fixtureRepo');
const pushService = require('../services/pushService');
const provider = require('./pushProvider');
const scoringService = require('./scoringService');
const logger = require('../utils/logger');

/** آخر حالة رأيناها لكل مباراة. */
const lastState = new Map();

/** الحالة المضغوطة التي تعني شيئاً للجيب — ما عداها تغيّر صامت. */
function snapshot(f) {
  return {
    gh: f.goals_home ?? null,
    ga: f.goals_away ?? null,
    status: f.status,
    elapsed: f.elapsed ?? null,
    phase: f.phase ?? null,
  };
}

const same = (a, b) =>
  a.gh === b.gh && a.ga === b.ga && a.status === b.status &&
  a.elapsed === b.elapsed && a.phase === b.phase;

/** ما يحمله النشاط الحيّ في كل تحديث — يطابق ContentState في Swift. */
function contentState(f) {
  return {
    goalsHome: f.goals_home ?? 0,
    goalsAway: f.goals_away ?? 0,
    elapsed: f.elapsed ?? null,
    phase: f.phase ?? '',
    status: f.status,
  };
}

/** صفات النشاط الثابتة — تطابق MatchActivityAttributes في Swift. */
function attributes(f, pred) {
  return {
    fixtureId: f.id,
    home: f.home_team_name,
    away: f.away_team_name,
    predHome: pred?.pred_home ?? null,
    predAway: pred?.pred_away ?? null,
  };
}

const score = (f) => `${f.home_team_name} ${f.goals_home ?? 0} - ${f.goals_away ?? 0} ${f.away_team_name}`;

/**
 * إشعار الهدف. الرقم أولاً — هو الخبر — ثم ماذا يعني لتوقّعك.
 *
 * «مضبوط الآن» بالذات هي الجملة التي تجعل المستخدم يفتح التطبيق:
 * هدفٌ حوّل توقّعه إلى نتيجة مضبوطة لحظةٌ تستحق أن تُقال باسمها.
 */
function goalText(f, pred, { cancelled = false } = {}) {
  const state = scoringService.computeState(
    { home: pred.pred_home, away: pred.pred_away },
    { home: f.goals_home ?? 0, away: f.goals_away ?? 0 }
  );
  const minute = f.elapsed != null ? `${f.elapsed}' · ` : '';
  const verdict = state === 'exact' ? ' — مضبوط الآن!' : state === 'none' ? ' — خارج المسار' : '';
  return {
    // النتيجة تنقص حين يُلغى هدف (VAR): «هدف!» فوق نتيجة أقلّ كذبة
    // تُقرأ فوراً، فنقول ما حدث.
    title: cancelled ? `أُلغي الهدف · ${score(f)}` : `⚽ هدف! ${score(f)}`,
    body: `${minute}توقعك ${pred.pred_home} - ${pred.pred_away}${verdict}`,
  };
}

async function onGoal(f, { cancelled = false } = {}) {
  const recipients = await notificationRepo.goalAlertRecipients(f.id);
  for (const pred of recipients) {
    const { title, body } = goalText(f, pred, { cancelled });
    await pushService.sendToUser(pred.user_id, {
      title,
      body,
      data: { type: 'goal', fixtureId: f.id },
      // إشعار واحد للمباراة يُستبدل مع كل هدف: النتيجة الأخيرة هي
      // ما يهمّ، وثلاثة إشعارات لثلاثة أهداف ضجيج يُطفأ.
      collapseId: `match-${f.id}`,
    });
  }
  if (recipients.length) logger.info(`[live] goal ${f.id}: ${recipients.length} alerts`);
}

/** تحديث كل الأنشطة القائمة لمباراة — بصمت، بلا إشعار. */
async function updateActivities(f, { end = false } = {}) {
  const tokens = await notificationRepo.activityTokensForFixture(f.id);
  if (!tokens.length) return;
  const dead = [];
  await Promise.all(tokens.map(async ({ token }) => {
    try {
      const r = await provider.sendLiveActivity({
        token,
        event: end ? 'end' : 'update',
        contentState: contentState(f),
        // بعد النهاية يبقى النشاط نصف ساعة ثم يختفي وحده — وقتٌ
        // كافٍ ليرى النتيجة من فتح هاتفه بعد الصافرة بقليل.
        dismissalDate: end ? Math.floor(Date.now() / 1000) + 30 * 60 : undefined,
      });
      if (r === provider.GONE) dead.push(token);
    } catch (err) {
      logger.warn(`[live] activity update failed: ${err.message}`);
    }
  }));
  // بعد النهاية لا يصلح التوكن لشيء: نمسحه لا ننتظر موت الجهاز.
  const stale = end ? tokens.map((t) => t.token) : dead;
  if (stale.length) await notificationRepo.removeActivityTokens(stale);
}

/** بدء النشاط بالدفع لمن توقّع ولم يفتح التطبيق عند الانطلاق. */
async function startActivities(f) {
  const rows = await notificationRepo.startTokensForFixture(f.id);
  if (!rows.length) return;
  const dead = [];
  await Promise.all(rows.map(async (row) => {
    try {
      const r = await provider.sendLiveActivity({
        token: row.token,
        event: 'start',
        attributes: attributes(f, row),
        contentState: contentState(f),
      });
      if (r === provider.GONE) dead.push(row.token);
    } catch (err) {
      logger.warn(`[live] activity start failed: ${err.message}`);
    }
  }));
  if (dead.length) await notificationRepo.removeActivityTokens(dead);
  logger.info(`[live] kickoff ${f.id}: ${rows.length} activities started by push`);
}

/**
 * نقطة الدخول: صفوف المباريات كما خرجت من المزامنة للتو.
 *
 * لا await من المستدعي: المزامنة قد تكون في مسار طلب، والدفع
 * رحلات شبكة إلى آبل وجوجل.
 */
async function sync(rows) {
  const changed = [];
  for (const row of rows) {
    const cur = snapshot(row);
    const prev = lastState.get(row.id);
    lastState.set(row.id, cur);
    if (!prev || same(prev, cur)) continue;
    // ما لا يعني الجيب: مباراة مجدولة تغيّر موعدها، أو منتهية
    // صحّح المزوّد إحصاءها. الجارية وحدها، ولحظة نهايتها.
    if (cur.status !== 'live' && !(cur.status === 'finished' && prev.status === 'live')) continue;
    changed.push({ id: row.id, prev, cur });
  }
  if (!changed.length) return;

  for (const { id, prev, cur } of changed) {
    // نقرأ الصف الكامل بأسماء الفرق: صفوف المزامنة بلا أسماء.
    const f = await fixtureRepo.findByIdDetail(id);
    if (!f) continue;
    try {
      const kickedOff = cur.status === 'live' && prev.status !== 'live';
      const finished = cur.status === 'finished';
      // هدفٌ = نتيجة معلومة تغيّرت. الانتقال من «لا نتيجة» (قبل
      // الانطلاق) إلى 0 - 0 ليس هدفاً، وكان يُعلَن كذلك.
      const hadScore = prev.gh != null && prev.ga != null;
      const scoreChanged = hadScore && (cur.gh !== prev.gh || cur.ga !== prev.ga);
      const cancelled = scoreChanged && (cur.gh + cur.ga) < (prev.gh + prev.ga);

      if (kickedOff) await startActivities(f);
      if (cur.status === 'live' && scoreChanged) await onGoal(f, { cancelled });
      await updateActivities(f, { end: finished });
    } catch (err) {
      logger.error(`[live] sync ${id} failed: ${err.message}`);
    }
  }
}

/** يُنادى بلا انتظار — يبتلع كل خطأ. */
function syncInBackground(rows) {
  sync(rows).catch((err) => logger.error('[live] sync failed:', err.message));
}

module.exports = { sync, syncInBackground, goalText, contentState, attributes };
