// teamMapper — تطبيع بيانات الفرق.
//
// شكل عنصر الفريق عند API-Football:
// {
//   team:  { id, name, code, country, founded, logo },
//   venue: { id, name, city, capacity }
// }
// لا نحتاج الملعب ولا سنة التأسيس الآن — نأخذ ما يطابق جدولنا فقط.
// name_ar لا يأتي من المزود أبداً؛ يُملأ لاحقاً من لوحة التحكم،
// لذلك الـ mapper لا يذكره أصلاً والـ repository يحرص على عدم
// الكتابة فوقه عند المزامنة.
function mapTeam(apiItem) {
  return {
    id: apiItem.team.id,
    name_en: apiItem.team.name,
    logo_url: apiItem.team.logo ?? null,
  };
}

module.exports = { mapTeam };
