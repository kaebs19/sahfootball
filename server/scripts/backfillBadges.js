// تعبئة الأوسمة بأثر رجعي — تشغيل لمرة واحدة بعد نشر الميزة.
//
// لماذا سكربت أصلاً؟ الأوسمة تُمنح عند الاحتساب وعند فتح الملف
// الشخصي، فمن لعب طويلاً قبل وجود الميزة ينالها أول مرة يفتح فيها
// شاشته — وهذا يكفي عملياً. لكن الأوسمة تدخل في إشعارات ولوحة الأدمن
// وأرقام "كم مستخدماً نال كذا"، وهذه تقرأ الجدول لا الشاشة، فتقرأ
// صفراً حتى يفتح الناس تطبيقاتهم واحداً واحداً. هذا السكربت يجعل
// الجدول صادقاً من لحظة النشر.
//
// آمن التكرار تماماً: شغّله مرة أو عشراً، ON CONFLICT DO NOTHING
// يمنع التكرار ولا يزحزح earned_at (انظر الهجرة 011).
//
// الاستخدام: node scripts/backfillBadges.js
require('dotenv').config();
const { pool } = require('../src/config/db');
const badgeService = require('../src/services/badgeService');

async function main() {
  const { rows: users } = await pool.query('SELECT id FROM users ORDER BY created_at');
  console.log(`evaluating ${users.length} users...`);

  let awardedCount = 0;
  let usersAwarded = 0;
  let failed = 0;

  // بالتتابع لا بـ Promise.all: عملية إدارية تعمل مرة، ولا سبب
  // لإغراق الـ pool (عشر اتصالات) بآلاف الاستعلامات المتوازية بينما
  // السيرفر يخدم مستخدمين حقيقيين في نفس اللحظة. البطء هنا مقبول.
  for (const user of users) {
    try {
      // evaluate الصريحة لا evaluateQuietly: هنا نريد الخطأ ظاهراً
      // ومعه صاحبه، لا مبتلعاً في سجل السيرفر. والحلقة تكمل على أي
      // حال — مستخدم واحد معطوب يجب ألا يوقف تعبئة الباقين.
      const awarded = await badgeService.evaluate(user.id);
      if (awarded.length > 0) {
        usersAwarded += 1;
        awardedCount += awarded.length;
        console.log(`  ${user.id}: ${awarded.join(', ')}`);
      }
    } catch (err) {
      failed += 1;
      console.error(`  FAILED ${user.id}: ${err.message}`);
    }
  }

  console.log(
    `done — ${awardedCount} badges awarded to ${usersAwarded} users ` +
    `(${users.length} evaluated, ${failed} failed)`
  );
  await pool.end();
  if (failed > 0) process.exitCode = 1; // كي يلاحظ النشر الآلي الفشل
}

main();
