// رسوم بسيطة بـ SVG خالص.
//
// لماذا بلا مكتبة رسم؟ نحتاج شكلين اثنين فقط (أعمدة زمنية وشريط
// توزيع)، ومكتبة مثل recharts تضيف ~100KB وتجرّ نظام ألوان وخطوطاً
// خاصة بها نضطر لمصارعتها كي تطابق الهوية. SVG هنا أقصر وأدق.

/** أعمدة زمنية — التوقعات اليومية آخر أسبوعين.
 *
 * البيانات تصل من السيرفر مكتملة بأيام الصفر (generate_series)،
 * فلا نملأ فجوات هنا: عمود مفقود في الرسم يكذب، وعمود بصفر يقول
 * الحقيقة "لم يتوقع أحد ذلك اليوم".
 */
export function BarChart({ data, height = 110 }) {
  if (!data?.length) return <p className="muted">لا بيانات بعد.</p>;

  const max = Math.max(...data.map((d) => d.count), 1);
  const fmt = new Intl.DateTimeFormat('ar', { day: 'numeric', month: 'short' });

  return (
    <div>
      <div
        style={{
          display: 'flex',
          alignItems: 'flex-end',
          gap: 4,
          height,
          direction: 'ltr', // المحور الزمني يمضي من الأقدم لليمين
        }}
      >
        {data.map((d) => {
          const h = Math.max(2, Math.round((d.count / max) * height));
          return (
            <div
              key={d.day}
              title={`${fmt.format(new Date(d.day))} — ${d.count} توقّع`}
              style={{
                flex: 1,
                height: h,
                borderRadius: 4,
                // العمود الفارغ يبقى مرئياً بلون خافت: غيابه التام
                // يجعل اليوم يبدو غير موجود بدل "بلا نشاط".
                background: d.count ? 'var(--correct)' : 'var(--fill)',
                opacity: d.count ? 0.55 + 0.45 * (d.count / max) : 1,
              }}
            />
          );
        })}
      </div>
      <div
        style={{
          display: 'flex',
          justifyContent: 'space-between',
          marginTop: 7,
          fontSize: 11,
          color: 'var(--text-faint)',
        }}
      >
        <span>{fmt.format(new Date(data[0].day))}</span>
        <span>{fmt.format(new Date(data[data.length - 1].day))}</span>
      </div>
    </div>
  );
}

/** شريط توزيع أفقي — كيف تتوزع التوقعات المحتسبة على قيم النقاط. */
export function Distribution({ data, labelOf }) {
  if (!data?.length) return <p className="muted">لا توقعات محتسبة بعد.</p>;

  const total = data.reduce((s, d) => s + d.count, 0) || 1;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 11 }}>
      {data.map((d) => {
        const pct = Math.round((d.count / total) * 100);
        // صفر نقاط ليس إنجازاً — لا يأخذ الذهبي.
        const zero = d.points === 0;
        return (
          <div key={d.points}>
            <div style={{ display: 'flex', fontSize: 12, marginBottom: 4 }}>
              <span style={{ color: zero ? 'var(--text-muted)' : 'var(--crown)', fontWeight: 600 }}>
                {labelOf ? labelOf(d.points) : `${d.points} نقاط`}
              </span>
              <span className="spacer" style={{ flex: 1 }} />
              <span className="muted num">
                {d.count} · {pct}%
              </span>
            </div>
            <div className="meter">
              <span
                style={{
                  width: `${pct}%`,
                  background: zero ? 'var(--fill-strong)' : 'var(--crown)',
                }}
              />
            </div>
          </div>
        );
      })}
    </div>
  );
}
