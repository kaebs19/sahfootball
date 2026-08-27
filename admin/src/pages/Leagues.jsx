// الدوريات — أي بطولات يغطيها التطبيق.
//
// هذه أغلى صفحة في اللوحة من ناحية التكلفة، ويجب أن تُظهر ذلك:
// كل دوري مُفعَّل يُزامَن مع كل دورة مزامنة، والخطة المجانية 100
// طلب/يوم. لذلك نعرض حصة اليوم في الأعلى ونحذّر قبل الإضافة، بدل
// أن يكتشف الأدمن الكلفة حين يتوقف التطبيق عن التحديث.
//
// التعطيل مقابل الحذف: التعطيل يوقف المزامنة ويبقي المباريات
// والتوقعات المبنية عليها. الحذف يرفضه السيرفر ما دامت للدوري
// مباريات — وهذا مقصود، فحذفه كان سيترك صفوفاً تشير إلى لا شيء.
import { useEffect, useState } from 'react';
import { api } from '../api';
import { Card, ConfirmButton, Icon, Notice, PageHead, Stat, Svg, Table } from '../components/ui';

export default function Leagues() {
  const [leagues, setLeagues] = useState(null);
  const [quota, setQuota] = useState(null);
  const [message, setMessage] = useState(null);
  const [busyId, setBusyId] = useState(null);
  const [adding, setAdding] = useState(false);

  async function load() {
    const [{ data: l }, { data: s }] = await Promise.all([
      api.get('/admin/leagues'),
      api.get('/admin/stats'),
    ]);
    setLeagues(l.leagues);
    setQuota({ used: s.api_requests_today, limit: s.api_daily_limit });
  }

  useEffect(() => {
    load().catch(() => setMessage({ type: 'error', text: 'تعذر تحميل الدوريات' }));
  }, []);

  async function patch(id, fields) {
    setBusyId(id);
    setMessage(null);
    try {
      await api.put(`/admin/leagues/${id}`, fields);
      setLeagues((ls) => ls.map((l) => (l.id === id ? { ...l, ...fields } : l)));
    } catch (err) {
      setMessage({ type: 'error', text: err.response?.data?.error || 'فشل التعديل' });
    } finally {
      setBusyId(null);
    }
  }

  async function syncOne(league) {
    setBusyId(league.id);
    setMessage(null);
    try {
      const { data } = await api.post(`/admin/leagues/${league.id}/sync`);
      setMessage({
        type: 'ok',
        text: `${league.name_ar || league.name_en}: ${data.teams ?? 0} فريقاً و${data.fixtures ?? 0} مباراة`,
      });
      await load();
    } catch (err) {
      setMessage({ type: 'error', text: err.response?.data?.error || 'فشلت المزامنة' });
    } finally {
      setBusyId(null);
    }
  }

  async function remove(league) {
    setBusyId(league.id);
    setMessage(null);
    try {
      await api.delete(`/admin/leagues/${league.id}`);
      setLeagues((ls) => ls.filter((l) => l.id !== league.id));
    } catch (err) {
      setMessage({
        type: 'error',
        text: err.response?.data?.error || 'فشل الحذف — عطّل الدوري بدلاً من حذفه',
      });
    } finally {
      setBusyId(null);
    }
  }

  if (!leagues) {
    // فشل التحميل يجب أن يظهر كخطأ لا كتحميل أبدي: الأول يخبر
    // الأدمن أن شيئاً معطّل، والثاني يجعله ينتظر بلا نهاية.
    return (
      <>
        <PageHead title="الدوريات" />
        <Card>
          {message ? (
            <>
              <Notice kind="error">{message.text}</Notice>
              <button className="ghost" onClick={() => load().catch(() => {})}>
                إعادة المحاولة
              </button>
            </>
          ) : (
            <p className="muted">جارِ التحميل…</p>
          )}
        </Card>
      </>
    );
  }

  const enabled = leagues.filter((l) => l.enabled).length;
  const quotaRatio = quota ? quota.used / quota.limit : 0;

  return (
    <>
      <PageHead
        title="الدوريات"
        subtitle="البطولات التي يغطيها التطبيق. كل دوري مُفعَّل يُزامَن دورياً ويستهلك من حصة API."
      >
        <button onClick={() => setAdding((v) => !v)}>
          {adding ? 'إلغاء' : 'إضافة دوري'}
        </button>
      </PageHead>

      <div className="grid cols-4" style={{ marginBottom: 14 }}>
        <Stat icon={Icon.league} label="الدوريات" value={leagues.length} />
        <Stat
          icon={Icon.sync}
          label="مُفعَّلة"
          value={enabled}
          note="تُزامَن تلقائياً"
          tone={enabled > 0 ? 'good' : 'alert'}
        />
        <Stat
          icon={Icon.ball}
          label="مجموع المباريات"
          value={leagues.reduce((s, l) => s + (l.fixtures_count ?? 0), 0)}
        />
        <Stat
          icon={Icon.alert}
          label="حصة API اليوم"
          value={quota ? `${quota.used} / ${quota.limit}` : '…'}
          note={quotaRatio >= 0.8 ? 'اقتربت من النفاد' : 'مشتركة بين كل الدوريات'}
          tone={quotaRatio >= 0.8 ? 'alert' : undefined}
          meter={quotaRatio}
          meterTone={quotaRatio >= 0.9 ? 'danger' : quotaRatio >= 0.7 ? 'warn' : undefined}
        />
      </div>

      {message && <Notice kind={message.type}>{message.text}</Notice>}

      {adding && (
        <AddLeague
          onDone={async () => {
            setAdding(false);
            await load();
          }}
          onError={(text) => setMessage({ type: 'error', text })}
        />
      )}

      <Card>
        <Table
          head={['الدوري', 'المعرّف', 'الموسم', 'المباريات', 'آخر مزامنة', 'الحالة', '']}
          empty={leagues.length === 0 ? 'لا دوريات — أضف واحداً لتبدأ التغطية' : null}
        >
          {leagues.map((l) => (
            <tr key={l.id} style={{ opacity: l.enabled ? 1 : 0.55 }}>
              <td>
                <span className="match">
                  {l.logo_url && <img className="team-logo" src={l.logo_url} alt="" />}
                  <span>
                    <div style={{ fontWeight: 600 }}>{l.name_ar || l.name_en}</div>
                    {l.name_ar && <div className="ltr" style={{ fontSize: 11 }}>{l.name_en}</div>}
                  </span>
                </span>
              </td>
              <td className="ltr">{l.id}</td>
              <td className="num">{l.season}</td>
              <td>
                {l.fixtures_count > 0 ? (
                  <span className="badge">{l.fixtures_count}</span>
                ) : (
                  <span className="faint">—</span>
                )}
              </td>
              <td className="muted">
                {l.last_synced_at
                  ? new Date(l.last_synced_at).toLocaleString('ar-SA', {
                      month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit',
                    })
                  : 'لم تتم بعد'}
              </td>
              <td>
                {l.enabled ? (
                  <span className="badge good">مُفعَّل</span>
                ) : (
                  <span className="badge">معطَّل</span>
                )}
              </td>
              <td>
                <div style={{ display: 'flex', gap: 6 }}>
                  <button
                    className="ghost small"
                    disabled={busyId === l.id}
                    title="مزامنة هذا الدوري الآن"
                    onClick={() => syncOne(l)}
                  >
                    <Svg path={Icon.sync} size={13} />
                  </button>
                  <button
                    className="ghost small"
                    disabled={busyId === l.id}
                    onClick={() => patch(l.id, { enabled: !l.enabled })}
                  >
                    {l.enabled ? 'تعطيل' : 'تفعيل'}
                  </button>
                  {/* الحذف متاح فقط لدوري بلا مباريات — السيرفر يرفض
                      غير ذلك، ونخفي الزر بدل أن نعرض فعلاً سيفشل. */}
                  {!l.fixtures_count && (
                    <ConfirmButton
                      label="حذف"
                      busy={busyId === l.id}
                      onConfirm={() => remove(l)}
                    />
                  )}
                </div>
              </td>
            </tr>
          ))}
        </Table>
      </Card>
    </>
  );
}

/** نموذج إضافة دوري — بحث في المزود أو إدخال المعرّف يدوياً. */
function AddLeague({ onDone, onError }) {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState(null);
  const [searching, setSearching] = useState(false);
  const [season, setSeason] = useState(new Date().getFullYear());
  const [busy, setBusy] = useState(false);

  async function search(e) {
    e.preventDefault();
    if (!query.trim()) return;
    setSearching(true);
    try {
      const { data } = await api.get('/admin/leagues/search', { params: { q: query.trim() } });
      setResults(data.leagues ?? []);
    } catch (err) {
      onError(err.response?.data?.error || 'فشل البحث — قد تكون الحصة قد نفدت');
    } finally {
      setSearching(false);
    }
  }

  async function add(item) {
    setBusy(true);
    try {
      await api.post('/admin/leagues', {
        id: item.id,
        name_en: item.name_en ?? item.name,
        country: item.country ?? null,
        logo_url: item.logo_url ?? item.logo ?? null,
        season: Number(season),
      });
      onDone();
    } catch (err) {
      onError(err.response?.data?.error || 'فشلت الإضافة');
    } finally {
      setBusy(false);
    }
  }

  return (
    <Card title="إضافة دوري" subtitle="ابحث باسم البطولة أو الدولة. البحث يستهلك طلباً واحداً من الحصة.">
      <form onSubmit={search} style={{ display: 'flex', gap: 9, flexWrap: 'wrap', marginTop: 12 }}>
        <input
          style={{ flex: 1, minWidth: 200 }}
          placeholder="مثال: Premier League أو Saudi"
          dir="ltr"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        <input
          type="number"
          style={{ width: 110 }}
          dir="ltr"
          value={season}
          onChange={(e) => setSeason(e.target.value)}
          title="الموسم"
        />
        <button disabled={searching}>{searching ? '…' : 'بحث'}</button>
      </form>

      {results && (
        <div style={{ marginTop: 14 }}>
          <Table
            head={['البطولة', 'الدولة', 'المعرّف', '']}
            empty={results.length === 0 ? 'لا نتائج' : null}
          >
            {results.map((r) => (
              <tr key={r.id}>
                <td>
                  <span className="match">
                    {(r.logo_url || r.logo) && (
                      <img className="team-logo" src={r.logo_url || r.logo} alt="" />
                    )}
                    <span className="ltr" style={{ color: 'var(--text)' }}>
                      {r.name_en ?? r.name}
                    </span>
                  </span>
                </td>
                <td className="muted">{r.country || '—'}</td>
                <td className="ltr">{r.id}</td>
                <td>
                  <button className="small" disabled={busy} onClick={() => add(r)}>
                    إضافة
                  </button>
                </td>
              </tr>
            ))}
          </Table>
        </div>
      )}
    </Card>
  );
}
