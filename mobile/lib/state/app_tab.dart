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
}
