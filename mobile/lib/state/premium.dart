// Premium — امتيازات اللاعب الحالية، كحالة مشتركة.
//
// لماذا حالة مستقلة لا حقل في Session؟ لأنها تتغيّر لأسباب لا علاقة
// لها بالجلسة: شراء ينجح، اشتراك ينتهي في منتصف الاستعمال، معزّز
// يُنفق فينقص الرصيد. وSession مسؤولة عن "من أنت"، ودفعُ "ماذا
// تملك" فيها يجعل كل تغيّر رصيد يُعيد بناء شجرة التطبيق كاملة.
//
// وتستمع إلى Session بدل أن تُنادى من كل شاشة: الدخول والخروج
// وتبديل الحساب كلها تغيّر الامتيازات، ونسيان النداء في مسار واحد
// منها يعني لاعباً يرى تاج غيره.
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../models/premium.dart';
import 'session.dart';

class Premium extends ChangeNotifier {
  final ApiClient api;
  final Session session;

  Premium(this.api, this.session) {
    session.addListener(_onSession);
    _onSession();
  }

  Entitlements _entitlements = Entitlements.unknown;
  Entitlements get value => _entitlements;

  bool get isPremium => _entitlements.premium;

  /// هل تُعرض الإعلانات؟ الضيف يراها، والمشترك لا.
  bool get showAds => _entitlements.ads;

  SessionStatus? _lastStatus;

  void _onSession() {
    final status = session.status;
    if (status == _lastStatus) return;
    _lastStatus = status;
    if (status == SessionStatus.loggedIn) {
      refresh();
    } else {
      // الخروج يمسح الامتيازات فوراً لا بعد رحلة شبكة: من خرج
      // يجب ألا تبقى شاشته بلا إعلانات لأن التاج كان لمن قبله.
      _set(Entitlements.unknown);
    }
  }

  Future<void> refresh() async {
    if (session.status != SessionStatus.loggedIn) return;
    try {
      _set(await api.entitlements());
    } on ApiException catch (e) {
      // فشل القراءة لا يمنح ولا يمنع: نُبقي آخر ما عرفناه. تصفير
      // الامتيازات عند انقطاع شبكة كان سيُظهر إعلانات لمشترك دفع.
      debugPrint('[premium] تعذّرت قراءة الامتيازات: ${e.message}');
    }
  }

  void _set(Entitlements value) {
    _entitlements = value;
    notifyListeners();
  }

  /// بعد شراء ناجح — الردّ يحمل الامتيازات الجديدة فلا نعيد سؤالها.
  void adopt(Entitlements value) => _set(value);

  @override
  void dispose() {
    session.removeListener(_onSession);
    super.dispose();
  }
}
