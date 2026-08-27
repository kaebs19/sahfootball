// تحرير صفحات الموقع العام.
//
// المحرر Markdown لا HTML، وهذا قرار أمني لا تفضيل شكلي: المحتوى
// المكتوب هنا يُعرض لكل زائر، ولو سمحنا بـ HTML خام لصار أي حساب
// أدمن مخترق قادراً على حقن سكربت في الموقع كله. السيرفر يهرب من
// HTML أولاً ثم يطبّق مجموعة Markdown صغيرة، فلا يمر وسم أبداً.
//
// المعاينة هنا تقريبية عمداً: تريك البنية (عناوين، قوائم، عريض)
// كي لا تحرّر أعمى، لكن الحقيقة النهائية ما يصيّره السيرفر — وزر
// "افتح الصفحة" يفتحها كما يراها الزائر فعلاً.
import { useEffect, useState } from 'react';
import { api, API_ORIGIN } from '../api';
import { Card, Icon, Notice, PageHead, Svg } from '../components/ui';

const SLUG_LABEL = {
  privacy: 'سياسة الخصوصية',
  terms: 'شروط الاستخدام',
  about: 'حول الموقع',
  contact: 'اتصل بنا',
};

const HELP = [
  ['## عنوان', 'عنوان قسم'],
  ['### عنوان فرعي', 'عنوان أصغر'],
  ['**عريض**', 'تشديد'],
  ['- بند', 'قائمة'],
  ['[نص](https://…)', 'رابط'],
];

export default function SiteContent() {
  const [pages, setPages] = useState(null);
  const [slug, setSlug] = useState('privacy');
  const [page, setPage] = useState(null); // الصفحة المفتوحة بنصها
  const [draft, setDraft] = useState(null);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState(null);

  // قائمة الصفحات لا تحمل النصوص عمداً (السيرفر يرسل slug والعنوان
  // والتاريخ فقط) — أربعة نصوص قانونية كاملة في رد واحد هدر لا
  // يُقرأ منه إلا واحد. فنجلب نص الصفحة عند فتحها.
  async function loadList() {
    const { data } = await api.get('/admin/site/pages');
    setPages(data.pages);
  }

  async function loadPage(s) {
    const { data } = await api.get(`/admin/site/pages/${s}`);
    setPage(data.page);
  }

  useEffect(() => {
    loadList().catch(() => setMsg({ type: 'error', text: 'تعذّر تحميل صفحات الموقع' }));
  }, []);

  useEffect(() => {
    setPage(null);
    loadPage(slug).catch(() => setMsg({ type: 'error', text: 'تعذّر تحميل نص الصفحة' }));
  }, [slug]);

  const current = draft ?? (page ? { title: page.title, body: page.body } : null);
  const dirty =
    Boolean(draft) && page && (draft.title !== page.title || draft.body !== page.body);

  function edit(patch) {
    setDraft({ ...(current || { title: '', body: '' }), ...patch });
    setMsg(null);
  }

  async function save() {
    setBusy(true);
    setMsg(null);
    try {
      await api.put(`/admin/site/pages/${slug}`, {
        title: current.title,
        body: current.body,
      });
      await Promise.all([loadList(), loadPage(slug)]);
      setDraft(null);
      setMsg({ type: 'ok', text: 'حُفظت الصفحة — ظاهرة على الموقع الآن' });
    } catch (err) {
      setMsg({ type: 'error', text: err.response?.data?.error || 'فشل الحفظ' });
    } finally {
      setBusy(false);
    }
  }

  if (!pages) {
    return (
      <>
        <PageHead title="محتوى الموقع" />
        <Card><p className="muted">{msg?.text || 'جارِ التحميل…'}</p></Card>
      </>
    );
  }

  return (
    <>
      <PageHead
        title="محتوى الموقع"
        subtitle="نصوص الصفحات العامة. التعديل يظهر للزوار فوراً بلا إعادة نشر."
      >
        <a
          className="btn ghost"
          href={`${API_ORIGIN}/${slug}`}
          target="_blank"
          rel="noopener noreferrer"
        >
          افتح الصفحة
        </a>
        <button disabled={busy || !dirty} onClick={save}>
          {busy ? '…' : 'حفظ'}
        </button>
      </PageHead>

      <div className="chips" style={{ marginBottom: 14 }}>
        {pages.map((p) => (
          <button
            key={p.slug}
            type="button"
            className={`chip${slug === p.slug ? ' active' : ''}`}
            onClick={() => {
              if (dirty && !window.confirm('لديك تعديل غير محفوظ. تتركه؟')) return;
              setSlug(p.slug);
              setDraft(null);
              setMsg(null);
            }}
          >
            {SLUG_LABEL[p.slug] || p.slug}
          </button>
        ))}
      </div>

      {msg && <Notice kind={msg.type}>{msg.text}</Notice>}

      {current && (
        <div className="grid cols-2">
          <Card
            title="النص"
            subtitle={
              page?.updated_at
                ? `آخر تحديث ${new Date(page.updated_at).toLocaleString('ar-SA', {
                    dateStyle: 'medium',
                    timeStyle: 'short',
                  })}`
                : undefined
            }
          >
            <label className="muted" style={{ fontSize: 12.5 }}>
              عنوان الصفحة
              <input
                value={current.title}
                onChange={(e) => edit({ title: e.target.value })}
                style={{ marginTop: 5, marginBottom: 12 }}
              />
            </label>

            <textarea
              value={current.body}
              onChange={(e) => edit({ body: e.target.value })}
              spellCheck="false"
              style={{
                width: '100%',
                minHeight: 460,
                background: 'var(--night)',
                color: 'var(--text)',
                border: '1px solid var(--border)',
                borderRadius: 'var(--r-input)',
                padding: 13,
                fontFamily: 'var(--font-body)',
                fontSize: 14,
                lineHeight: 1.9,
                resize: 'vertical',
              }}
            />

            <div className="chips" style={{ marginTop: 10 }}>
              {HELP.map(([syntax, what]) => (
                <span key={syntax} className="badge" title={what}>
                  <code className="ltr" style={{ fontSize: 11 }}>{syntax}</code>
                </span>
              ))}
            </div>
          </Card>

          <Card title="معاينة" subtitle="تقريبية — الشكل النهائي على الموقع نفسه">
            <div
              style={{
                background: 'var(--night)',
                border: '1px solid var(--border)',
                borderRadius: 14,
                padding: '18px 20px',
                minHeight: 460,
                maxHeight: 560,
                overflowY: 'auto',
                lineHeight: 1.9,
              }}
            >
              <h2 style={{ fontSize: 19, marginBottom: 14 }}>{current.title}</h2>
              <Preview markdown={current.body} />
            </div>
          </Card>
        </div>
      )}

      <Card title="تذكير" royal>
        <div style={{ display: 'flex', gap: 10, alignItems: 'flex-start' }}>
          <Svg path={Icon.alert} size={16} />
          <p className="muted" style={{ margin: 0 }}>
            نصوص الخصوصية والشروط المكتوبة هنا مسوّدة كتبها مطوّر لا محامٍ.
            راجعها قانونياً قبل نشر التطبيق — ومراجعة App Store تطلب رابط
            سياسة خصوصية يعمل فعلاً.
          </p>
        </div>
      </Card>
    </>
  );
}

/** معاينة Markdown مبسّطة.
 *
 * تبني عناصر React لا نصاً، فلا تمر عبر dangerouslySetInnerHTML —
 * ما يعني أن محاولة كتابة وسم HTML في المحرر تظهر هنا كنص عادي،
 * تماماً كما ستظهر على الموقع. المعاينة تصدق في هذا تحديداً.
 */
function Preview({ markdown }) {
  const lines = String(markdown || '').split('\n');
  const out = [];
  let list = null;

  const flush = () => {
    if (list) {
      out.push(
        <ul key={`l${out.length}`} style={{ paddingInlineStart: 20, marginBottom: 12 }}>
          {list.map((t, i) => (
            <li key={i} style={{ color: 'var(--text-muted)', marginBottom: 5 }}>
              <Inline text={t} />
            </li>
          ))}
        </ul>
      );
      list = null;
    }
  };

  lines.forEach((raw, i) => {
    const line = raw.trimEnd();
    if (/^\s*[-*]\s+/.test(line)) {
      (list ||= []).push(line.replace(/^\s*[-*]\s+/, ''));
      return;
    }
    flush();
    if (!line.trim()) return;
    if (/^###\s+/.test(line)) {
      out.push(<h3 key={i} style={{ fontSize: 15, color: 'var(--crown)', margin: '18px 0 6px' }}>
        {line.replace(/^###\s+/, '')}</h3>);
    } else if (/^##\s+/.test(line)) {
      out.push(<h2 key={i} style={{ fontSize: 17, margin: '22px 0 8px' }}>
        {line.replace(/^##\s+/, '')}</h2>);
    } else if (/^#\s+/.test(line)) {
      out.push(<h2 key={i} style={{ fontSize: 19, margin: '22px 0 8px' }}>
        {line.replace(/^#\s+/, '')}</h2>);
    } else if (/^---+$/.test(line.trim())) {
      out.push(<hr key={i} style={{ border: 'none', borderTop: '1px solid var(--border)', margin: '20px 0' }} />);
    } else {
      out.push(<p key={i} style={{ color: 'var(--text-muted)', marginBottom: 11 }}>
        <Inline text={line} /></p>);
    }
  });
  flush();

  return out.length ? out : <p className="faint">لا محتوى بعد.</p>;
}

/** العريض والروابط داخل السطر. */
function Inline({ text }) {
  const parts = String(text).split(/(\*\*[^*]+\*\*|\[[^\]]+\]\([^)]+\))/g);
  return parts.map((part, i) => {
    const bold = /^\*\*([^*]+)\*\*$/.exec(part);
    if (bold) return <strong key={i} style={{ color: 'var(--text)' }}>{bold[1]}</strong>;
    const link = /^\[([^\]]+)\]\(([^)]+)\)$/.exec(part);
    if (link) return <span key={i} style={{ color: 'var(--correct)' }}>{link[1]}</span>;
    return part;
  });
}
