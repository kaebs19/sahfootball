// standingsMapper — تطبيع جدول الترتيب.
//
// الترتيب لا يُخزَّن في قاعدة البيانات: هو بيانات مشتقة يحسبها
// المزود، وتغييره يعني إعادة جلبه كاملاً — الكاش (ساعة) يكفيه.
// لذلك هذا الـ mapper يُطبّع للعرض المباشر عبر الـ API وليس للتخزين.
//
// شكل استجابة المزود متداخل بغرابة:
// response[0].league.standings[0] هي المصفوفة الفعلية للفرق.
// المصفوفة الخارجية standings[...] موجودة لأن بعض الدوريات تنقسم
// لمجموعات (مثل دوريات أمريكا الجنوبية) — دوري روشن مجموعة واحدة.
function mapStandings(apiResponse) {
  const rows = apiResponse?.[0]?.league?.standings?.[0] ?? [];

  return rows.map((row) => ({
    rank: row.rank,
    team_id: row.team.id,
    team_name: row.team.name, // سيُستبدل بالاسم العربي في الـ route لو توفر
    logo_url: row.team.logo ?? null,
    points: row.points,
    played: row.all.played,
    win: row.all.win,
    draw: row.all.draw,
    lose: row.all.lose,
    goals_for: row.all.goals.for,
    goals_against: row.all.goals.against,
    goals_diff: row.goalsDiff,
    form: row.form ?? null, // آخر النتائج كنص مثل "WWDLW"
  }));
}

module.exports = { mapStandings };
