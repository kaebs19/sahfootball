# نشر ملك التوقعات

دليل عملي لرفع النسخة على سيرفر. الافتراض أنك على VPS بنظام Linux
ولديك نطاق يشير إليه.

---

## قبل أن تبدأ — ثلاثة أمور تحجب الإطلاق

راجعها الآن لا بعد النشر.

**١. اشتراك مزوّد البيانات.** الخطة المجانية تخدم مواسم 2022–2024
فقط، والموسم المخزَّن منتهٍ بالكامل — أي أن تبويب "المباريات
القادمة" سيكون فارغاً دائماً ولن يستطيع أحد التوقع. وحتى بحصة
الطلبات وحدها: يوم مباريات عادي يستهلك ~87 طلباً وأكثف يوم ~122،
والحد المجاني 100/يوم. خطة Pro (7,500/يوم) تكفي بأريحية.

**٢. مزوّد بريد.** `MAIL_DRIVER=console` يطبع رمز استعادة كلمة
المرور في اللوق ولا يرسله. من ينسى كلمته يفقد حسابه نهائياً.

**٣. مراجعة قانونية.** نصوص الخصوصية والشروط مسوّدة كتبها مطوّر لا
محامٍ. مراجعة App Store تفتح رابط سياسة الخصوصية وتتحقق أنه يعمل.

---

## الطريق الأسرع: Docker

```bash
git clone https://github.com/kaebs19/sahfootball.git
cd sahfootball
cp server/.env.example .env
```

عدّل `.env` واضبط على الأقل:

```bash
POSTGRES_PASSWORD=<كلمة قوية>
JWT_SECRET=<openssl rand -hex 32>
FOOTBALL_API_KEY=<مفتاحك>
```

ثم:

```bash
docker compose up -d --build
docker compose logs -f app
```

الهجرات تعمل تلقائياً عند الإقلاع. التطبيق يستمع على
`127.0.0.1:3000` فقط — البروكسي أدناه هو ما يواجه الإنترنت.

### أول أدمن

```bash
docker compose exec app node scripts/makeAdmin.js you@example.com
```

الحساب يجب أن يكون مسجّلاً أولاً من الموقع أو التطبيق.

---

## بدون Docker

يتطلب Node 20+، PostgreSQL 14+، Redis 6+.

```bash
cd admin && npm ci && npm run build && cd ..
cd server && npm ci --omit=dev
cp .env.example .env      # املأه
npm run migrate
npm start
```

لتشغيله كخدمة دائمة، `/etc/systemd/system/malik.service`:

```ini
[Unit]
Description=Malik Al-Tawaquat
After=network.target postgresql.service redis.service

[Service]
Type=simple
User=malik
WorkingDirectory=/srv/malik/server
EnvironmentFile=/srv/malik/server/.env
ExecStart=/usr/bin/node src/app.js
Restart=always
RestartSec=5

# systemd يرسل SIGTERM ثم ينتظر؛ التطبيق يطفئ نفسه بلطف خلال 10 ثوانٍ.
KillSignal=SIGTERM
TimeoutStopSec=20

# تقييد الصلاحيات: ثغرة في التطبيق تبقى محصورة.
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/malik

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now malik
sudo journalctl -u malik -f
```

---

## البروكسي و TLS

التطبيق **لا يتولى TLS**. ضع nginx أو Caddy أمامه.

Caddy (يدير الشهادة تلقائياً) — `/etc/caddy/Caddyfile`:

```
malikaltawaquat.com {
    reverse_proxy 127.0.0.1:3000
}
```

nginx:

```nginx
server {
    server_name malikaltawaquat.com;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        # بدون هذه الترويسة يرى التطبيق كل الزوار بعنوان واحد،
        # فيقفل حدّ سبام نموذج التواصل الباب على الجميع.
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # صور المستخدمين قد تصل 2MB.
    client_max_body_size 4M;
}
```

ثم شهادة عبر `certbot --nginx`.

**مهم:** اضبط `TRUST_PROXY=1` في `.env` بعد وضع البروكسي، وإلا
انهار حدّ السبام. ولا تضبطه بدون بروكسي — عندها يستطيع أي زائر
انتحال عنوانه.

---

## ماذا يعمل بعد النشر

| المسار | المحتوى |
|---|---|
| `/` | الموقع العام |
| `/privacy` `/terms` `/about` `/contact` | الصفحات القانونية والتعريفية |
| `/admin` | لوحة التحكم |
| `/api/*` | الـ API الذي يستهلكه التطبيق |
| `/health` | فحص الصحة وحصة API |

---

## التحقق بعد النشر

```bash
curl -s https://<نطاقك>/health
curl -s -o /dev/null -w '%{http_code}\n' https://<نطاقك>/privacy   # 200
curl -s -o /dev/null -w '%{http_code}\n' https://<نطاقك>/admin/    # 200
```

ثم من المتصفح: افتح `/admin`، سجّل الدخول، واضبط من **إعدادات
الموقع** البريد وحسابات التواصل وروابط المتاجر. راجع نصوص
**محتوى الصفحات** قبل أن تعطي الرابط لـ App Store.

وأخيراً حدّث عنوان الـ API في تطبيق الجوال:

```bash
flutter build ipa --dart-define=API_URL=https://<نطاقك>
```

---

## أشياء ستلدغك لو نسيتها

**نسخة واحدة فقط تزامن.** لو شغّلت أكثر من نسخة للتوسّع، اترك
`ENABLE_SCHEDULER=true` في واحدة و`false` في البقية — وإلا تضاعف
استهلاك حصة المزوّد بعدد النسخ.

**الصور تحتاج قرصاً دائماً.** `UPLOADS_DIR` يجب أن يشير خارج مجلد
المشروع. على قرص مؤقت تختفي صور المستخدمين مع كل نشر بينما تبقى
مساراتها في القاعدة.

**النسخ الاحتياطي.** القاعدة تحمل الحسابات والتوقعات والنقاط، ولا
شيء منها قابل لإعادة البناء:

```bash
docker compose exec db pg_dump -U malik sahfootball | gzip > backup-$(date +%F).sql.gz
```

**تدوير الأسرار.** لو تسرّب `JWT_SECRET` يوماً، تغييره يُخرج كل
المستخدمين — وهذا هو السلوك المطلوب.
