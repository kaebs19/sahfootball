// الرئيسية — حالة النظام في شاشة واحدة.
//
// مبدأ ترتيب الصفحة: ما يستدعي تدخّلاً أولاً، ثم ما يقيس النمو،
// ثم التفاصيل. الأدمن يفتح هذه الشاشة ليسأل "هل كل شيء يعمل؟"
// لا ليقرأ تقريراً — فالأرقام التي تعني عطلاً (توقعات لم تُحتسب،
// حصة API على وشك النفاد) تأخذ لوناً تحذيرياً وتصعد للأعلى.
import { useEffect, useState } from 'react';
import { api } from '../api';
import { BarChart, Distribution } from '../components/charts';
import { Card, Icon, Notice, PageHead, Stat, Table } from '../components/ui';

export default function Dashboard() {
  const [stats, setStats] = useState(null);
  const [scoring, setScoring] = useState(null);
  const [message, setMessage] = useState(null);
  const [busy, setBusy] = useState(false);

  async function load() {
    const { data } = await api.get('/admin/stats');
    setStats(data);
  }

  useEffect(() => {
    load().catch(() => setMessage({ type: 'error', text: 'تعذر تحميل الإحصاءات' }));
    // قيم النقاط تُستخدم لتسمية أعمدة التوزيع ("5 نقاط" ← "نتيجة
    // مضبوطة") — بدونها الرسم أرقام بلا معنى.
    api.get('/admin/settings/scoring').then(({ data }) => setScoring(data.scoring)).catch(() => {});
  }, []);

  async function syncNow() {
    setBusy(true);
    setMessage(null);
    try {
      const { data } = await api.post('/admin/sync');
      setMessage({
        type: 'ok',
        text: `تمت المزامنة: ${data.teams} فريقاً، ${data.fixtures} مباراة، واحتُسب ${data.settled} توقعاً`,
      });
      await load();
    } catch (err) {
      setMessage({ type: 'error', text: err.response?.data?.error || 'فشلت المزامنة' });
    } finally {
      setBusy(false);
    }
  }

  if (!stats) {
    return (
      <>
        <PageHead title="الرئيسية" />
        <Card><p className="muted">{message?.text || 'جارِ التحميل…'}</p></Card>
      </>
    );
  }

  const quotaRatio = stats.api_requests_today / (stats.api_daily_limit || 1);
  const pending = stats.pending_settlement ?? 0;

  // تسمية قيمة النقاط بمعناها بدل رقمها المجرّد.
  const labelOf = (points) => {
    if (!scoring) return `${points} نقاط`;
    if (points === scoring.exact) return `نتيجة مضبوطة (${points})`;
    if (points === scoring.diff) return `فارق الأهداف (${points})`;
    if (points === scoring.outcome) return `الاتجاه فقط (${points})`;
    if (points === 0) return 'بدون نقاط';
    return `${points} نقاط`;
  };

  return (
    <>
      <PageHead title="الرئيسية" subtitle="حالة النظام والنشاط الأخير">
        <button disabled={busy} onClick={syncNow}>
          {busy ? 'جارِ المزامنة…' : 'مزامنة الآن'}
        </button>
      </PageHead>

      {message && <Notice kind={message.type}>{message.text}</Notice>}

      {/* الصف الأول: ما قد يستدعي تدخّلاً */}
      <div className="grid cols-4" style={{ marginBottom: 12 }}>
        <Stat
          icon={Icon.alert}
          label="تنتظر الاحتساب"
          value={pending}
          note={pending ? 'مباريات انتهت ولم تُحتسب' : 'كل ما انتهى محتسب'}
          tone={pending > 0 ? 'alert' : 'good'}
        />
        <Stat
          icon={Icon.sync}
          label="حصة API اليوم"
          value={`${stats.api_requests_today} / ${stats.api_daily_limit}`}
          note={quotaRatio >= 0.8 ? 'اقتربت من النفاد' : 'الحصة اليومية'}
          tone={quotaRatio >= 0.8 ? 'alert' : undefined}
          // هنا الامتلاء خطر: كلما ارتفع الاستهلاك اقترب التوقف.
          meter={quotaRatio}
          meterTone={quotaRatio >= 0.9 ? 'danger' : quotaRatio >= 0.7 ? 'warn' : undefined}
        />
        <Stat
          icon={Icon.ball}
          label="مباشرة الآن"
          value={stats.fixtures_live}
          tone={stats.fixtures_live > 0 ? 'good' : undefined}
          note={stats.fixtures_live > 0 ? 'التحديث كل 5 دقائق' : 'لا مباريات جارية'}
        />
        <Stat
          icon={Icon.league}
          label="الدوريات المُفعَّلة"
          value={
            stats.leagues_enabled !== undefined
              ? `${stats.leagues_enabled} / ${stats.leagues_total}`
              : '—'
          }
          note="تُزامَن دورياً"
        />
      </div>

      {/* الصف الثاني: النمو */}
      <div className="grid cols-4" style={{ marginBottom: 12 }}>
        <Stat
          icon={Icon.users}
          label="المستخدمون"
          value={stats.users}
          note={growth(stats.users_new_7d, 'حساب جديد')}
        />
        <Stat
          icon={Icon.scoring}
          label="التوقعات"
          value={stats.predictions}
          note={growth(stats.predictions_7d, 'توقّع')}
        />
        <Stat
          icon={Icon.users}
          label="نشطون هذا الأسبوع"
          value={stats.active_users_7d ?? '—'}
          note={
            stats.active_users_7d !== undefined && stats.users
              ? `${Math.round((stats.active_users_7d / stats.users) * 100)}% من الحسابات`
              : undefined
          }
        />
        <Stat
          icon={Icon.group}
          label="المجموعات"
          value={stats.groups ?? '—'}
          note={growth(stats.groups_7d, 'مجموعة')}
        />
      </div>

      <div className="grid cols-2" style={{ marginBottom: 12 }}>
        <Card
          title="نشاط التوقعات"
          subtitle="آخر أربعة عشر يوماً — الأعمدة الفارغة أيام بلا توقعات"
        >
          <BarChart data={stats.predictions_daily} />
        </Card>

        <Card title="كيف تُكسب النقاط" subtitle="توزيع التوقعات المحتسبة على قيم النقاط">
          <Distribution data={stats.points_distribution} labelOf={labelOf} />
        </Card>
      </div>

      <div className="grid cols-2">
        <Card title="المتصدّرون" subtitle="أعلى خمسة في العرش">
          {stats.top_users?.length ? (
            <Table head={['#', 'الاسم', 'النقاط', 'محتسبة']}>
              {stats.top_users.map((u, i) => (
                <tr key={u.user_id}>
                  <td style={{ width: 40 }}>
                    <span className={i === 0 ? 'badge crown' : 'muted'}>{i + 1}</span>
                  </td>
                  <td style={{ fontWeight: 600 }}>{u.display_name}</td>
                  <td className="crown-text" style={{ fontWeight: 700 }}>{u.total_points}</td>
                  <td className="muted">{u.settled_predictions}</td>
                </tr>
              ))}
            </Table>
          ) : (
            <p className="muted">لا نقاط بعد.</p>
          )}
        </Card>

        <Card title="المباريات حسب الدوري" subtitle="ما هو مخزّن عندنا الآن">
          {stats.fixtures_by_league?.length ? (
            <Table head={['الدوري', 'قادمة', 'مباشرة', 'منتهية']}>
              {stats.fixtures_by_league.map((l) => (
                <tr key={l.league_id}>
                  <td style={{ fontWeight: 600 }}>{l.name}</td>
                  <td>{l.scheduled}</td>
                  <td className={l.live > 0 ? 'error' : 'muted'}>{l.live}</td>
                  <td className="muted">{l.finished}</td>
                </tr>
              ))}
            </Table>
          ) : (
            <SimpleFixtureCounts stats={stats} />
          )}
        </Card>
      </div>

      <div className="grid cols-4" style={{ marginTop: 12 }}>
        <Stat
          icon={Icon.shield}
          label="الفرق المترجمة"
          value={`${stats.teams_translated} / ${stats.teams}`}
          note={
            stats.teams_translated < stats.teams
              ? `${stats.teams - stats.teams_translated} بلا اسم عربي`
              : 'كلها مترجمة'
          }
          tone={stats.teams_translated < stats.teams ? undefined : 'good'}
          meter={stats.teams ? stats.teams_translated / stats.teams : 0}
          meterTone={
            stats.teams && stats.teams_translated / stats.teams < 0.5 ? 'danger' : 'warn'
          }
        />
        <Stat icon={Icon.ball} label="مباريات قادمة" value={stats.fixtures_scheduled} />
        <Stat icon={Icon.ball} label="مباريات منتهية" value={stats.fixtures_finished} />
        <Stat
          icon={Icon.trophy}
          label="متوسط التوقعات للمستخدم"
          value={stats.users ? (stats.predictions / stats.users).toFixed(1) : '—'}
        />
      </div>
    </>
  );
}

function growth(value, unit) {
  if (value === undefined || value === null) return undefined;
  return value > 0 ? `+${value} ${unit} هذا الأسبوع` : `لا ${unit} جديد هذا الأسبوع`;
}

/** بديل لو لم يرسل السيرفر التفصيل حسب الدوري (نسخة أقدم). */
function SimpleFixtureCounts({ stats }) {
  return (
    <Table head={['الحالة', 'العدد']}>
      <tr><td>قادمة</td><td>{stats.fixtures_scheduled}</td></tr>
      <tr><td>مباشرة</td><td>{stats.fixtures_live}</td></tr>
      <tr><td>منتهية</td><td>{stats.fixtures_finished}</td></tr>
    </Table>
  );
}
