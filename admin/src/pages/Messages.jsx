// صندوق رسائل "اتصل بنا".
//
// الرسائل تُخزَّن في القاعدة ولا تُرسل بالبريد، لأن مزوّد البريد
// لم يُضبط بعد (MAIL_DRIVER=console) — ونموذج تواصل يرسل إلى
// اللاشيء أسوأ من عدم وجوده: الزائر يظن أن رسالته وصلت.
//
// لذلك هذه الشاشة ليست ترفاً بل القناة الوحيدة لقراءة ما يصل.
// وزر "رد بالبريد" يفتح برنامج البريد عندك بالعنوان والموضوع
// جاهزين — الرد يخرج من بريدك أنت لا من السيرفر.
import { useEffect, useState } from 'react';
import { api } from '../api';
import { Card, ConfirmButton, Icon, Notice, PageHead, Stat, Table } from '../components/ui';

export default function Messages() {
  const [messages, setMessages] = useState(null);
  const [unreadOnly, setUnreadOnly] = useState(false);
  const [open, setOpen] = useState(null);
  const [busyId, setBusyId] = useState(null);
  const [error, setError] = useState('');

  async function load(unread = unreadOnly) {
    const { data } = await api.get('/admin/site/messages', {
      params: unread ? { unread: 1 } : {},
    });
    setMessages(data.messages);
  }

  useEffect(() => {
    load(unreadOnly).catch(() => setError('تعذّر تحميل الرسائل'));
  }, [unreadOnly]);

  async function markRead(m) {
    if (m.read_at) return;
    try {
      await api.put(`/admin/site/messages/${m.id}/read`);
      setMessages((list) =>
        list.map((x) => (x.id === m.id ? { ...x, read_at: new Date().toISOString() } : x))
      );
    } catch {
      /* التعليم كمقروء تفصيل ثانوي — فشله لا يستحق إزعاج الأدمن */
    }
  }

  async function remove(m) {
    setBusyId(m.id);
    setError('');
    try {
      await api.delete(`/admin/site/messages/${m.id}`);
      setMessages((list) => list.filter((x) => x.id !== m.id));
      if (open?.id === m.id) setOpen(null);
    } catch (err) {
      setError(err.response?.data?.error || 'فشل الحذف');
    } finally {
      setBusyId(null);
    }
  }

  const unread = messages?.filter((m) => !m.read_at).length ?? 0;

  return (
    <>
      <PageHead
        title="الرسائل"
        subtitle="ما يصل من نموذج «اتصل بنا» في الموقع العام"
      >
        <button
          className={unreadOnly ? '' : 'ghost'}
          onClick={() => setUnreadOnly((v) => !v)}
        >
          {unreadOnly ? 'عرض الكل' : 'غير المقروءة فقط'}
        </button>
      </PageHead>

      <div className="grid cols-4" style={{ marginBottom: 14 }}>
        <Stat icon={Icon.users} label="الرسائل" value={messages?.length ?? '…'} />
        <Stat
          icon={Icon.alert}
          label="غير مقروءة"
          value={unread}
          tone={unread > 0 ? 'alert' : 'good'}
          note={unread ? 'تنتظر ردك' : 'لا شيء معلّق'}
        />
      </div>

      <Notice kind="error">{error}</Notice>

      {!messages ? (
        <Card><p className="muted">جارِ التحميل…</p></Card>
      ) : (
        <div className="grid cols-2">
          <Card>
            <Table
              head={['من', 'الموضوع', 'وصلت', '']}
              empty={messages.length === 0
                ? (unreadOnly ? 'لا رسائل غير مقروءة' : 'لا رسائل بعد')
                : null}
            >
              {messages.map((m) => (
                <tr
                  key={m.id}
                  style={{
                    cursor: 'pointer',
                    background: open?.id === m.id ? 'var(--fill)' : undefined,
                  }}
                  onClick={() => { setOpen(m); markRead(m); }}
                >
                  <td>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
                      {/* نقطة غير المقروء: أسرع مسحاً بالعين من شارة نصية */}
                      <span
                        style={{
                          width: 7, height: 7, borderRadius: 999, flex: 'none',
                          background: m.read_at ? 'transparent' : 'var(--correct)',
                        }}
                      />
                      <span>
                        <div style={{ fontWeight: m.read_at ? 400 : 600 }}>
                          {m.name || 'بلا اسم'}
                        </div>
                        <div className="ltr" style={{ fontSize: 11 }}>{m.email}</div>
                      </span>
                    </div>
                  </td>
                  <td className="muted">{m.subject || '—'}</td>
                  <td className="muted" style={{ whiteSpace: 'nowrap' }}>
                    {new Date(m.created_at).toLocaleDateString('ar-SA')}
                  </td>
                  <td onClick={(e) => e.stopPropagation()}>
                    <ConfirmButton
                      label="حذف"
                      busy={busyId === m.id}
                      onConfirm={() => remove(m)}
                    />
                  </td>
                </tr>
              ))}
            </Table>
          </Card>

          <Card title={open ? (open.subject || 'بلا موضوع') : 'الرسالة'}>
            {!open ? (
              <p className="muted">اختر رسالة من القائمة لقراءتها.</p>
            ) : (
              <>
                <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginBottom: 14 }}>
                  <span className="badge">{open.name || 'بلا اسم'}</span>
                  <span className="badge ltr">{open.email}</span>
                  <span className="badge">
                    {new Date(open.created_at).toLocaleString('ar-SA', {
                      dateStyle: 'medium', timeStyle: 'short',
                    })}
                  </span>
                </div>

                {/* نص خام لا Markdown: هذا كلام زائر مجهول، ولا سبب
                    يجعلنا نمنحه أي قدرة على التنسيق. */}
                <div
                  style={{
                    background: 'var(--night)',
                    border: '1px solid var(--border)',
                    borderRadius: 14,
                    padding: '15px 17px',
                    whiteSpace: 'pre-wrap',
                    lineHeight: 1.9,
                    color: 'var(--text)',
                    minHeight: 180,
                  }}
                >
                  {open.message}
                </div>

                <div className="actions">
                  <a
                    className="btn"
                    href={`mailto:${encodeURIComponent(open.email)}?subject=${encodeURIComponent(
                      'رد: ' + (open.subject || 'رسالتك')
                    )}`}
                  >
                    رد بالبريد
                  </a>
                </div>
              </>
            )}
          </Card>
        </div>
      )}
    </>
  );
}
