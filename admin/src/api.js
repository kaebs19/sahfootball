// عميل HTTP موحد للوحة التحكم.
//
// المسؤوليات الثلاث:
// 1. عنوان السيرفر من VITE_API_URL (ملف .env.local).
// 2. إرفاق الـ access token تلقائياً بكل طلب.
// 3. عند انتهاء صلاحيته (401) يجرب التجديد بالـ refresh token مرة
//    واحدة ويعيد الطلب — الأدمن لا يلاحظ شيئاً. لو فشل التجديد
//    نفسه، الجلسة انتهت فعلاً → خروج.
import axios from 'axios';

const api = axios.create({ baseURL: import.meta.env.VITE_API_URL });

// أصل السيرفر بلا لاحقة /api.
//
// نحتاجه للصور المرفوعة: السيرفر يخزّن avatar_url نسبياً
// ("/uploads/x.jpg") كي لا تتعطل الروابط لو تغيّر نطاقه، لكنه
// يقدّمها من الجذر لا من تحت /api — فلا يصلح baseURL لإكمالها.
const API_ORIGIN = String(import.meta.env.VITE_API_URL || '').replace(/\/api\/?$/, '');

const store = {
  get access() { return localStorage.getItem('accessToken'); },
  get refresh() { return localStorage.getItem('refreshToken'); },
  save(tokens) {
    localStorage.setItem('accessToken', tokens.accessToken);
    localStorage.setItem('refreshToken', tokens.refreshToken);
  },
  clear() {
    localStorage.removeItem('accessToken');
    localStorage.removeItem('refreshToken');
  },
};

api.interceptors.request.use((config) => {
  if (store.access) config.headers.Authorization = `Bearer ${store.access}`;
  return config;
});

api.interceptors.response.use(
  (res) => res,
  async (error) => {
    const original = error.config;
    // _retried: علامة نضعها بأنفسنا على الطلب حتى لا ندخل حلقة
    // تجديد لا نهائية لو رجع 401 حتى بعد التجديد.
    if (error.response?.status === 401 && !original._retried && store.refresh) {
      original._retried = true;
      try {
        // axios مباشرة وليس api: طلب التجديد يجب ألا يمر عبر
        // interceptor الذي قد يحاول تجديد التجديد.
        const { data } = await axios.post(
          `${import.meta.env.VITE_API_URL}/auth/refresh`,
          { refreshToken: store.refresh }
        );
        store.save(data);
        original.headers.Authorization = `Bearer ${data.accessToken}`;
        return api(original);
      } catch {
        store.clear();
        window.location.reload();
      }
    }
    return Promise.reject(error);
  }
);

export { api, store, API_ORIGIN };
