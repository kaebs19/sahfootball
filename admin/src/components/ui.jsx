// مكونات الواجهة المشتركة.
//
// وُضعت هنا لأنها تتكرر في كل صفحة، ولأن بعضها يجسّد قاعدة من قواعد
// الهوية — فمركزتها تعني أن القاعدة تُطبَّق مرة واحدة بدل أن تُعاد
// كتابتها (وتُخالَف) في كل صفحة.

// الأيقونات في ملف مستقل (icons.jsx) لأن Fast Refresh يتعطل حين
// يصدّر ملفٌ مكوناتٍ وثوابتَ معاً. نستوردها هنا لاستعمالنا الداخلي
// ونعيد تصديرها كي تستورد الصفحات كل شيء من مكان واحد.
import { useEffect, useState } from 'react';
import { API_ORIGIN } from '../api';
import { Icon } from './icons';

export { Icon };

/** صورة المستخدم، أو الحرف الأول من اسمه بديلاً.
 *
 * `avatar_url` يصل نسبياً ("/uploads/x.jpg") لأن السيرفر يخزّنه
 * كذلك كي لا تتعطل الروابط لو تغيّر نطاقه — فنكمله بأصل السيرفر.
 * الحرف الأول أهدأ من أيقونة شخص عامة مكررة في كل صف.
 */
export function Avatar({ url, name, size = 34 }) {
  if (!url) {
    return (
      <div className="avatar" style={{ width: size, height: size, fontSize: size * 0.4 }}>
        {(name || '؟').charAt(0)}
      </div>
    );
  }
  return (
    <img
      src={url.startsWith('http') ? url : `${API_ORIGIN}${url}`}
      alt=""
      style={{
        width: size,
        height: size,
        borderRadius: 999,
        objectFit: 'cover',
        background: 'var(--fill)',
        flex: 'none',
      }}
    />
  );
}

/** علامة "ملك التوقعات": درع بثلاث درجات محفورة يعلو وسطاها تاج.
 *
 * نفس هندسة الـ SVG في ملف الهوية (مربع 512) وهي نفسها المرسومة في
 * تطبيق الجوال. قاعدتان مطبَّقتان هنا:
 *  - الحفر بلون الخلفية التي يجلس عليها الدرع، لا لون ثالث — لذلك
 *    `carve` وسيط إجباري عملياً وليس قيمة مخبأة.
 *  - تحت 64 بكسل تُحذف الدرجات ويبقى الدرع والتاج، لأن الدرجات
 *    تتحول إلى خروق غير مقروءة. الشرط داخل المكوّن فلا يُنسى.
 */
export function BrandMark({ size = 24, color = 'var(--crown)', carve = 'var(--surface)' }) {
  const full = size >= 64;
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" fill="none" aria-hidden="true">
      <path d="M256 40l192 68v168c0 80-88 152-192 192C152 428 64 356 64 276V108z" fill={color} />
      {full && (
        <g fill={carve}>
          <rect x="140" y="300" width="58" height="104" rx="10" />
          <rect x="227" y="250" width="58" height="154" rx="10" />
          <rect x="314" y="284" width="58" height="120" rx="10" />
        </g>
      )}
      <path d="M212 236v-40l22 14 22-24 22 24 22-14v40z" fill={carve} />
    </svg>
  );
}

/** غلاف موحّد لكل أيقونة: نفس السماكة والحواف في كل مكان. */
export function Svg({ path, size = 16 }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.7"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {path}
    </svg>
  );
}

/** ترويسة صفحة: عنوان وشرح، وحيّز حرّ على الجهة الأخرى للأزرار. */
export function PageHead({ title, subtitle, children }) {
  return (
    <div className="page-head">
      <div>
        <h1>{title}</h1>
        {subtitle && <p>{subtitle}</p>}
      </div>
      <div className="spacer" />
      {children}
    </div>
  );
}

/** مربع رقم واحد.
 *
 * `tone` يحمل المعنى لا الزخرفة: crown للنقاط والرتب (القاعدة تحجز
 * الذهبي لها)، alert لرقم يستدعي تدخّل الأدمن، good لحالة سليمة.
 *
 * `meter` هو الكسر المعروض فعلاً (0–1) ولا شيء غيره. لون الشريط
 * يقرره `meterTone` من المستدعي لا من ارتفاع الشريط، لأن معنى
 * "ممتلئ" يختلف بين مقياس ومقياس: حصة API ممتلئة = خطر، وترجمة
 * الفرق ممتلئة = اكتمال. خلط الاثنين كان سيجعل الشريط يكذب في
 * أحدهما حتماً.
 */
export function Stat({ icon, label, value, note, tone, meter, meterTone }) {
  return (
    <div className={`stat${tone ? ` ${tone}` : ''}`}>
      <div className="stat-top">
        {icon && <Svg path={icon} size={14} />}
        <span>{label}</span>
      </div>
      <span className="stat-value">{value}</span>
      {note && <span className="stat-note">{note}</span>}
      {meter !== undefined && (
        <div className={`meter${meterTone ? ` ${meterTone}` : ''}`}>
          <span style={{ width: `${Math.min(100, Math.max(0, Math.round(meter * 100)))}%` }} />
        </div>
      )}
    </div>
  );
}

export function Card({ title, subtitle, royal, children, actions }) {
  return (
    <div className={`card${royal ? ' royal' : ''}`}>
      {(title || actions) && (
        <div className="page-head" style={{ marginBottom: subtitle ? 4 : 14 }}>
          <div>
            {title && <h2>{title}</h2>}
            {subtitle && <p className="muted">{subtitle}</p>}
          </div>
          <div className="spacer" />
          {actions}
        </div>
      )}
      {children}
    </div>
  );
}

/** رسالة نجاح أو خطأ. شكل واحد لكل الصفحات بدل تنويعات. */
export function Notice({ kind = 'info', children }) {
  if (!children) return null;
  return (
    <div className={`notice ${kind}`}>
      <Svg path={kind === 'error' ? Icon.alert : Icon.shield} size={15} />
      <span>{children}</span>
    </div>
  );
}

export function Empty({ message }) {
  return (
    <div className="empty">
      <Svg path={Icon.empty} size={34} />
      <p>{message}</p>
    </div>
  );
}

/** جدول قابل للتمرير أفقياً.
 *
 * الغلاف ضروري لا تجميلي: الجداول هنا تحمل 7 أعمدة، وبدون تمرير
 * خاص بها ستمدّد الصفحة كلها وتكسر الشريط الجانبي على الشاشات
 * الضيقة.
 */
export function Table({ head, children, empty, colSpan }) {
  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>
            {head.map((h, i) => (
              <th key={i}>{h}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {children}
          {empty && (
            <tr>
              <td colSpan={colSpan ?? head.length}>
                <p className="muted" style={{ padding: '18px 0', textAlign: 'center' }}>
                  {empty}
                </p>
              </td>
            </tr>
          )}
        </tbody>
      </table>
    </div>
  );
}

/** زر يطلب تأكيداً على خطوتين.
 *
 * بديل window.confirm: النافذة المنبثقة تقطع السياق، وشكلها من
 * المتصفح لا من الهوية، وبعض البيئات المدمجة لا تعرضها أصلاً.
 * الضغطة الأولى تحوّل الزر إلى "متأكد؟" لخمس ثوانٍ ثم يعود وحده —
 * فالتراجع هو التصرف الافتراضي عند الانشغال عنه.
 */
export function ConfirmButton({ label, confirmLabel = 'متأكد؟', onConfirm, busy, className = 'ghost' }) {
  const [armed, setArmed] = useState(false);

  useEffect(() => {
    if (!armed) return;
    const t = setTimeout(() => setArmed(false), 5000);
    return () => clearTimeout(t);
  }, [armed]);

  return (
    <button
      type="button"
      className={`small ${armed ? 'danger' : className}`}
      disabled={busy}
      onClick={() => {
        if (!armed) return setArmed(true);
        setArmed(false);
        onConfirm();
      }}
    >
      {busy ? '…' : armed ? confirmLabel : label}
    </button>
  );
}
