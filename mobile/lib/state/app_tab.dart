// AppTab — التبويب المعروض حالياً، كحالة مشتركة لا حالة داخلية.
//
// لماذا أُخرج هذا من HomeShell؟ لأن للتبويب الآن محرّكاً من خارج
// شجرة الواجهة: الضغط على إشعار يجب أن يفتح شاشة بعينها. بلا حالة
// مشتركة يحتاج ذلك مفتاح GlobalKey على حالة HomeShell ثم نداء
// دالة عليها من طبقة الإشعارات — وهو ربط هشّ يكسره أي تغيير في
// بناء الشجرة، ويصعب اختباره.
//
// ChangeNotifier يجعل الأمر تحديث حالة كالمعتاد في هذا المشروع:
// الإشعار يقول "التبويب 0"، وHomeShell يُعاد بناؤه. نفس منطق
// Session مع شاشة الدخول.
import 'package:flutter/foundation.dart';

class AppTab extends ChangeNotifier {
  // الأرقام تطابق ترتيب HomeShell: المباريات، مباشر، العرش، ملفي.
  static const matches = 0;
  static const live = 1;
  static const leaderboard = 2;
  static const profile = 3;

  int _index = matches;
  int get index => _index;

  void select(int value) {
    if (value == _index || value < 0 || value > profile) return;
    _index = value;
    notifyListeners();
  }

  /// مجلس ينتظر أن يُفتح — طلب وصل من إشعار («فلان يطلب الانضمام»).
  ///
  /// نفس المبدأ: الإشعار لا يمسّ الشجرة، بل يضع طلباً هنا، وويدجت
  /// داخل الشجرة (HomeShell) يلتقطه بـ [takePendingGroup] ويدفع
  /// الشاشة. «يأخذ» لا «يقرأ»: الطلب يُستهلك مرة واحدة كي لا تُفتح
  /// الشاشة مرتين مع كل إعادة بناء.
  String? _pendingGroupId;

  void openGroup(String groupId) {
    _pendingGroupId = groupId;
    _index = leaderboard;
    notifyListeners();
  }

  String? takePendingGroup() {
    final id = _pendingGroupId;
    _pendingGroupId = null;
    return id;
  }

  /// رمز دعوة وصل من رابط (sahfootball.com/join/XXXXXX) — نفس آلية
  /// المجلس المعلّق: الرابط يضع الرمز هنا، وHomeShell يفتح شاشة
  /// الدعوة. يعمل للضيف أيضاً لأن المعاينة عامة.
  String? _pendingInviteCode;

  void openInvite(String code) {
    _pendingInviteCode = code;
    _index = leaderboard;
    notifyListeners();
  }

  String? takePendingInvite() {
    final code = _pendingInviteCode;
    _pendingInviteCode = null;
    return code;
  }
}
