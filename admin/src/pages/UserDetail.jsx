// ملف مستخدم واحد — كل ما نعرفه عنه، وكل ما يمكن فعله به.
//
// لماذا صفحة مستقلة لا نافذة منبثقة من الجدول؟ لأن لها رابطاً
// خاصاً يمكن مشاركته ("افحص هذا الحساب")، ولأن المحتوى — إحصاءات
// وتوقعات ومجموعات — أكبر من نافذة.
//
// ترتيب الأفعال مقصود: الأقل ضرراً في الأعلى (الدور)، ثم القابل
// للتراجع (التعليق)، ثم غير القابل للتراجع (الحذف) في منطقة
// منفصلة بلون تحذيري. الأدمن المتعجّل يجب ألا يقع على "حذف" وهو
// يقصد "تعليق".
import { useEffect, useState } from 'react';
import { useNavigate, useParams, Link } from 'react-router-dom';
import { api } from '../api';
import {
  Avatar,
  Card,
  ConfirmButton,
  Icon,
  Notice,
  PageHead,
  Stat,
  Table,
} from '../components/ui';

export default function UserDetail() {
  const { id } = useParams();
  const navigate = useNavigate();
  const [user, setUser] = useState(null);
  const [msg, setMsg] = useState(null);
  const [busy, setBusy] = useState(false);
  const [reason, setReason] = useState('');

  async function load() {
    const { data } = await api.get(`/admin/users/${id}`);
    setUser(data.user);
  }

  useEffect(() => {
    load().catch((err) =>
      setMsg({
        type: 'error',
        text: err.response?.status === 404 ? 'هذا المستخدم غير موجود' : 'تعذر تحميل الملف',
      })
    );
  }, [id]);

  async function act(fn, okText) {
    setBusy(true);
    setMsg(null);
    try {
      await fn();
      if (okText) setMsg({ type: 'ok', text: okText });
      await load();
    } catch (err) {
      setMsg({ type: 'error', text: err.response?.data?.error || 'فشلت العملية' });
    } finally {
      setBusy(false);
    }
  }

  if (!user) {
    return (
      <>
        <PageHead title="ملف المستخدم" />
        <Card>
          {msg ? <Notice kind={msg.type}>{msg.text}</Notice> : <p className="muted">جارِ التحميل…</p>}
          <div className="actions">
            <Link to="/users" className="btn ghost" style={{ display: 'inline-block' }}>
              رجوع للمستخدمين
            </Link>
          </div>
        </Card>
      </>
    );
  }

  const suspended = Boolean(user.suspended_at);
  const name = user.display_name || 'بلا اسم';

  return (
    <>
      <PageHead title="ملف المستخدم" subtitle="كل ما يخص هذا الحساب في مكان واحد">
        <Link to="/users" className="btn ghost">رجوع</Link>
      </PageHead>

      {msg && <Notice kind={msg.type}>{msg.text}</Notice>}

      {suspended && (
        <Notice kind="error">
          هذا الحساب معلّق منذ {new Date(user.suspended_at).toLocaleDateString('ar-SA')}
          {user.suspended_reason ? ` — السبب: ${user.suspended_reason}` : ''}. لا يستطيع
          الدخول ولا التوقع.
        </Notice>
      )}

      <Card>
        <div style={{ display: 'flex', alignItems: 'center', gap: 16, flexWrap: 'wrap' }}>
          <Avatar url={user.avatar_url} name={name} size={64} />
          <div style={{ flex: 1, minWidth: 180 }}>
            <h2 style={{ fontSize: 18 }}>{name}</h2>
            <div className="ltr" style={{ marginTop: 2 }}>{user.email || 'بلا بريد'}</div>
            <div style={{ display: 'flex', gap: 6, marginTop: 8, flexWrap: 'wrap' }}>
              {user.role === 'admin' && <span className="badge crown">أدمن</span>}
              {user.via_apple && <span className="badge">Apple</span>}
              {suspended ? (
                <span className="badge alert">معلّق</span>
              ) : (
                <span className="badge good">نشط</span>
              )}
              <span className="badge">
                انضم {new Date(user.created_at).toLocaleDateString('ar-SA')}
              </span>
              {user.favorite_team_name && (
                <span className="badge">
                  {user.favorite_team_logo && (
                    <img className="team-logo" style={{ width: 14, height: 14 }}
                         src={user.favorite_team_logo} alt="" />
                  )}
                  يشجّع {user.favorite_team_name}
                </span>
              )}
            </div>
          </div>
          {user.avatar_url && (
            <ConfirmButton
              label="إزالة الصورة"
              busy={busy}
              onConfirm={() =>
                act(() => api.delete(`/admin/users/${id}/avatar`), 'أُزيلت الصورة')
              }
            />
          )}
        </div>
      </Card>

      <div className="grid cols-4" style={{ margin: '12px 0' }}>
        <Stat icon={Icon.scoring} label="النقاط" value={user.total_points ?? 0} tone="crown" />
        <Stat icon={Icon.ball} label="التوقعات" value={user.predictions_count ?? 0} />
        <Stat
          icon={Icon.trophy}
          label="محتسبة"
          value={user.settled_predictions ?? 0}
          // accuracy تصل نسبة مئوية جاهزة من السيرفر (0–100).
          note={
            user.settled_predictions
              ? `دقة ${Math.round(user.accuracy ?? 0)}%`
              : 'لا شيء محتسب بعد'
          }
        />
        <Stat icon={Icon.group} label="المجموعات" value={user.groups?.length ?? 0} />
      </div>

      <div className="grid cols-2">
        <Card title="آخر التوقعات" subtitle="أحدث عشرين توقعاً">
          {user.predictions?.length ? (
            <Table head={['المباراة', 'توقعه', 'النتيجة', 'النقاط']}>
              {user.predictions.map((p) => (
                <tr key={p.id}>
                  <td style={{ fontSize: 12.5 }}>
                    {p.home_team_name} — {p.away_team_name}
                  </td>
                  <td className="ltr" style={{ color: 'var(--correct)', fontWeight: 600 }}>
                    {p.pred_home} - {p.pred_away}
                  </td>
                  <td className="ltr">
                    {p.goals_home !== null ? `${p.goals_home} - ${p.goals_away}` : '—'}
                  </td>
                  <td>
                    {p.settled_at ? (
                      p.points > 0 ? (
                        <span className="badge crown">+{p.points}</span>
                      ) : (
                        <span className="faint">0</span>
                      )
                    ) : (
                      <span className="muted">—</span>
                    )}
                  </td>
                </tr>
              ))}
            </Table>
          ) : (
            <p className="muted">لم يسجّل أي توقع.</p>
          )}
        </Card>

        <div className="grid" style={{ alignContent: 'start' }}>
          <Card title="المجموعات">
            {user.groups?.length ? (
              <Table head={['المجموعة', 'الدور', 'الأعضاء']}>
                {user.groups.map((g) => (
                  <tr key={g.id}>
                    <td style={{ fontWeight: 600 }}>{g.name}</td>
                    <td>
                      {g.is_owner ? (
                        <span className="badge crown">مالك</span>
                      ) : (
                        <span className="muted">عضو</span>
                      )}
                    </td>
                    <td className="muted">{g.members_count}</td>
                  </tr>
                ))}
              </Table>
            ) : (
              <p className="muted">ليس في أي مجموعة.</p>
            )}
          </Card>

          <Card title="الصلاحية">
            <p className="muted" style={{ marginBottom: 10 }}>
              الأدمن يرى لوحة التحكم كاملة ويستطيع تعديل كل شيء فيها.
            </p>
            <ConfirmButton
              label={user.role === 'admin' ? 'إزالة صلاحية الأدمن' : 'ترقية لأدمن'}
              busy={busy}
              onConfirm={() =>
                act(
                  () =>
                    api.put(`/admin/users/${id}/role`, {
                      role: user.role === 'admin' ? 'user' : 'admin',
                    }),
                  'تغيّر الدور'
                )
              }
            />
          </Card>
        </div>
      </div>

      {/* منطقة الأفعال الخطرة — معزولة بصرياً بحد أحمر */}
      <div
        className="card"
        style={{ marginTop: 12, borderColor: 'var(--wrong-wash)' }}
      >
        <h2 style={{ color: 'var(--wrong)' }}>أفعال خطرة</h2>
        <p className="muted" style={{ marginBottom: 14 }}>
          التعليق قابل للتراجع في أي وقت. الحذف نهائي.
        </p>

        <div className="field" style={{ alignItems: 'flex-start' }}>
          <label>
            {suspended ? 'رفع التعليق' : 'تعليق الحساب'}
            <span className="hint">
              {suspended
                ? 'يعود الحساب للعمل فوراً ويستطيع صاحبه الدخول مجدداً.'
                : 'يمنع الدخول والتوقع فوراً وتُنهى جلساته، وتبقى بياناته وتوقعاته كما هي.'}
            </span>
          </label>
          <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
            {!suspended && (
              <input
                style={{ width: 200 }}
                placeholder="السبب (اختياري)"
                value={reason}
                onChange={(e) => setReason(e.target.value)}
              />
            )}
            <ConfirmButton
              label={suspended ? 'رفع التعليق' : 'تعليق'}
              busy={busy}
              className={suspended ? '' : 'ghost'}
              onConfirm={() =>
                act(
                  () =>
                    api.put(`/admin/users/${id}/suspend`, {
                      suspended: !suspended,
                      ...(suspended ? {} : { reason: reason.trim() || undefined }),
                    }),
                  suspended ? 'رُفع التعليق' : 'عُلّق الحساب'
                )
              }
            />
          </div>
        </div>

        <div className="field" style={{ alignItems: 'flex-start', borderBottom: 'none' }}>
          <label>
            حذف الحساب نهائياً
            <span className="hint">
              يُحذف الحساب وتوقعاته وصورته. لا يمكن التراجع، ونقاطه تختفي من العرش.
            </span>
          </label>
          <ConfirmButton
            label="حذف نهائي"
            confirmLabel="متأكد؟ لا رجعة"
            busy={busy}
            onConfirm={async () => {
              setBusy(true);
              setMsg(null);
              try {
                await api.delete(`/admin/users/${id}`);
                navigate('/users');
              } catch (err) {
                setMsg({ type: 'error', text: err.response?.data?.error || 'فشل الحذف' });
                setBusy(false);
              }
            }}
          />
        </div>
      </div>
    </>
  );
}
