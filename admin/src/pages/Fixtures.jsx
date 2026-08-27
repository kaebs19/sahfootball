// المباريات — عرض وفلترة بالحالة والدوري، مع عدد التوقعات.
import { useEffect, useState } from 'react';
import { api } from '../api';
import { Card, Notice, PageHead, Table } from '../components/ui';

const FILTERS = [
  { key: 'scheduled', label: 'قادمة' },
  { key: 'live', label: 'مباشرة' },
  { key: 'finished', label: 'منتهية' },
  { key: 'all', label: 'الكل' },
];

const STATUS_AR = {
  scheduled: 'قادمة',
  live: 'مباشرة',
  finished: 'انتهت',
  postponed: 'مؤجلة',
  cancelled: 'ملغاة',
};

export default function Fixtures() {
  const [status, setStatus] = useState('scheduled');
  const [league, setLeague] = useState('');
  const [leagues, setLeagues] = useState([]);
  const [fixtures, setFixtures] = useState(null);
  const [error, setError] = useState('');

  // قائمة الدوريات للمرشّح. لو لم يكن المسار جاهزاً بعد نتجاهله
  // بهدوء — الصفحة تبقى تعمل بمرشّح الحالة وحده.
  useEffect(() => {
    api.get('/admin/leagues')
      .then(({ data }) => setLeagues(data.leagues ?? []))
      .catch(() => {});
  }, []);

  useEffect(() => {
    setFixtures(null);
    setError('');
    api.get('/admin/fixtures', { params: { status, ...(league ? { league } : {}) } })
      .then(({ data }) => setFixtures(data.fixtures))
      .catch(() => setError('تعذر تحميل المباريات'));
  }, [status, league]);

  const withPredictions = fixtures?.filter((f) => f.predictions_count > 0).length ?? 0;

  return (
    <>
      <PageHead
        title="المباريات"
        subtitle={
          fixtures
            ? `${fixtures.length} مباراة · ${withPredictions} عليها توقعات`
            : 'جارِ التحميل…'
        }
      />

      <Card>
        <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap', alignItems: 'center', marginBottom: 14 }}>
          <div className="chips">
            {FILTERS.map((f) => (
              <button
                key={f.key}
                type="button"
                className={`chip${status === f.key ? ' active' : ''}`}
                onClick={() => setStatus(f.key)}
              >
                {f.label}
              </button>
            ))}
          </div>
          {leagues.length > 1 && (
            <select
              style={{ width: 'auto', minWidth: 170 }}
              value={league}
              onChange={(e) => setLeague(e.target.value)}
            >
              <option value="">كل الدوريات</option>
              {leagues.map((l) => (
                <option key={l.id} value={l.id}>
                  {l.name_ar || l.name_en}
                </option>
              ))}
            </select>
          )}
        </div>

        <Notice kind="error">{error}</Notice>

        {!fixtures ? (
          <p className="muted">جارِ التحميل…</p>
        ) : (
          <Table
            head={['الجولة', 'المباراة', 'النتيجة / الموعد', 'الحالة', 'التوقعات']}
            empty={fixtures.length === 0 ? 'لا مباريات بهذه المرشّحات' : null}
          >
            {fixtures.map((f) => (
              <tr key={f.id}>
                <td className="faint">{shortRound(f.round)}</td>
                <td>
                  <span className="match">
                    <img className="team-logo" src={f.home_team_logo} alt="" />
                    {f.home_team_name}
                    <span className="faint">×</span>
                    {f.away_team_name}
                    <img className="team-logo" src={f.away_team_logo} alt="" />
                  </span>
                </td>
                <td className="ltr" style={{ fontWeight: 600, color: 'var(--text)' }}>
                  {f.goals_home !== null
                    ? `${f.goals_home} - ${f.goals_away}`
                    : formatKickoff(f.kickoff_at)}
                </td>
                <td>
                  <span className={`badge badge-${f.status}`}>{STATUS_AR[f.status] || f.status}</span>
                </td>
                <td>
                  {f.predictions_count > 0 ? (
                    <span className="badge crown">{f.predictions_count}</span>
                  ) : (
                    <span className="faint">0</span>
                  )}
                </td>
              </tr>
            ))}
          </Table>
        )}
      </Card>
    </>
  );
}

// "Regular Season - 12" ← "ج12" — التسمية الكاملة ضجيج في جدول ضيق.
function shortRound(round) {
  const m = /(\d+)\s*$/.exec(round || '');
  return m ? `ج${m[1]}` : round || '—';
}

function formatKickoff(iso) {
  return new Date(iso).toLocaleString('ar-SA', {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}
