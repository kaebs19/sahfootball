// ترجمة أسماء الفرق — تعبئة name_ar.
//
// أسلوب الحفظ: زر لكل صف يظهر فقط عند تغيير النص (dirty).
// حفظ تلقائي عند كل حرف كان سيغرق السيرفر بالطلبات، وزر حفظ واحد
// للجدول كله يجعل خطأً في صف واحد يعطّل البقية.
import { useEffect, useState } from 'react';
import { api } from '../api';
import { Card, Icon, Notice, PageHead, Stat, Table } from '../components/ui';

export default function Teams() {
  const [teams, setTeams] = useState(null);
  const [drafts, setDrafts] = useState({}); // { teamId: النص المكتوب }
  const [savingId, setSavingId] = useState(null);
  const [error, setError] = useState('');
  const [onlyUntranslated, setOnlyUntranslated] = useState(false);

  useEffect(() => {
    api.get('/admin/teams')
      .then(({ data }) => setTeams(data.teams))
      .catch(() => setError('تعذر تحميل الفرق'));
  }, []);

  async function save(team) {
    const value = drafts[team.id] ?? '';
    setSavingId(team.id);
    setError('');
    try {
      const { data } = await api.put(`/admin/teams/${team.id}`, { name_ar: value });
      // حدّث الصف محلياً وامسح مسودته — الزر يختفي.
      setTeams(teams.map((t) => (t.id === team.id ? { ...t, name_ar: data.name_ar } : t)));
      setDrafts((d) => {
        const next = { ...d };
        delete next[team.id];
        return next;
      });
    } catch (err) {
      setError(err.response?.data?.error || 'فشل الحفظ');
    } finally {
      setSavingId(null);
    }
  }

  if (!teams) {
    return (
      <>
        <PageHead title="الفرق" />
        <Card><p className="muted">{error || 'جارِ التحميل…'}</p></Card>
      </>
    );
  }

  const translated = teams.filter((t) => t.name_ar).length;
  const ratio = teams.length ? translated / teams.length : 0;
  const rows = onlyUntranslated ? teams.filter((t) => !t.name_ar) : teams;

  return (
    <>
      <PageHead
        title="الفرق"
        subtitle="الاسم العربي يظهر في التطبيق فور حفظه، والفارغ يعرض الإنجليزي تلقائياً"
      />

      <div className="grid cols-4" style={{ marginBottom: 14 }}>
        <Stat icon={Icon.shield} label="مجموع الفرق" value={teams.length} />
        <Stat
          icon={Icon.shield}
          label="مترجمة"
          value={`${translated} / ${teams.length}`}
          note={`${Math.round(ratio * 100)}%`}
          tone={ratio === 1 ? 'good' : undefined}
          // الشريط يعرض التقدّم الفعلي، ولونه يحمّر حين يكون التقدّم
          // ضعيفاً — عكس حصة API حيث الامتلاء هو الخطر.
          meter={ratio}
          meterTone={ratio >= 1 ? undefined : ratio < 0.5 ? 'danger' : 'warn'}
        />
        <Stat
          icon={Icon.alert}
          label="بلا ترجمة"
          value={teams.length - translated}
          tone={translated < teams.length ? 'alert' : 'good'}
        />
      </div>

      <Card
        actions={
          <button
            className={onlyUntranslated ? '' : 'ghost'}
            onClick={() => setOnlyUntranslated((v) => !v)}
          >
            {onlyUntranslated ? 'عرض الكل' : 'غير المترجمة فقط'}
          </button>
        }
      >
        <Notice kind="error">{error}</Notice>
        <Table
          head={['', 'الاسم الإنجليزي', 'الاسم العربي', '']}
          empty={rows.length === 0 ? 'كل الفرق مترجمة 🎉' : null}
        >
          {rows.map((team) => {
            const draft = drafts[team.id];
            const dirty = draft !== undefined && draft !== (team.name_ar ?? '');
            return (
              <tr key={team.id}>
                <td style={{ width: 34 }}>
                  <img className="team-logo" src={team.logo_url} alt="" />
                </td>
                <td className="ltr">{team.name_en}</td>
                <td style={{ maxWidth: 280 }}>
                  <input
                    value={draft ?? team.name_ar ?? ''}
                    placeholder="—"
                    onChange={(e) => setDrafts({ ...drafts, [team.id]: e.target.value })}
                  />
                </td>
                <td style={{ width: 80 }}>
                  {dirty && (
                    <button
                      className="small"
                      disabled={savingId === team.id}
                      onClick={() => save(team)}
                    >
                      {savingId === team.id ? '…' : 'حفظ'}
                    </button>
                  )}
                </td>
              </tr>
            );
          })}
        </Table>
      </Card>
    </>
  );
}
