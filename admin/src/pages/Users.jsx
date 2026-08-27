// إدارة المستخدمين — قائمة وبحث، ومدخل لملف كل حساب.
//
// الأفعال الخطرة (تعليق، حذف) ليست هنا عمداً: صف في جدول ليس
// المكان المناسب لقرار لا رجعة فيه، والأدمن يجب أن يرى الحساب
// كاملاً — توقعاته ومجموعاته — قبل أن يحكم عليه. الجدول يعرض
// ويصفّي فقط، والأفعال في ملف المستخدم.
import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api } from '../api';
import { Avatar, Card, Icon, Notice, PageHead, Stat, Table } from '../components/ui';

const FILTERS = [
  { key: 'all', label: 'الكل' },
  { key: 'admin', label: 'الأدمن' },
  { key: 'suspended', label: 'المعلّقون' },
  { key: 'active', label: 'النشطون' },
];

export default function Users() {
  const [users, setUsers] = useState(null);
  const [search, setSearch] = useState('');
  const [filter, setFilter] = useState('all');
  const [error, setError] = useState('');

  // بحث مع مهلة (debounce): ننتظر 300ms بعد آخر حرف قبل الطلب —
  // بدونها كل ضغطة زر = طلب للسيرفر.
  useEffect(() => {
    const t = setTimeout(() => {
      api.get('/admin/users', { params: { search } })
        .then(({ data }) => setUsers(data.users))
        .catch(() => setError('تعذر تحميل المستخدمين'));
    }, search ? 300 : 0);
    return () => clearTimeout(t);
  }, [search]);

  // التصفية محلية لا على السيرفر: القائمة محدودة بمئتي صف أصلاً،
  // ورحلة شبكة لكل ضغطة شريحة ترف.
  const shown = users?.filter((u) => {
    if (filter === 'admin') return u.role === 'admin';
    if (filter === 'suspended') return Boolean(u.suspended_at);
    if (filter === 'active') return !u.suspended_at;
    return true;
  });

  const admins = users?.filter((u) => u.role === 'admin').length ?? 0;
  const suspended = users?.filter((u) => u.suspended_at).length ?? 0;
  const silent = users?.filter((u) => u.predictions_count === 0).length ?? 0;

  return (
    <>
      <PageHead
        title="المستخدمون"
        subtitle="اضغط أي صف لفتح ملف الحساب وإدارته"
      />

      <div className="grid cols-4" style={{ marginBottom: 14 }}>
        <Stat icon={Icon.users} label="الحسابات" value={users?.length ?? '…'} />
        <Stat icon={Icon.shield} label="أدمن" value={admins} tone="crown" />
        <Stat
          icon={Icon.alert}
          label="معلّقون"
          value={suspended}
          tone={suspended > 0 ? 'alert' : 'good'}
        />
        <Stat
          icon={Icon.ball}
          label="بلا أي توقع"
          value={silent}
          note="سجّلوا ولم يشاركوا"
        />
      </div>

      <Card>
        <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap', alignItems: 'center' }}>
          <input
            className="search"
            style={{ marginBottom: 0 }}
            placeholder="بحث بالبريد أو الاسم…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          <div className="chips">
            {FILTERS.map((f) => (
              <button
                key={f.key}
                type="button"
                className={`chip${filter === f.key ? ' active' : ''}`}
                onClick={() => setFilter(f.key)}
              >
                {f.label}
              </button>
            ))}
          </div>
        </div>

        <Notice kind="error">{error}</Notice>

        {!shown ? (
          <p className="muted" style={{ marginTop: 14 }}>جارِ التحميل…</p>
        ) : (
          <div style={{ marginTop: 14 }}>
            <Table
              head={['المستخدم', 'التسجيل', 'التوقعات', 'النقاط', 'الحالة', '']}
              empty={shown.length === 0 ? 'لا نتائج' : null}
            >
              {shown.map((u) => (
                <tr key={u.id} style={{ opacity: u.suspended_at ? 0.6 : 1 }}>
                  <td>
                    <Link
                      to={`/users/${u.id}`}
                      style={{ display: 'flex', alignItems: 'center', gap: 10 }}
                    >
                      <Avatar url={u.avatar_url} name={u.display_name || u.email} size={30} />
                      <span style={{ minWidth: 0 }}>
                        <div style={{ fontWeight: 600 }}>{u.display_name || 'بلا اسم'}</div>
                        <div className="ltr" style={{ fontSize: 11 }}>{u.email || '—'}</div>
                      </span>
                    </Link>
                  </td>
                  <td className="muted">{new Date(u.created_at).toLocaleDateString('ar-SA')}</td>
                  <td>{u.predictions_count}</td>
                  {/* النقاط ذهبية — القاعدة تحجز الذهبي لها */}
                  <td className="crown-text" style={{ fontWeight: 700 }}>{u.total_points}</td>
                  <td>
                    <div style={{ display: 'flex', gap: 5, flexWrap: 'wrap' }}>
                      {u.suspended_at && <span className="badge alert">معلّق</span>}
                      {u.role === 'admin' && <span className="badge crown">أدمن</span>}
                      {u.via_apple && <span className="badge">Apple</span>}
                      {!u.suspended_at && u.role !== 'admin' && !u.via_apple && (
                        <span className="muted">—</span>
                      )}
                    </div>
                  </td>
                  <td>
                    <Link to={`/users/${u.id}`} className="btn ghost small">
                      إدارة
                    </Link>
                  </td>
                </tr>
              ))}
            </Table>
          </div>
        )}
      </Card>
    </>
  );
}
