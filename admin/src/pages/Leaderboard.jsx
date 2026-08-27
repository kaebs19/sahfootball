// العرش — نفس ما يراه المستخدمون في التطبيق (المسار العام).
//
// سلّم الرتب مكرَّر هنا وفي تطبيق الجوال عمداً: هو قرار عرض لا
// حقيقة في القاعدة، والسيرفر لا يرسله. لو أصبح للرتب أثر فعلي
// (صلاحيات، مكافآت) وجب نقله للسيرفر ليكون مصدراً واحداً.
import { useEffect, useState } from 'react';
import { api } from '../api';
import { Card, Icon, PageHead, Stat, Table } from '../components/ui';

const RANKS = [
  { from: 5000, label: 'الملك' },
  { from: 3000, label: 'أمير' },
  { from: 1500, label: 'فارس' },
  { from: 500, label: 'لاعب' },
  { from: 0, label: 'مشجّع' },
];

const rankOf = (points) => RANKS.find((r) => points >= r.from).label;

export default function Leaderboard() {
  const [rows, setRows] = useState(null);
  const [error, setError] = useState('');

  useEffect(() => {
    api.get('/leaderboard')
      .then(({ data }) => setRows(data.leaderboard))
      .catch(() => setError('تعذر تحميل العرش'));
  }, []);

  const totalPoints = rows?.reduce((s, r) => s + r.total_points, 0) ?? 0;
  const totalSettled = rows?.reduce((s, r) => s + r.settled_predictions, 0) ?? 0;

  return (
    <>
      <PageHead title="العرش" subtitle="الترتيب العام كما يظهر للمستخدمين في التطبيق" />

      {rows && rows.length > 0 && (
        <div className="grid cols-4" style={{ marginBottom: 14 }}>
          <Stat icon={Icon.trophy} label="المتصدّر" value={rows[0].display_name} tone="crown" />
          <Stat icon={Icon.users} label="متنافسون" value={rows.length} />
          <Stat icon={Icon.scoring} label="مجموع النقاط" value={totalPoints} tone="crown" />
          <Stat
            icon={Icon.ball}
            label="متوسط النقطة للتوقّع"
            value={totalSettled ? (totalPoints / totalSettled).toFixed(2) : '—'}
            note="مؤشر على سخاء نظام النقاط"
          />
        </div>
      )}

      <Card>
        {error && <p className="error">{error}</p>}
        {!rows ? (
          <p className="muted">جارِ التحميل…</p>
        ) : (
          <Table
            head={['المركز', 'الاسم', 'الرتبة', 'النقاط', 'توقعات محتسبة']}
            empty={rows.length === 0 ? 'لا توقعات محتسبة بعد' : null}
          >
            {rows.map((r) => (
              <tr key={r.user_id}>
                <td style={{ width: 60 }}>
                  {/* المركز الأول ذهبي مصمت والتاليان ذهبي خافت — تدرّج
                      بلون واحد بدل ثلاثة ألوان ميداليات، فالهوية لا
                      تسمح بلون ثالث. */}
                  <span
                    className={r.rank === 1 ? 'badge crown' : r.rank <= 3 ? 'badge' : 'muted'}
                    style={r.rank === 1 ? { background: 'var(--crown)', color: 'var(--on-accent)' } : undefined}
                  >
                    {r.rank}
                  </span>
                </td>
                <td style={{ fontWeight: 600 }}>{r.display_name}</td>
                <td className="muted">{rankOf(r.total_points)}</td>
                <td className="crown-text" style={{ fontWeight: 700, fontSize: 15 }}>
                  {r.total_points}
                </td>
                <td className="muted">{r.settled_predictions}</td>
              </tr>
            ))}
          </Table>
        )}
      </Card>
    </>
  );
}
