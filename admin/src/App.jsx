// لوحة تحكم ملك التوقعات.
//
// البنية: App يحرس الدخول، وبعده Shell ثابت (شريط جانبي) و Routes
// تبدّل الصفحة. كل صفحة ملف مستقل في pages/ — إضافة صفحة = ملف
// جديد وسطر في NAV وسطر في Routes.
//
// لماذا شريط جانبي بدل تبويبات علوية؟ الأقسام صارت تسعة، والتبويبات
// الأفقية تتكسّر أو تنكمش مع كل قسم جديد. الشريط الجانبي يستوعب
// النمو ويسمح بتجميع الأقسام تحت عناوين.
import { useEffect, useState } from 'react';
import { BrowserRouter, Routes, Route, NavLink, Navigate } from 'react-router-dom';
import { api, store } from './api';
import { BrandMark, Icon, Svg } from './components/ui';
import Dashboard from './pages/Dashboard';
import Leagues from './pages/Leagues';
import Fixtures from './pages/Fixtures';
import Standings from './pages/Standings';
import Teams from './pages/Teams';
import Users from './pages/Users';
import UserDetail from './pages/UserDetail';
import Groups from './pages/Groups';
import Leaderboard from './pages/Leaderboard';
import Scoring from './pages/Scoring';
import Profile from './pages/Profile';
import './theme.css';

// مجموعة الأقسام: المحتوى (ما يراه المستخدم) ثم الناس ثم الإعدادات.
const NAV = [
  {
    section: 'عام',
    items: [{ to: '/', label: 'الرئيسية', icon: Icon.home, end: true }],
  },
  {
    section: 'المحتوى',
    items: [
      { to: '/leagues', label: 'الدوريات', icon: Icon.league },
      { to: '/fixtures', label: 'المباريات', icon: Icon.ball },
      { to: '/standings', label: 'الترتيب', icon: Icon.table },
      { to: '/teams', label: 'الفرق', icon: Icon.shield },
    ],
  },
  {
    section: 'الناس',
    items: [
      { to: '/users', label: 'المستخدمون', icon: Icon.users },
      { to: '/groups', label: 'المجموعات', icon: Icon.group },
      { to: '/leaderboard', label: 'العرش', icon: Icon.trophy },
    ],
  },
  {
    section: 'الإعدادات',
    items: [
      { to: '/scoring', label: 'نظام النقاط', icon: Icon.scoring },
      { to: '/profile', label: 'حسابي', icon: Icon.shield },
    ],
  },
];

export default function App() {
  const [loggedIn, setLoggedIn] = useState(Boolean(store.access));

  if (!loggedIn) return <Login onSuccess={() => setLoggedIn(true)} />;

  return (
    <BrowserRouter>
      <Shell onLogout={() => { store.clear(); setLoggedIn(false); }} />
    </BrowserRouter>
  );
}

function Shell({ onLogout }) {
  // عدّاد التوقعات المعلّقة يعيش في الهيكل لا في صفحة الرئيسية:
  // إنه تنبيه يجب أن يراه الأدمن وهو في أي صفحة، لا حين يزور
  // الرئيسية فقط.
  const [pending, setPending] = useState(0);
  const [me, setMe] = useState(null);

  useEffect(() => {
    api.get('/auth/me').then(({ data }) => setMe(data.user)).catch(() => {});
    const load = () =>
      api.get('/admin/stats')
        .then(({ data }) => setPending(data.pending_settlement ?? 0))
        .catch(() => {});
    load();
    const t = setInterval(load, 60000);
    return () => clearInterval(t);
  }, []);

  return (
    <div className="shell">
      <aside className="sidebar">
        <div className="brand">
          <BrandMark size={30} carve="var(--surface)" />
          <div>
            <div className="brand-name">ملك التوقعات</div>
            <div className="brand-sub">لوحة التحكم</div>
          </div>
        </div>

        <nav className="nav">
          {NAV.map((group) => (
            <div key={group.section}>
              <div className="nav-section">{group.section}</div>
              {group.items.map((item) => (
                <NavLink key={item.to} to={item.to} end={item.end}>
                  <Svg path={item.icon} />
                  <span>{item.label}</span>
                  {item.to === '/scoring' && pending > 0 && (
                    <span className="nav-badge" title="توقعات تنتظر الاحتساب">
                      {pending}
                    </span>
                  )}
                </NavLink>
              ))}
            </div>
          ))}
        </nav>

        <div className="sidebar-foot">
          <div className="avatar">{(me?.display_name || me?.email || '؟').charAt(0)}</div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 12.5, fontWeight: 600 }}>
              {me?.display_name || 'أدمن'}
            </div>
            <div className="ltr" style={{ fontSize: 10.5, overflow: 'hidden', textOverflow: 'ellipsis' }}>
              {me?.email}
            </div>
          </div>
          <button className="ghost small" title="خروج" onClick={onLogout}>
            <Svg path={Icon.logout} size={14} />
          </button>
        </div>
      </aside>

      <main className="content">
        <Routes>
          <Route path="/" element={<Dashboard />} />
          <Route path="/leagues" element={<Leagues />} />
          <Route path="/fixtures" element={<Fixtures />} />
          <Route path="/standings" element={<Standings />} />
          <Route path="/teams" element={<Teams />} />
          <Route path="/users" element={<Users />} />
          <Route path="/users/:id" element={<UserDetail />} />
          <Route path="/groups" element={<Groups />} />
          <Route path="/leaderboard" element={<Leaderboard />} />
          <Route path="/scoring" element={<Scoring />} />
          <Route path="/profile" element={<Profile />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </main>
    </div>
  );
}

function Login({ onSuccess }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  async function submit(e) {
    e.preventDefault();
    setBusy(true);
    setError('');
    try {
      const { data } = await api.post('/auth/login', { email, password });
      store.save(data);
      // نتأكد أنه أدمن قبل إدخاله — مستخدم عادي سيجد كل شيء 403،
      // وأن يُمنع عند الباب أوضح من أن يدخل لواجهة كل شيء فيها معطّل.
      try {
        await api.get('/admin/settings/scoring');
      } catch (err) {
        store.clear();
        throw new Error(
          err.response?.status === 403 ? 'هذا الحساب ليس أدمن' : 'تعذر الاتصال بالسيرفر'
        );
      }
      onSuccess();
    } catch (err) {
      setError(err.response?.data?.error || err.message || 'فشل تسجيل الدخول');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="login-wrap">
      <div className="card login">
        {/* 64 هو أصغر حجم تبقى معه درجات الدرع مقروءة — قاعدة الهوية */}
        <BrandMark size={64} carve="var(--surface)" />
        <h1>ملك التوقعات</h1>
        <p className="muted">لوحة التحكم</p>
        <form onSubmit={submit}>
          <label>
            البريد الإلكتروني
            <input
              type="email"
              dir="ltr"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
            />
          </label>
          <label>
            كلمة المرور
            <input
              type="password"
              dir="ltr"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
            />
          </label>
          {error && <p className="error">{error}</p>}
          <button disabled={busy}>{busy ? '…' : 'دخول'}</button>
        </form>
      </div>
    </div>
  );
}
