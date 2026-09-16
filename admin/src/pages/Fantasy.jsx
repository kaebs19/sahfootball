// «فريقي» — جدول نقاط الفانتازي، وأسعار اللاعبين وأسماؤهم.
//
// صفحةٌ مستقلة عن «نظام النقاط»: اللعبتان منفصلتان تماماً (راجع
// FANTASY.md)، وجمعُهما في شاشة واحدة يجعل تعديل سعر الهدف في
// الفانتازي يمرّ بجوار سعر «النتيجة المضبوطة» في التوقّعات — وأول
// خطأ نسخٍ هناك يفسد اللعبتين معاً.
import { useEffect, useState } from 'react';
import { api } from '../api';
import { Card, Notice, PageHead } from '../components/ui';

const POSITIONS = [
  { key: 'Goalkeeper', label: 'حارس' },
  { key: 'Defender', label: 'مدافع' },
  { key: 'Midfielder', label: 'وسط' },
  { key: 'Attacker', label: 'مهاجم' },
];

// الحقول الرقمية المفردة في جدول النقاط، بترتيب قراءتها لا ترتيب
// تخزينها: اللعب أولاً ثم ما يُكسب ثم ما يُخصم.
const SIMPLE = [
  { key: 'appearance', label: 'شارك (أقل من ٦٠ دقيقة)' },
  { key: 'full_appearance', label: 'لعب ٦٠ دقيقة فأكثر' },
  { key: 'assist', label: 'صناعة هدف' },
  { key: 'saves_per', label: 'كل كم تصدٍّ تُحتسب نقطة' },
  { key: 'save_points', label: 'نقاط التصديات' },
  { key: 'penalty_saved', label: 'صدّ ركلة جزاء' },
  { key: 'penalty_missed', label: 'أهدر ركلة جزاء' },
  { key: 'yellow', label: 'بطاقة صفراء' },
  { key: 'red', label: 'بطاقة حمراء' },
  { key: 'own_goal', label: 'هدف في مرماه' },
  { key: 'captain_multiplier', label: 'مضاعِف الكابتن' },
];

// الحقول التي تختلف بالمركز.
const BY_POSITION = [
  { key: 'goal', label: 'هدف' },
  { key: 'clean_sheet', label: 'شباك نظيفة' },
  { key: 'conceded_penalty', label: 'خصم كل هدفين يدخلان مرماه' },
];

export default function Fantasy() {
  const [scoring, setScoring] = useState(null);
  const [leagues, setLeagues] = useState([]);
  const [league, setLeague] = useState(null);
  const [players, setPlayers] = useState([]);
  const [query, setQuery] = useState('');
  const [position, setPosition] = useState('');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState(null);

  useEffect(() => {
    api.get('/admin/fantasy/scoring')
      .then(({ data }) => setScoring(data.scoring))
      .catch(() => setMessage({ type: 'error', text: 'تعذّر تحميل جدول النقاط' }));
    api.get('/admin/leagues')
      .then(({ data }) => {
        const inApp = (data.leagues || []).filter((l) => l.in_app);
        setLeagues(inApp);
        if (inApp.length) setLeague(inApp[0].id);
      })
      .catch(() => {});
  }, []);

  useEffect(() => {
    if (!league) return;
    loadPlayers();
    // البحث يُعاد تحميله من الخادم لا يُصفّى محلياً: القائمة ٣٠٠
    // صفّ من أصل آلاف، والتصفية المحلية تبحث في المعروض وحده
    // فتبدو وكأن اللاعب غير موجود.
  }, [league, position]);

  async function loadPlayers(q = query) {
    try {
      const { data } = await api.get('/admin/fantasy/players', {
        params: { league, q: q || undefined, position: position || undefined },
      });
      setPlayers(data.players || []);
    } catch (err) {
      setMessage({ type: 'error', text: err.response?.data?.error || 'تعذّر تحميل اللاعبين' });
    }
  }

  async function saveScoring(e) {
    e.preventDefault();
    setBusy(true);
    setMessage(null);
    try {
      const { data } = await api.put('/admin/fantasy/scoring', scoring);
      setScoring(data.scoring);
      setMessage({ type: 'ok', text: 'حُفظ الجدول — يسري على الجولات القادمة، ولا يعيد حساب ما مضى' });
    } catch (err) {
      setMessage({ type: 'error', text: err.response?.data?.error || 'فشل الحفظ' });
    } finally {
      setBusy(false);
    }
  }

  async function reprice() {
    setBusy(true);
    setMessage(null);
    try {
      const { data } = await api.post('/admin/fantasy/reprice', { league });
      setMessage({ type: 'ok', text: `أُعيد تسعير ${data.priced} لاعباً من أدائهم` });
      loadPlayers();
    } catch (err) {
      setMessage({ type: 'error', text: err.response?.data?.error || 'فشلت إعادة التسعير' });
    } finally {
      setBusy(false);
    }
  }

  async function savePlayer(id, patch) {
    try {
      const { data } = await api.put(`/admin/fantasy/players/${id}`, patch);
      setPlayers((list) =>
        list.map((p) => (p.id === id ? { ...p, ...data.player } : p)));
    } catch (err) {
      setMessage({ type: 'error', text: err.response?.data?.error || 'فشل الحفظ' });
    }
  }

  if (!scoring) {
    return (
      <>
        <PageHead title="فريقي" />
        <Card><p className="muted">جارِ التحميل…</p></Card>
      </>
    );
  }

  return (
    <>
      <PageHead
        title="فريقي"
        subtitle="جدول نقاط الفانتازي وأسعار اللاعبين — منفصل تماماً عن نقاط التوقّعات"
      />

      {message && <Notice kind={message.type}>{message.text}</Notice>}

      <form className="card" onSubmit={saveScoring}>
        <h2>جدول النقاط</h2>
        <p className="muted" style={{ marginBottom: 8 }}>
          نقاط الجولات المحتسبة مخزّنة ولا تتغيّر بتعديل الجدول — شاشة
          اللاعب تبقى كما رآها يوم الجولة.
        </p>

        <div className="grid cols-2">
          {SIMPLE.map(({ key, label }) => (
            <div className="field" key={key}>
              <label>{label}</label>
              <input
                type="number"
                dir="ltr"
                value={scoring[key] ?? 0}
                onChange={(e) =>
                  setScoring({ ...scoring, [key]: Number(e.target.value) })}
              />
            </div>
          ))}
        </div>

        {BY_POSITION.map(({ key, label }) => (
          <div key={key} style={{ marginTop: 14 }}>
            <label style={{ display: 'block', marginBottom: 6 }}>{label}</label>
            <div className="grid cols-4">
              {POSITIONS.map((p) => (
                <div className="field" key={p.key}>
                  <label><span className="hint">{p.label}</span></label>
                  <input
                    type="number"
                    dir="ltr"
                    value={scoring[key]?.[p.key] ?? 0}
                    onChange={(e) =>
                      setScoring({
                        ...scoring,
                        [key]: { ...scoring[key], [p.key]: Number(e.target.value) },
                      })}
                  />
                </div>
              ))}
            </div>
          </div>
        ))}

        <div className="actions">
          <button disabled={busy}>حفظ الجدول</button>
        </div>
      </form>

      <Card title="اللاعبون والأسعار">
        <p className="muted" style={{ marginBottom: 8 }}>
          السعر يُحتسب من الأداء. وما تضبطه بيدك يُوسم يدوياً فلا تدهسه
          إعادة التسعير — وهذا مقصود: الأرقام عمياء عن الإصابة والصفقة
          التي لم تلعب بعد.
        </p>

        <div className="toolbar">
          <select value={league || ''} onChange={(e) => setLeague(Number(e.target.value))}>
            {leagues.map((l) => (
              <option key={l.id} value={l.id}>{l.name_ar || l.name_en}</option>
            ))}
          </select>

          <select value={position} onChange={(e) => setPosition(e.target.value)}>
            <option value="">كل المراكز</option>
            {POSITIONS.map((p) => (
              <option key={p.key} value={p.key}>{p.label}</option>
            ))}
          </select>

          <input
            placeholder="ابحث باسم اللاعب"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && (e.preventDefault(), loadPlayers())}
          />
          <button type="button" className="ghost" onClick={() => loadPlayers()}>بحث</button>
          <button type="button" className="ghost" disabled={busy} onClick={reprice}>
            أعد التسعير من الأداء
          </button>
        </div>

        <table>
          <thead>
            <tr>
              <th>اللاعب</th>
              <th>النادي</th>
              <th>المركز</th>
              <th>مباريات</th>
              <th>نقاط</th>
              <th>السعر</th>
              <th>الاسم العربي</th>
              <th>متاح</th>
            </tr>
          </thead>
          <tbody>
            {players.map((p) => (
              <PlayerRow key={p.id} player={p} onSave={savePlayer} />
            ))}
            {!players.length && (
              <tr><td colSpan="8" className="muted">لا لاعبين — شغّل مزامنة القوائم أولاً.</td></tr>
            )}
          </tbody>
        </table>
      </Card>
    </>
  );
}

function PlayerRow({ player, onSave }) {
  const [price, setPrice] = useState(player.price);
  const [nameAr, setNameAr] = useState(player.name_ar || '');

  // الحفظ عند مغادرة الحقل لا عند كل حرف: طلبٌ لكل ضغطة مفتاح
  // يغرق الخادم، وزرُّ حفظٍ لكل صفّ في ثلاثمئة صفّ جدارٌ من الأزرار.
  return (
    <tr>
      <td>{player.name_ar || player.name_en}</td>
      <td className="muted">{player.team_name}</td>
      <td className="muted">
        {POSITIONS.find((x) => x.key === player.position)?.label || '—'}
      </td>
      <td dir="ltr">{player.apps}</td>
      <td dir="ltr">{player.total_points}</td>
      <td>
        <input
          type="number"
          step="0.5"
          dir="ltr"
          style={{ width: 70 }}
          value={price}
          onChange={(e) => setPrice(e.target.value)}
          onBlur={() => Number(price) !== Number(player.price)
            && onSave(player.id, { price: Number(price) })}
        />
        {player.manual_price && (
          <button
            type="button"
            className="ghost"
            title="أعِده إلى التسعير الآلي"
            style={{ marginRight: 6, padding: '2px 8px' }}
            onClick={() => onSave(player.id, { manual_price: false })}
          >
            يدوي
          </button>
        )}
      </td>
      <td>
        <input
          placeholder={player.name_en}
          value={nameAr}
          onChange={(e) => setNameAr(e.target.value)}
          onBlur={() => nameAr !== (player.name_ar || '')
            && onSave(player.id, { name_ar: nameAr })}
        />
      </td>
      <td>
        <input
          type="checkbox"
          checked={player.available}
          onChange={(e) => onSave(player.id, { available: e.target.checked })}
        />
      </td>
    </tr>
  );
}
