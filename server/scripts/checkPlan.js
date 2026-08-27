// checkPlan — ماذا فتح لك اشتراكك فعلاً؟
//
// يُشغَّل مرة بعد ترقية الاشتراك للإجابة على ثلاثة أسئلة لا يصح
// تخمينها: ما حدّك اليومي الحقيقي، وأي المواسم صارت متاحة لدوريك،
// وأي موسم هو "الحالي". الخطة المجانية كانت تقصرنا على 2022–2024،
// وضبط SEASON على قيمة لا يخدمها اشتراكك يعطي جدولاً فارغاً بلا
// رسالة خطأ — أسوأ أنواع الأعطال.
//
// التكلفة: طلبان اثنان من حصتك.
//
//   node scripts/checkPlan.js
require('dotenv').config();

const KEY = process.env.FOOTBALL_API_KEY;
const BASE = process.env.FOOTBALL_API_URL || 'https://v3.football.api-sports.io';
const LEAGUE = process.env.LEAGUE_ID || 307;

if (!KEY) {
  console.error('\nFOOTBALL_API_KEY غير مضبوط في .env — ضعه أولاً.\n');
  process.exit(1);
}

async function get(path) {
  const res = await fetch(`${BASE}/${path}`, { headers: { 'x-apisports-key': KEY } });
  const body = await res.json();
  // المزوّد يرد 200 مع مصفوفة errors بدل رمز خطأ — تجاهلها يعني
  // تفسير "مفتاح خاطئ" كأنه "لا نتائج".
  const errors = body.errors;
  if (errors && (Array.isArray(errors) ? errors.length : Object.keys(errors).length)) {
    throw new Error(JSON.stringify(errors));
  }
  return body;
}

(async () => {
  console.log('\n═══ حالة الاشتراك ═══\n');

  const status = await get('status');
  const { subscription, requests, account } = status.response;
  console.log(`الحساب      : ${account?.firstname ?? ''} ${account?.lastname ?? ''}`.trim());
  console.log(`الخطة       : ${subscription.plan}`);
  console.log(`تنتهي في    : ${subscription.end}`);
  console.log(`الحد اليومي : ${requests.limit_day}`);
  console.log(`المستهلك    : ${requests.current}`);

  console.log('\n═══ مواسم الدوري ' + LEAGUE + ' ═══\n');

  const leagues = await get(`leagues?id=${LEAGUE}`);
  const entry = leagues.response[0];
  if (!entry) {
    console.log('لا بيانات لهذا الدوري — تحقق من LEAGUE_ID.');
    return;
  }

  console.log(`الدوري : ${entry.league.name} (${entry.country.name})\n`);

  const seasons = entry.seasons.filter((s) => s.coverage?.fixtures?.events);
  const recent = seasons.slice(-6);
  for (const s of recent) {
    const cov = s.coverage.fixtures;
    const marks = [
      cov.events && 'أحداث',
      cov.statistics_fixtures && 'إحصاءات',
      cov.lineups && 'تشكيلات',
      s.coverage.standings && 'ترتيب',
      s.coverage.predictions && 'توقعات',
    ].filter(Boolean).join(' · ');
    console.log(`  ${s.year}${s.current ? '  ← الحالي' : '        '}  ${s.start} → ${s.end}`);
    console.log(`        ${marks}`);
  }

  const current = entry.seasons.find((s) => s.current);
  console.log('\n═══ ما يجب ضبطه في .env ═══\n');
  console.log(`  SEASON=${current ? current.year : recent.at(-1)?.year}`);
  console.log(`  FOOTBALL_DAILY_LIMIT=${requests.limit_day}`);
  console.log('');
})().catch((err) => {
  console.error('\nفشل الفحص:', err.message);
  console.error('لو كانت الرسالة عن المفتاح، تأكد أنك نسخت المفتاح الجديد كاملاً في .env.\n');
  process.exit(1);
});
