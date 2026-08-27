// ملف الأدمن الشخصي — الصورة والاسم والبريد وكلمة المرور.
//
// لماذا ثلاث بطاقات منفصلة لا نموذج واحد بزر حفظ؟ لأن الحقول هنا
// ليست من نوع واحد: الاسم تعديل عادي، والبريد وكلمة المرور
// عمليتان حسّاستان يطلب كل منهما كلمة المرور الحالية ويعيد إصدار
// الجلسة. دمجها في نموذج واحد كان سيجعل تغيير الاسم يطلب كلمة
// المرور بلا سبب، ويجعل فشل أحدها يبهم أيّها فشل.
import { useEffect, useRef, useState } from 'react';
import { api, store } from '../api';
import { Avatar, Card, Notice, PageHead } from '../components/ui';

export default function Profile() {
  const [me, setMe] = useState(null);
  const [error, setError] = useState('');

  useEffect(() => {
    api.get('/auth/me')
      .then(({ data }) => setMe(data.user))
      .catch(() => setError('تعذر تحميل بياناتك'));
  }, []);

  if (!me) {
    return (
      <>
        <PageHead title="حسابي" />
        <Card><p className="muted">{error || 'جارِ التحميل…'}</p></Card>
      </>
    );
  }

  return (
    <>
      <PageHead title="حسابي" subtitle="بياناتك أنت — لا تخص المستخدمين" />
      <div className="grid cols-2">
        <div className="grid" style={{ alignContent: 'start' }}>
          <AvatarCard me={me} onChange={setMe} />
          <NameCard me={me} onChange={setMe} />
        </div>
        <div className="grid" style={{ alignContent: 'start' }}>
          <EmailCard me={me} onChange={setMe} />
          <PasswordCard />
        </div>
      </div>
    </>
  );
}

/** الصورة الشخصية — رفع واستبدال وحذف. */
function AvatarCard({ me, onChange }) {
  const fileRef = useRef(null);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState(null);

  async function upload(file) {
    if (!file) return;
    // نفحص الحجم قبل الرفع: السيرفر يرفض ما فوق 2MB، لكن انتظار
    // رحلة كاملة لملف كبير ثم رفضه تجربة سيئة.
    if (file.size > 2 * 1024 * 1024) {
      return setMsg({ type: 'error', text: 'الصورة أكبر من 2 ميجابايت' });
    }
    setBusy(true);
    setMsg(null);
    try {
      const form = new FormData();
      form.append('avatar', file);
      const { data } = await api.post('/profile/avatar', form);
      onChange(data.user);
      setMsg({ type: 'ok', text: 'حُدّثت الصورة' });
    } catch (err) {
      setMsg({ type: 'error', text: err.response?.data?.error || 'فشل الرفع' });
    } finally {
      setBusy(false);
      // نصفّر الحقل كي يعمل اختيار *نفس* الملف مرة أخرى — بدونها
      // لا يطلق المتصفح حدث change حين لا تتغير القيمة.
      if (fileRef.current) fileRef.current.value = '';
    }
  }

  async function removeAvatar() {
    setBusy(true);
    setMsg(null);
    try {
      await api.delete('/profile/avatar');
      onChange({ ...me, avatar_url: null });
    } catch {
      setMsg({ type: 'error', text: 'فشل الحذف' });
    } finally {
      setBusy(false);
    }
  }

  return (
    <Card title="الصورة الشخصية" subtitle="jpeg أو png أو webp، حتى 2 ميجابايت">
      <div style={{ display: 'flex', alignItems: 'center', gap: 16, marginTop: 12 }}>
        <Avatar url={me.avatar_url} name={me.display_name || me.email} size={72} />
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          <input
            ref={fileRef}
            type="file"
            accept="image/jpeg,image/png,image/webp"
            style={{ display: 'none' }}
            onChange={(e) => upload(e.target.files?.[0])}
          />
          <button
            type="button"
            className="small"
            disabled={busy}
            onClick={() => fileRef.current?.click()}
          >
            {busy ? '…' : me.avatar_url ? 'تغيير الصورة' : 'رفع صورة'}
          </button>
          {me.avatar_url && (
            <button type="button" className="ghost small" disabled={busy} onClick={removeAvatar}>
              إزالة
            </button>
          )}
        </div>
      </div>
      {msg && <Notice kind={msg.type}>{msg.text}</Notice>}
    </Card>
  );
}

function NameCard({ me, onChange }) {
  const [name, setName] = useState(me.display_name || '');
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState(null);
  const dirty = name.trim() !== (me.display_name || '');

  async function save(e) {
    e.preventDefault();
    setBusy(true);
    setMsg(null);
    try {
      const { data } = await api.put('/profile', { displayName: name.trim() });
      onChange(data.user);
      setMsg({ type: 'ok', text: 'حُفظ الاسم' });
    } catch (err) {
      setMsg({ type: 'error', text: err.response?.data?.error || 'فشل الحفظ' });
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className="card" onSubmit={save}>
      <h2>الاسم المعروض</h2>
      <p className="muted" style={{ marginBottom: 12 }}>
        يظهر في العرش وفي المجموعات التي تشارك فيها.
      </p>
      <input value={name} onChange={(e) => setName(e.target.value)} />
      {msg && <Notice kind={msg.type}>{msg.text}</Notice>}
      <div className="actions">
        <button disabled={busy || !dirty}>حفظ</button>
      </div>
    </form>
  );
}

function EmailCard({ me, onChange }) {
  const [email, setEmail] = useState(me.email || '');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState(null);
  const dirty = email.trim().toLowerCase() !== (me.email || '').toLowerCase();

  async function save(e) {
    e.preventDefault();
    setBusy(true);
    setMsg(null);
    try {
      const { data } = await api.put('/auth/email', {
        newEmail: email.trim(),
        currentPassword: password,
      });
      if (data.accessToken) store.save(data);
      onChange(data.user ?? { ...me, email: email.trim().toLowerCase() });
      setPassword('');
      setMsg({ type: 'ok', text: 'تغيّر البريد' });
    } catch (err) {
      setMsg({ type: 'error', text: err.response?.data?.error || 'فشل التغيير' });
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className="card" onSubmit={save}>
      <h2>البريد الإلكتروني</h2>
      <p className="muted" style={{ marginBottom: 12 }}>
        هو ما تسجّل به الدخول. نطلب كلمة المرور الحالية لأن جلسة
        مفتوحة بلا صاحبها يجب ألا تكفي للاستيلاء على الحساب.
      </p>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 9 }}>
        <label className="muted" style={{ fontSize: 12.5 }}>
          البريد الجديد
          <input dir="ltr" type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
        </label>
        <label className="muted" style={{ fontSize: 12.5 }}>
          كلمة المرور الحالية
          <input
            dir="ltr"
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            autoComplete="current-password"
          />
        </label>
      </div>
      {msg && <Notice kind={msg.type}>{msg.text}</Notice>}
      <div className="actions">
        <button disabled={busy || !dirty || !password}>تغيير البريد</button>
      </div>
    </form>
  );
}

function PasswordCard() {
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [confirm, setConfirm] = useState('');
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState(null);

  const mismatch = confirm.length > 0 && next !== confirm;
  const ready = current && next.length >= 8 && next === confirm;

  async function save(e) {
    e.preventDefault();
    setBusy(true);
    setMsg(null);
    try {
      const { data } = await api.post('/auth/change-password', {
        currentPassword: current,
        newPassword: next,
      });
      // السيرفر يبطل الجلسات القديمة ويصدر توكنات جديدة — نحفظها
      // وإلا خرجنا من اللوحة فور نجاح العملية.
      if (data.accessToken) store.save(data);
      setCurrent('');
      setNext('');
      setConfirm('');
      setMsg({ type: 'ok', text: 'تغيّرت كلمة المرور — أُنهيت جلساتك الأخرى' });
    } catch (err) {
      setMsg({ type: 'error', text: err.response?.data?.error || 'فشل التغيير' });
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className="card" onSubmit={save}>
      <h2>كلمة المرور</h2>
      <p className="muted" style={{ marginBottom: 12 }}>
        تغييرها ينهي جلساتك على الأجهزة الأخرى.
      </p>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 9 }}>
        <label className="muted" style={{ fontSize: 12.5 }}>
          الحالية
          <input
            dir="ltr"
            type="password"
            value={current}
            onChange={(e) => setCurrent(e.target.value)}
            autoComplete="current-password"
          />
        </label>
        <label className="muted" style={{ fontSize: 12.5 }}>
          الجديدة (8 أحرف على الأقل)
          <input
            dir="ltr"
            type="password"
            value={next}
            onChange={(e) => setNext(e.target.value)}
            autoComplete="new-password"
          />
        </label>
        <label className="muted" style={{ fontSize: 12.5 }}>
          تأكيد الجديدة
          <input
            dir="ltr"
            type="password"
            value={confirm}
            onChange={(e) => setConfirm(e.target.value)}
            autoComplete="new-password"
          />
        </label>
      </div>
      {mismatch && <Notice kind="error">الكلمتان غير متطابقتين</Notice>}
      {msg && <Notice kind={msg.type}>{msg.text}</Notice>}
      <div className="actions">
        <button disabled={busy || !ready}>تغيير كلمة المرور</button>
      </div>
    </form>
  );
}
