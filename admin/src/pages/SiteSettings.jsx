// إعدادات الموقع — الاسم والوصف وقنوات التواصل وروابط المتاجر.
//
// كل قيمة هنا تظهر في الموقع العام وفي تذييل كل صفحة. الحقول
// الفارغة تختفي من الموقع بدل أن تظهر كروابط ميتة — لذلك ترك حقل
// فارغاً قرار صالح لا نقص في الإدخال، والنص المساعد يقول ذلك.
import { useEffect, useState } from 'react';
import { api, API_ORIGIN } from '../api';
import { Card, Icon, Notice, PageHead, Svg } from '../components/ui';

const SOCIAL = [
  ['x', 'X (تويتر)', 'https://x.com/…'],
  ['instagram', 'إنستقرام', 'https://instagram.com/…'],
  ['tiktok', 'تيك توك', 'https://tiktok.com/@…'],
  ['youtube', 'يوتيوب', 'https://youtube.com/@…'],
  ['snapchat', 'سناب شات', 'https://snapchat.com/add/…'],
  ['linkedin', 'لينكدإن', 'https://linkedin.com/company/…'],
];

const EMPTY = {
  siteName: '',
  tagline: '',
  description: '',
  contactEmail: '',
  supportEmail: '',
  appStoreUrl: '',
  googlePlayUrl: '',
  social: {},
};

export default function SiteSettings() {
  const [saved, setSaved] = useState(null);
  const [form, setForm] = useState(null);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState(null);

  async function load() {
    const { data } = await api.get('/admin/site/settings');
    const s = { ...EMPTY, ...(data.settings || {}), social: { ...(data.settings?.social || {}) } };
    setSaved(s);
    setForm(s);
  }

  useEffect(() => {
    load().catch(() => setMsg({ type: 'error', text: 'تعذّر تحميل الإعدادات' }));
  }, []);

  if (!form) {
    return (
      <>
        <PageHead title="إعدادات الموقع" />
        <Card><p className="muted">{msg?.text || 'جارِ التحميل…'}</p></Card>
      </>
    );
  }

  const dirty = JSON.stringify(form) !== JSON.stringify(saved);
  const set = (patch) => { setForm({ ...form, ...patch }); setMsg(null); };
  const setSocial = (key, value) => set({ social: { ...form.social, [key]: value } });

  // تحقق محلي يوازي تحقق السيرفر: رسالة فورية بلا رحلة شبكة،
  // والسيرفر يبقى الحكم النهائي.
  const badUrl = (v) => v && !/^https?:\/\/.+/i.test(v.trim());
  const badEmail = (v) => v && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v.trim());

  const problems = [
    badEmail(form.contactEmail) && 'بريد التواصل غير صحيح',
    badEmail(form.supportEmail) && 'بريد الدعم غير صحيح',
    badUrl(form.appStoreUrl) && 'رابط App Store يجب أن يبدأ بـ https://',
    badUrl(form.googlePlayUrl) && 'رابط Google Play يجب أن يبدأ بـ https://',
    ...SOCIAL.filter(([k]) => badUrl(form.social[k])).map(([, label]) => `رابط ${label} غير صحيح`),
  ].filter(Boolean);

  async function save(e) {
    e.preventDefault();
    setBusy(true);
    setMsg(null);
    try {
      const { data } = await api.put('/admin/site/settings', form);
      const s = { ...EMPTY, ...(data.settings || {}), social: { ...(data.settings?.social || {}) } };
      setSaved(s);
      setForm(s);
      setMsg({ type: 'ok', text: 'حُفظت الإعدادات — ظاهرة على الموقع الآن' });
    } catch (err) {
      setMsg({ type: 'error', text: err.response?.data?.error || 'فشل الحفظ' });
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={save}>
      <PageHead
        title="إعدادات الموقع"
        subtitle="الاسم والوصف وقنوات التواصل — تظهر في تذييل كل صفحة"
      >
        <a className="btn ghost" href={API_ORIGIN} target="_blank" rel="noopener noreferrer">
          افتح الموقع
        </a>
        <button disabled={busy || !dirty || problems.length > 0}>
          {busy ? '…' : 'حفظ'}
        </button>
      </PageHead>

      {problems.length > 0 && <Notice kind="error">{problems.join(' · ')}</Notice>}
      {msg && <Notice kind={msg.type}>{msg.text}</Notice>}

      <div className="grid cols-2">
        <div className="grid" style={{ alignContent: 'start' }}>
          <Card title="الهوية" subtitle="ما يراه الزائر في الترويسة والصفحة الرئيسية">
            <Field label="اسم الموقع" value={form.siteName}
                   onChange={(v) => set({ siteName: v })} />
            <Field label="الشعار النصي" hint="سطر قصير تحت الاسم"
                   value={form.tagline} onChange={(v) => set({ tagline: v })} />
            <Field label="الوصف" hint="فقرة قصيرة — تُستعمل أيضاً في نتائج البحث والمشاركة"
                   textarea value={form.description} onChange={(v) => set({ description: v })} />
          </Card>

          <Card title="التواصل">
            <Field label="بريد التواصل" ltr placeholder="hello@example.com"
                   value={form.contactEmail} onChange={(v) => set({ contactEmail: v })} />
            <Field label="بريد الدعم" ltr hint="اتركه فارغاً لو نفس بريد التواصل"
                   placeholder="support@example.com"
                   value={form.supportEmail} onChange={(v) => set({ supportEmail: v })} />
          </Card>

          <Card title="روابط المتاجر" subtitle="تظهر كأزرار تحميل في الصفحة الرئيسية">
            <Field label="App Store" ltr placeholder="https://apps.apple.com/…"
                   value={form.appStoreUrl} onChange={(v) => set({ appStoreUrl: v })} />
            <Field label="Google Play" ltr placeholder="https://play.google.com/…"
                   value={form.googlePlayUrl} onChange={(v) => set({ googlePlayUrl: v })} />
            <p className="faint" style={{ fontSize: 12, marginTop: 4 }}>
              ما دام الحقلان فارغين تعرض الصفحة الرئيسية دعوة للتواصل بدل أزرار
              تحميل لا تقود إلى شيء.
            </p>
          </Card>
        </div>

        <div className="grid" style={{ alignContent: 'start' }}>
          <Card
            title="حسابات التواصل"
            subtitle="الحساب الفارغ لا تظهر أيقونته إطلاقاً — لا رابط ميت"
          >
            {SOCIAL.map(([key, label, placeholder]) => (
              <Field
                key={key}
                label={label}
                ltr
                placeholder={placeholder}
                value={form.social[key] || ''}
                onChange={(v) => setSocial(key, v)}
              />
            ))}
          </Card>

          <Card royal>
            <div style={{ display: 'flex', gap: 10, alignItems: 'flex-start' }}>
              <Svg path={Icon.alert} size={16} />
              <p className="muted" style={{ margin: 0 }}>
                رابط سياسة الخصوصية الذي ستعطيه لـ App Store هو{' '}
                <code className="ltr">{API_ORIGIN}/privacy</code> — تأكد أنه يفتح
                من خارج جهازك قبل تقديم التطبيق.
              </p>
            </div>
          </Card>
        </div>
      </div>
    </form>
  );
}

function Field({ label, hint, value, onChange, ltr, textarea, placeholder }) {
  const style = {
    marginTop: 5,
    ...(ltr ? { direction: 'ltr', textAlign: 'start' } : {}),
  };
  return (
    <label className="muted" style={{ fontSize: 12.5, display: 'block', marginBottom: 12 }}>
      {label}
      {hint && <span className="faint" style={{ fontSize: 11.5, display: 'block' }}>{hint}</span>}
      {textarea ? (
        <textarea
          value={value}
          placeholder={placeholder}
          onChange={(e) => onChange(e.target.value)}
          style={{
            ...style,
            width: '100%',
            minHeight: 88,
            background: 'var(--night)',
            color: 'var(--text)',
            border: '1px solid var(--border)',
            borderRadius: 'var(--r-input)',
            padding: '9px 12px',
            fontFamily: 'var(--font-body)',
            fontSize: 13.5,
            resize: 'vertical',
          }}
        />
      ) : (
        <input
          value={value}
          placeholder={placeholder}
          onChange={(e) => onChange(e.target.value)}
          style={style}
        />
      )}
    </label>
  );
}
