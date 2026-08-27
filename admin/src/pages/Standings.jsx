// جدول الترتيب.
//
// الترتيب لا يُخزَّن عندنا (بيانات مشتقة يحسبها المزود)، فالصفحة
// تقرأه حيّاً خلف كاش السيرفر. هذا يعني أن كل تبديل دوري قد يكلف
// طلباً من الحصة اليومية إن لم يكن مخزّناً — نعرض تنبيهاً بذلك
// بدل أن يكتشفه الأدمن من نفاد الحصة.
import { useEffect, useState } from 'react';
import { api } from '../api';
import { Card, Notice, PageHead, Table } from '../components/ui';

/** آخر خمس نتائج كنقاط ملوّنة.
 *
 * المزود يرسلها نصاً مثل "WWDLW" مرتباً من الأقدم للأحدث. نعرض
 * الأحدث خمساً فقط: السلسلة الكاملة قد تبلغ ثلاثين حرفاً وتكسر
 * عرض الجدول، والقارئ يهمّه الاتجاه الأخير لا كل الموسم.
 */
function Form({ value }) {
  if (!value) return <span className="faint">—</span>;
  const last = value.slice(-5).split('');
  const color = { W: 'var(--correct)', D: 'var(--text-faint)', L: 'var(--wrong)' };
  return (
    <span style={{ display: 'inline-flex', gap: 3, direction: 'ltr' }}>
      {last.map((c, i) => (
        <span
          key={i}
          title={c === 'W' ? 'فوز' : c === 'D' ? 'تعادل' : 'خسارة'}
          style={{
            width: 7,
            height: 7,
            borderRadius: 999,
            background: color[c] ?? 'var(--fill-strong)',
          }}
        />
      ))}
    </span>
  );
}

export default function Standings() {
  const [leagues, setLeagues] = useState([]);
  const [league, setLeague] = useState('');
  // نعرف أن قائمة الدوريات وصلت — وليس فقط أنها فارغة بعد.
  const [leaguesReady, setLeaguesReady] = useState(false);
  const [rows, setRows] = useState(null);
  const [error, setError] = useState('');

  useEffect(() => {
    api.get('/admin/leagues')
      .then(({ data }) => {
        const list = data.leagues ?? [];
        setLeagues(list);
        const first = list.find((l) => l.enabled) ?? list[0];
        if (first) setLeague(String(first.id));
      })
      .catch(() => {})
      .finally(() => setLeaguesReady(true));
  }, []);

  // ننتظر وصول قائمة الدوريات قبل أول طلب ترتيب.
  //
  // ليس تحسيناً تجميلياً: الطلب المبكر (بلا دوري) ثم الطلب الصحيح
  // بعد وصول القائمة = رحلتان للمزود بدل واحدة، والخطة المجانية
  // مئة طلب في اليوم كلها.
  useEffect(() => {
    if (!leaguesReady) return;
    setRows(null);
    setError('');
    const params = league ? { league } : {};
    api.get('/admin/standings', { params })
      .then(({ data }) => setRows(data.standings))
      .catch((err) =>
        setError(err.response?.data?.error || 'تعذر تحميل الترتيب — قد تكون حصة API قد نفدت')
      );
  }, [league, leaguesReady]);

  const current = leagues.find((l) => String(l.id) === String(league));

  return (
    <>
      <PageHead
        title="الترتيب"
        subtitle="يُجلب حيّاً من المزود ولا يُخزَّن — بيانات مشتقة تتغير بعد كل جولة"
      >
        {leagues.length > 1 && (
          <select
            style={{ width: 'auto', minWidth: 190 }}
            value={league}
            onChange={(e) => setLeague(e.target.value)}
          >
            {leagues.map((l) => (
              <option key={l.id} value={l.id}>
                {l.name_ar || l.name_en}
              </option>
            ))}
          </select>
        )}
      </PageHead>

      <Card
        title={current ? `${current.name_ar || current.name_en} · موسم ${current.season}` : undefined}
      >
        <Notice kind="error">{error}</Notice>
        {!rows && !error ? (
          <p className="muted">جارِ التحميل…</p>
        ) : !rows ? null : (
          <Table
            head={['#', 'الفريق', 'لعب', 'فاز', 'تعادل', 'خسر', 'له', 'عليه', '+/-', 'الفورمة', 'النقاط']}
            empty={rows.length === 0 ? 'لا ترتيب متاح لهذا الموسم' : null}
          >
            {rows.map((r) => (
              <tr key={r.team_id}>
                <td style={{ width: 40 }}>
                  {/* الثلاثة الأوائل فقط يأخذون الذهبي: الصدارة رتبة،
                      وهي الاستعمال الذي تحجزه الهوية للذهبي. */}
                  <span className={r.rank <= 3 ? 'badge crown' : 'muted'}>{r.rank}</span>
                </td>
                <td>
                  <span className="match">
                    {r.logo_url && <img className="team-logo" src={r.logo_url} alt="" />}
                    <span style={{ fontWeight: 600 }}>{r.team_name}</span>
                  </span>
                </td>
                <td className="muted">{r.played}</td>
                <td>{r.win}</td>
                <td className="muted">{r.draw}</td>
                <td className="muted">{r.lose}</td>
                <td className="muted">{r.goals_for}</td>
                <td className="muted">{r.goals_against}</td>
                <td className={r.goals_diff > 0 ? 'ok' : r.goals_diff < 0 ? 'error' : 'muted'}>
                  {r.goals_diff > 0 ? `+${r.goals_diff}` : r.goals_diff}
                </td>
                <td><Form value={r.form} /></td>
                <td className="crown-text" style={{ fontWeight: 700, fontSize: 15 }}>
                  {r.points}
                </td>
              </tr>
            ))}
          </Table>
        )}
      </Card>
    </>
  );
}
