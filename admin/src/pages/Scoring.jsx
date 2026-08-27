// نظام النقاط — قيم الاحتساب وتشغيله يدوياً.
import { useEffect, useState } from 'react';
import { api } from '../api';
import { Card, Icon, Notice, PageHead, Stat } from '../components/ui';

const FIELDS = [
  { key: 'exact', label: 'النتيجة بالضبط', hint: 'توقّع 2-1 وانتهت 2-1' },
  { key: 'diff', label: 'فارق الأهداف صحيح', hint: 'توقّع 2-1 وانتهت 3-2' },
  { key: 'outcome', label: 'الاتجاه فقط', hint: 'توقّع فوز الفريق وفاز بأي نتيجة' },
];

export default function Scoring() {
  const [scoring, setScoring] = useState(null);
  const [pending, setPending] = useState(null);
  const [message, setMessage] = useState(null);
  const [busy, setBusy] = useState(false);

  function loadPending() {
    api.get('/admin/stats')
      .then(({ data }) => setPending(data.pending_settlement ?? 0))
      .catch(() => {});
  }

  useEffect(() => {
    api.get('/admin/settings/scoring')
      .then(({ data }) => setScoring(data.scoring))
      .catch(() => setMessage({ type: 'error', text: 'تعذر تحميل الإعدادات' }));
    loadPending();
  }, []);

  if (!scoring) {
    return (
      <>
        <PageHead title="نظام النقاط" />
        <Card><p className="muted">جارِ التحميل…</p></Card>
      </>
    );
  }

  async function save(e) {
    e.preventDefault();
    setBusy(true);
    setMessage(null);
    try {
      const { data } = await api.put('/admin/settings/scoring', scoring);
      setScoring(data.scoring);
      setMessage({ type: 'ok', text: 'حُفظت الإعدادات — تسري على الاحتسابات القادمة' });
    } catch (err) {
      setMessage({ type: 'error', text: err.response?.data?.error || 'فشل الحفظ' });
    } finally {
      setBusy(false);
    }
  }

  async function settleNow() {
    setBusy(true);
    setMessage(null);
    try {
      const { data } = await api.post('/admin/settle');
      setMessage({ type: 'ok', text: `تم احتساب ${data.settled} توقعاً` });
      loadPending();
    } catch {
      setMessage({ type: 'error', text: 'فشل الاحتساب' });
    } finally {
      setBusy(false);
    }
  }

  // ترتيب مقلوب يفسد عدالة اللعبة — السيرفر يرفضه، ونحذّر قبله.
  const inverted = !(scoring.exact >= scoring.diff && scoring.diff >= scoring.outcome);

  return (
    <>
      <PageHead
        title="نظام النقاط"
        subtitle="تسري القيم الجديدة على ما يُحتسب بعد الحفظ، ولا تُعاد على القديم"
      />

      <div className="grid cols-2">
        <form className="card" onSubmit={save}>
          <h2>قيم النقاط</h2>
          <p className="muted" style={{ marginBottom: 8 }}>
            كل توقّع يأخذ أعلى قيمة تنطبق عليه فقط، لا مجموعها.
          </p>
          {FIELDS.map(({ key, label, hint }) => (
            <div className="field" key={key}>
              <label>
                {label}
                <span className="hint">{hint}</span>
              </label>
              <input
                type="number"
                min="0"
                max="100"
                dir="ltr"
                value={scoring[key]}
                onChange={(e) => setScoring({ ...scoring, [key]: Number(e.target.value) })}
              />
            </div>
          ))}

          {inverted && (
            <Notice kind="error">
              الأدق يجب أن يستحق أكثر: النتيجة بالضبط ≥ فارق الأهداف ≥ الاتجاه.
            </Notice>
          )}
          {message && <Notice kind={message.type}>{message.text}</Notice>}

          <div className="actions">
            <button disabled={busy || inverted}>حفظ</button>
          </div>
        </form>

        <div className="grid" style={{ alignContent: 'start' }}>
          <Stat
            icon={Icon.alert}
            label="توقعات تنتظر الاحتساب"
            value={pending ?? '…'}
            note={
              pending === 0
                ? 'كل ما انتهى محتسب'
                : 'مباريات انتهت ولم تُحتسب توقعاتها بعد'
            }
            tone={pending > 0 ? 'alert' : 'good'}
          />
          <Card title="الاحتساب اليدوي">
            <p className="muted" style={{ marginBottom: 4 }}>
              الاحتساب يعمل تلقائياً بعد كل مزامنة. هذا الزر للحالات الطارئة:
              بعد تعديل القيم، أو لو تعطّل المجدول.
            </p>
            <p className="muted">
              العملية آمنة للتكرار — التوقع المحتسب لا يُحتسب مرتين.
            </p>
            <div className="actions">
              <button type="button" className="ghost" disabled={busy} onClick={settleNow}>
                احتساب النقاط الآن
              </button>
            </div>
          </Card>
        </div>
      </div>
    </>
  );
}
