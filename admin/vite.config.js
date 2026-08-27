import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// base: '/admin/' — اللوحة تُخدم من نفس سيرفر الـ API تحت هذا
// المسار لا على نطاق مستقل، فيجب أن تولّد روابط أصولها (JS و CSS)
// مسبوقة به. بدونه يطلب المتصفح /assets/index.js فيصطدم بمجلد
// أصول الموقع العام ويحصل على CSS بدل JavaScript.
export default defineConfig({
  base: '/admin/',
  plugins: [react()],
})
