// cacheLogos — ينزّل شعارات الفرق والدوريات مرة، ويخدمها من عندنا.
//
// كانت الصفحة تطلب كل شعار من media.api-sports.io مباشرة. يعمل،
// لكنه يربط سرعة موقعنا بخادم طرف ثالث لا نتحكم به: بطؤه بطؤنا،
// وانقطاعه صفحة بلا شعارات، وسياسة CSP عندنا اضطرت لفتح مضيف
// خارجي لأجله.
//
// خمسون شعاراً في صفحة واحدة تعني خمسين طلباً لخادم غيرنا عند كل
// زيارة. من عندنا تصير خمسين طلباً لنفس الاتصال المفتوح أصلاً،
// وبكاش متصفح طويل.
//
// يُشغَّل يدوياً أو بعد إضافة دوري: npm run cache-logos
require('dotenv').config({ quiet: true });
const fs = require('node:fs/promises');
const path = require('node:path');
const db = require('../src/config/db');
const logger = require('../src/utils/logger');

// داخل المستودع: أصول ثابتة كـ site.css، مصغّرة مسبقاً ومرفوعة مع
// الكود. البديل (تنزيلها على كل خادم) يعني أن كل نشر جديد يبدأ
// بمئتي طلب خارجي، وأن الخادم يحتاج أداة تصغير — والخادم عندنا
// بلا ImageMagick.
const DIR = path.join(__dirname, '..', '..', 'web', 'assets', 'logos');

// التصغير: 64 بكسل تكفي لعرض 30 بكسل على شاشة مضاعفة الكثافة.
// الأصل ~500 بكسل و90 كيلوبايت، والمصغَّر 6 — أي 1.8 ميغابايت
// توفير في صفحة فيها خمسون شعاراً.
//
// sips أداة macOS. حين تغيب (خادم Linux مثلاً) يبقى الأصل كما هو:
// أثقل لكنه يعمل. لا نضيف حزمة تصغير لأجل سكربت يُشغَّل يدوياً
// مرة كل موسم.
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const execFileAsync = promisify(execFile);

async function shrink(file) {
  try {
    await execFileAsync('sips', ['-Z', '64', file, '--out', file]);
  } catch { /* الأداة غائبة أو فشلت — نُبقي الأصل */ }
}

const TIMEOUT_MS = 15000;

async function download(url, dest) {
  const res = await fetch(url, { signal: AbortSignal.timeout(TIMEOUT_MS) });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  await fs.writeFile(dest, Buffer.from(await res.arrayBuffer()));
}

async function run() {
  await fs.mkdir(DIR, { recursive: true });

  const { rows } = await db.query(`
    SELECT 'team' AS kind, id, logo_url FROM teams   WHERE logo_url IS NOT NULL
    UNION ALL
    SELECT 'league',       id, logo_url FROM leagues WHERE logo_url IS NOT NULL
  `);

  let saved = 0;
  let skipped = 0;
  let failed = 0;

  for (const row of rows) {
    const name = `${row.kind}-${row.id}.png`;
    const dest = path.join(DIR, name);

    // موجود مسبقاً = لا ننزّله ثانية. الشعارات لا تتغير عملياً،
    // وإعادة التشغيل يجب أن تكون رخيصة كي تصير عادة.
    try {
      await fs.access(dest);
      skipped += 1;
      continue;
    } catch { /* غير موجود — ننزّله */ }

    try {
      await download(row.logo_url, dest);
      await shrink(dest);
      saved += 1;
    } catch (err) {
      // شعار ناقص ليس عطلاً: العارض يرسم حرف الفريق الأول بدلاً منه.
      logger.warn(`[logos] تعذّر ${name}: ${err.message}`);
      failed += 1;
    }
  }

  logger.info(`[logos] نُزّل ${saved} · موجود ${skipped} · فشل ${failed} · المجلد ${DIR}`);
  await db.pool.end();
  await require('../src/config/redis').quit();
}

run().catch((err) => {
  logger.error('[logos] فشل:', err.message);
  process.exit(1);
});
