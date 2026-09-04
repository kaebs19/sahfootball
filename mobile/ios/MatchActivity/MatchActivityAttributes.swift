// صفات النشاط الحيّ وحالته — الملف الوحيد المشترك بين التطبيق
// والامتداد. النوعان يجب أن يتطابقا حرفياً على الطرفين وإلا رُفض
// النشاط بصمت، ولذلك يُترجَم الملف مرتين (في Runner وفي MatchActivity)
// لا يُنسخ.
//
// وأسماء الحقول هي نفسها التي يرسلها السيرفر في content-state
// و attributes (راجع server/src/services/liveActivityService.js):
// ActivityKit يفكّ JSON الدفعة بهذه الأسماء بالضبط.
import ActivityKit
import Foundation

struct MatchActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var goalsHome: Int
    var goalsAway: Int
    /// الدقيقة الرسمية من المزوّد؛ غائبة في الاستراحة وبعد النهاية.
    var elapsed: Int?
    /// طور المزوّد الخام: 1H / HT / 2H / ET / P / FT…
    var phase: String
    /// scheduled / live / finished — حالتنا المختزلة.
    var status: String
  }

  var fixtureId: Int
  var home: String
  var away: String
  /// توقّع صاحب الهاتف. غائب لمن يتابع بلا توقّع.
  var predHome: Int?
  var predAway: Int?
}
