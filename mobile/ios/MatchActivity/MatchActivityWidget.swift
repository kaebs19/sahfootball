// النشاط الحيّ — النتيجة على شاشة القفل وفي الجزيرة الديناميكية.
//
// ما يرسمه هذا الملف هو ما يراه المستخدم دون أن يفتح التطبيق: فريقان،
// نتيجة كبيرة، دقيقة، وتوقّعه هو تحتها بحكمه («مضبوط الآن» ذهبياً).
// الهوية نفسها: ليلٌ وذهبٌ محصور في الملكية، وأخضر للصح، وأحمر
// للجاري والخطأ.
//
// بلا شعارات: الامتداد لا يحمّل صوراً من الشبكة، وشعار مكسور أسوأ
// من اسم واضح. الاسم يكفي على شاشة القفل.
//
// وكل رقم يمرّ بـ Text(verbatim:): Text العادية تُعرّب الأرقام مع
// لغة الجهاز (٢ - ١)، والتطبيق كله بأرقام غربية — راجع
// mobile/lib/format.dart. وقعت فعلاً على شاشة القفل قبل هذا السطر.
import ActivityKit
import SwiftUI
import WidgetKit

// ── ألوان الهوية (نسخة من mobile/lib/brand.dart) ──────────────────
private extension Color {
  static let night = Color(red: 0.039, green: 0.039, blue: 0.039)
  static let surface = Color(red: 0.086, green: 0.086, blue: 0.086)
  static let crown = Color(red: 0.949, green: 0.757, blue: 0.306)
  static let correct = Color(red: 0.071, green: 0.878, blue: 0.494)
  static let wrong = Color(red: 1.0, green: 0.353, blue: 0.306)
  static let textMuted = Color(red: 0.631, green: 0.631, blue: 0.631)
  static let textFaint = Color(red: 0.42, green: 0.42, blue: 0.42)
}

// ── منطق العرض ──────────────────────────────────────────────────────

/// ما يُكتب مكان الدقيقة: الطور يحكم لا الرقم وحده — 45' تقف طوال
/// الاستراحة، و«استراحة» أصدق منها.
private func phaseLabel(_ s: MatchActivityAttributes.ContentState) -> String {
  switch s.phase {
  case "HT": return "استراحة"
  case "BT": return "استراحة الإضافي"
  case "P": return "ركلات الترجيح"
  case "INT", "SUSP": return "متوقفة"
  case "ET": return s.elapsed.map { "إضافي \($0)'" } ?? "وقت إضافي"
  case "AET": return "انتهت بعد الإضافي"
  case "PEN": return "انتهت بالترجيح"
  case "FT", "WO", "AWD": return "انتهت"
  default:
    if s.status == "finished" { return "انتهت" }
    if s.status == "live" { return s.elapsed.map { "\($0)'" } ?? "مباشر" }
    return "قريباً"
  }
}

/// حكم التوقّع مقابل النتيجة الجارية — نفس سلّم السيرفر (مضبوط،
/// فارق، فائز، لا شيء) مختصراً لما يُكتب في سطر واحد.
private enum Verdict {
  case exact, onTrack, off, none

  static func of(_ a: MatchActivityAttributes, _ s: MatchActivityAttributes.ContentState) -> Verdict {
    guard let ph = a.predHome, let pa = a.predAway else { return .none }
    if ph == s.goalsHome && pa == s.goalsAway { return .exact }
    let predicted = (ph - pa).signum()
    let actual = (s.goalsHome - s.goalsAway).signum()
    return predicted == actual ? .onTrack : .off
  }

  var label: String {
    switch self {
    case .exact: return "مضبوط الآن"
    case .onTrack: return "على المسار"
    case .off: return "خارج المسار"
    case .none: return ""
    }
  }

  var color: Color {
    switch self {
    case .exact: return .crown
    case .onTrack: return .correct
    case .off: return .wrong
    case .none: return .textMuted
    }
  }
}

// ── الواجهات ────────────────────────────────────────────────────────

/// شريحة الطور: حمراء للجارية، محايدة لما سواها.
private struct PhasePill: View {
  let state: MatchActivityAttributes.ContentState

  var body: some View {
    let live = state.status == "live"
    HStack(spacing: 5) {
      if live {
        Circle().fill(Color.wrong).frame(width: 6, height: 6)
      }
      Text(verbatim: phaseLabel(state))
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .monospacedDigit()
        .foregroundColor(live ? .wrong : .textMuted)
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 4)
    .background(live ? Color.wrong.opacity(0.14) : Color.white.opacity(0.06))
    .clipShape(Capsule())
  }
}

/// سطر توقّعك وحكمه.
private struct PredictionLine: View {
  let attributes: MatchActivityAttributes
  let state: MatchActivityAttributes.ContentState

  var body: some View {
    if let ph = attributes.predHome, let pa = attributes.predAway {
      let verdict = Verdict.of(attributes, state)
      HStack(spacing: 6) {
        Text(verbatim: "توقعك \(ph) - \(pa)")
          .font(.system(size: 12))
          .monospacedDigit()
          .foregroundColor(.textMuted)
        if state.status != "scheduled" {
          Text("·").foregroundColor(.textFaint)
          Text(verdict.label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(verdict.color)
        }
      }
    }
  }
}

/// شاشة القفل والإشعار المنبثق — العرض الكامل.
private struct LockScreenView: View {
  let context: ActivityViewContext<MatchActivityAttributes>

  var body: some View {
    let a = context.attributes
    let s = context.state
    VStack(spacing: 10) {
      HStack(alignment: .center) {
        Text(a.home)
          .font(.system(size: 15, weight: .bold))
          .lineLimit(2)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
        VStack(spacing: 6) {
          Text(verbatim: "\(s.goalsHome) - \(s.goalsAway)")
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundColor(s.status == "finished" ? .textMuted : .white)
          PhasePill(state: s)
        }
        .frame(minWidth: 110)
        Text(a.away)
          .font(.system(size: 15, weight: .bold))
          .lineLimit(2)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
      }
      PredictionLine(attributes: a, state: s)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .foregroundColor(.white)
    .environment(\.layoutDirection, .rightToLeft)
    .activityBackgroundTint(Color.night)
    .activitySystemActionForegroundColor(.white)
  }
}

struct MatchActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: MatchActivityAttributes.self) { context in
      LockScreenView(context: context)
    } dynamicIsland: { context in
      let a = context.attributes
      let s = context.state
      return DynamicIsland {
        // الجزيرة الموسّعة (ضغطة مطوّلة): نفس ما على شاشة القفل.
        DynamicIslandExpandedRegion(.leading) {
          Text(a.home)
            .font(.system(size: 13, weight: .bold))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(a.away)
            .font(.system(size: 13, weight: .bold))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 6)
        }
        DynamicIslandExpandedRegion(.center) {
          VStack(spacing: 4) {
            Text(verbatim: "\(s.goalsHome) - \(s.goalsAway)")
              .font(.system(size: 26, weight: .bold, design: .rounded))
              .monospacedDigit()
            PhasePill(state: s)
          }
        }
        DynamicIslandExpandedRegion(.bottom) {
          PredictionLine(attributes: a, state: s)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        }
      } compactLeading: {
        // مضغوطة: النتيجة يساراً والدقيقة يميناً — رقمان يُقرآن
        // بنظرة من أعلى الشاشة.
        Text(verbatim: "\(s.goalsHome)-\(s.goalsAway)")
          .font(.system(size: 13, weight: .bold, design: .rounded))
          .monospacedDigit()
          .padding(.leading, 4)
      } compactTrailing: {
        Text(verbatim: s.status == "live" ? (s.elapsed.map { "\($0)'" } ?? "●") : phaseLabel(s))
          .font(.system(size: 12, weight: .semibold))
          .monospacedDigit()
          .foregroundColor(s.status == "live" ? .wrong : .textMuted)
          .padding(.trailing, 4)
      } minimal: {
        Text(verbatim: "\(s.goalsHome)-\(s.goalsAway)")
          .font(.system(size: 11, weight: .bold, design: .rounded))
          .monospacedDigit()
      }
      .keylineTint(Color.crown)
    }
  }
}

@main
struct MatchActivityBundle: WidgetBundle {
  var body: some Widget {
    MatchActivityWidget()
  }
}
