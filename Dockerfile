# ملك التوقعات — صورة واحدة تحمل السيرفر ولوحة التحكم المبنية.
#
# لماذا صورة واحدة لا اثنتان؟ اللوحة ملفات ثابتة يخدمها نفس السيرفر
# تحت /admin، فالفصل كان سيعطينا حاويتين ونطاقين وإعداد CORS بلا
# مقابل. وحدة نشر واحدة تعني أيضاً أن اللوحة والـ API لا يفترقان
# في الإصدار أبداً.

# ─── المرحلة ١: بناء اللوحة ───────────────────────────────────
# مرحلة منفصلة كي لا تدخل تبعيات البناء (Vite وREact وأدواتها،
# مئات الميجابايت) في الصورة النهائية — نأخذ ناتج البناء فقط.
FROM node:22-alpine AS admin-build
WORKDIR /build

# نسخ ملفات الاعتماد وحدها أولاً: طبقة npm ci تبقى في الكاش ما لم
# تتغير التبعيات، فتعديل ملف واجهة لا يعيد تنزيل كل شيء.
COPY admin/package*.json ./
RUN npm ci

COPY admin/ ./
RUN npm run build

# ─── المرحلة ٢: التشغيل ───────────────────────────────────────
FROM node:22-alpine
WORKDIR /app

# tini كعملية أولى: بدونها يعمل node بمعرّف العملية 1، ولا يتلقى
# إشارات SIGTERM بالسلوك المتوقع — فينهار الإطفاء اللطيف الذي
# بنيناه وتُقطع الطلبات الجارية عند كل نشر.
RUN apk add --no-cache tini

ENV NODE_ENV=production

COPY server/package*.json ./
# omit=dev: nodemon وأدوات التطوير لا مكان لها في الإنتاج.
RUN npm ci --omit=dev && npm cache clean --force

COPY server/ ./
# أصول الموقع العام على /web لا داخل /app: الكود يبني مسارها من
# __dirname بصعود مجلدين (/app/src/../../web)، وهو ما يعطي /web هنا.
COPY web/ /web/
COPY --from=admin-build /build/dist ./admin-dist

ENV ADMIN_DIST=/app/admin-dist
ENV UPLOADS_DIR=/data/uploads

# مجلد الصور خارج شجرة المشروع كي يصلح نقطةَ ربط لقرص دائم.
RUN mkdir -p /data/uploads && chown -R node:node /data

# مستخدم غير جذري: ثغرة في التطبيق تصبح أقل خطراً حين لا يملك
# صلاحية الجذر داخل الحاوية.
USER node

EXPOSE 3000

# فحص الصحة يخبر منسّق الحاويات بالفرق بين "العملية تعمل" و"التطبيق
# يستجيب فعلاً" — سيرفر عالق على قاعدة بيانات ميتة يبدو حياً بدونه.
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD node -e "fetch('http://localhost:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "src/app.js"]
