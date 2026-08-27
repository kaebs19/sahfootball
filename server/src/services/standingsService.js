// standingsService — جدول ترتيب جاهز للعرض.
//
// لماذا خدمة وليست منطقاً داخل الـ route؟ نفس الترتيب مطلوب في
// مسارين: /api/standings للتطبيق و/api/admin/standings للوحة.
// نسخ خطوات (مزود ← mapper ← دمج الأسماء العربية) في الملفين كان
// يعني أن أي إصلاح في الدمج لاحقاً يجب تذكّره مرتين. الخطوات هنا
// مرة واحدة، والمساران يستدعيان.
const footballProvider = require('./footballProvider');
const { mapStandings } = require('../mappers/standingsMapper');
const teamRepo = require('../repositories/teamRepo');

// { leagueId, season } اختياريان — الغائب يعود لقيم .env داخل المزود.
async function getStandings(options) {
  const raw = await footballProvider.getStandings(options);
  const standings = mapStandings(raw);

  // أسماء المزود إنجليزية دائماً. نستبدلها بالعربية من قاعدتنا
  // متى ما توفرت الترجمة (وإلا يبقى الاسم الإنجليزي — تدهور لطيف).
  // Map للوصول بزمن ثابت بدل بحث خطي داخل الحلقة.
  const teams = await teamRepo.findAll();
  const nameById = new Map(teams.map((t) => [t.id, t.name]));

  for (const row of standings) {
    row.team_name = nameById.get(row.team_id) ?? row.team_name;
  }

  return standings;
}

module.exports = { getStandings };
