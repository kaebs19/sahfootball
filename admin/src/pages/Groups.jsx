// إشراف المجموعات — قائمة وبحث وحذف (للأسماء المسيئة ونحوها).
//
// أضفنا هنا فوق النسخة السابقة: أرقاماً موجزة في الأعلى، وتمييز
// المجموعات الفارغة. المجموعة بعضو واحد (مالكها فقط) لم تُستخدم
// فعلاً، وهي أول ما يبحث عنه الأدمن حين ينظّف.
import { useEffect, useState } from 'react';
import { api } from '../api';
import { Card, ConfirmButton, Icon, Notice, PageHead, Stat, Table } from '../components/ui';

export default function Groups() {
  const [groups, setGroups] = useState(null);
  const [search, setSearch] = useState('');
  const [error, setError] = useState('');
  const [busyId, setBusyId] = useState(null);

  useEffect(() => {
    const t = setTimeout(() => {
      api.get('/admin/groups', { params: { search } })
        .then(({ data }) => setGroups(data.groups))
        .catch(() => setError('تعذر تحميل المجموعات'));
    }, search ? 300 : 0);
    return () => clearTimeout(t);
  }, [search]);

  async function remove(group) {
    setBusyId(group.id);
    setError('');
    try {
      await api.delete(`/admin/groups/${group.id}`);
      setGroups(groups.filter((g) => g.id !== group.id));
    } catch (err) {
      setError(err.response?.data?.error || 'فشل الحذف');
    } finally {
      setBusyId(null);
    }
  }

  const total = groups?.length ?? 0;
  const members = groups?.reduce((s, g) => s + Number(g.members_count), 0) ?? 0;
  const empty = groups?.filter((g) => Number(g.members_count) <= 1).length ?? 0;

  return (
    <>
      <PageHead title="المجموعات" subtitle="دوريات خاصة ينشئها المستخدمون بكود دعوة" />

      <div className="grid cols-4" style={{ marginBottom: 14 }}>
        <Stat icon={Icon.group} label="المجموعات" value={total} />
        <Stat icon={Icon.users} label="مجموع العضويات" value={members} />
        <Stat
          icon={Icon.users}
          label="متوسط الأعضاء"
          value={total ? (members / total).toFixed(1) : '—'}
        />
        <Stat
          icon={Icon.alert}
          label="مجموعات فارغة"
          value={empty}
          note="مالكها فقط — لم تُستخدم"
          tone={empty > 0 ? 'alert' : undefined}
        />
      </div>

      <Card>
        <input
          className="search"
          placeholder="بحث بالاسم أو بريد المالك أو الرمز…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <Notice kind="error">{error}</Notice>
        {!groups ? (
          <p className="muted">جارِ التحميل…</p>
        ) : (
          <Table
            head={['الاسم', 'رمز الدعوة', 'المالك', 'الأعضاء', 'أُنشئت', '']}
            empty={groups.length === 0 ? 'لا مجموعات بعد' : null}
          >
            {groups.map((g) => (
              <tr key={g.id}>
                <td style={{ fontWeight: 600 }}>{g.name}</td>
                <td className="ltr">{g.invite_code}</td>
                <td className="ltr">{g.owner_email}</td>
                <td>
                  {Number(g.members_count) <= 1 ? (
                    <span className="badge">{g.members_count}</span>
                  ) : (
                    <span className="badge good">{g.members_count}</span>
                  )}
                </td>
                <td className="muted">{new Date(g.created_at).toLocaleDateString('ar-SA')}</td>
                <td>
                  <ConfirmButton
                    label="حذف"
                    busy={busyId === g.id}
                    onConfirm={() => remove(g)}
                  />
                </td>
              </tr>
            ))}
          </Table>
        )}
      </Card>
    </>
  );
}
